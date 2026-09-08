part of 'sqlite_chat_persistence.dart';

class _StoryJournal {
  _StoryJournal(this.store);
  final SqliteChatPersistence store;
  static const delta = ReversibleJsonDelta();
  List<String> keys(String id) =>
      ['memory_revision_v1_$id', 'memory_locks_v1_$id'];

  Future<void> schema(DatabaseExecutor db) async {
    await db.execute(
        'CREATE TABLE IF NOT EXISTS story_heads (branch_id TEXT PRIMARY KEY REFERENCES conversation_branches(id) ON DELETE CASCADE, revision INTEGER NOT NULL, metadata TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS story_turns (id TEXT NOT NULL, branch_id TEXT NOT NULL REFERENCES conversation_branches(id) ON DELETE CASCADE, contact_id TEXT NOT NULL, start_sequence INTEGER NOT NULL, before_revision INTEGER NOT NULL, input TEXT NOT NULL, status TEXT NOT NULL, PRIMARY KEY(branch_id,id))');
    await db.execute(
        'CREATE TABLE IF NOT EXISTS story_operations (id INTEGER PRIMARY KEY AUTOINCREMENT, branch_id TEXT NOT NULL REFERENCES conversation_branches(id) ON DELETE CASCADE, revision INTEGER NOT NULL, turn_id TEXT, delta TEXT NOT NULL, UNIQUE(branch_id,revision))');
  }

  Future<Map<String, dynamic>> projection(
      DatabaseExecutor db, String contactId) async {
    final contact = await store._readContact(db, contactId);
    final metadata = <String, dynamic>{};
    for (final key in keys(contactId)) {
      final rows =
          await db.query('app_meta', where: 'meta_key = ?', whereArgs: [key]);
      metadata[key] = rows.isEmpty ? null : rows.single['meta_value'];
    }
    return {'contact': contact.toJson(), 'metadata': metadata};
  }

  Future<Map<String, Object?>> head(
      DatabaseExecutor db, String branchId) async {
    var rows = await db
        .query('story_heads', where: 'branch_id = ?', whereArgs: [branchId]);
    if (rows.isEmpty) {
      final branches = await db.query('conversation_branches',
          where: 'id = ?', whereArgs: [branchId]);
      final p = await projection(db, branches.single['contact_id'] as String);
      await db.insert('story_heads', {
        'branch_id': branchId,
        'revision': 0,
        'metadata': jsonEncode(p['metadata'])
      });
      rows = await db
          .query('story_heads', where: 'branch_id = ?', whereArgs: [branchId]);
    }
    return rows.single;
  }

  Future<String> active(DatabaseExecutor db, String id) async {
    final rows = await db.query('conversation_branches',
        where: 'contact_id = ? AND is_active = 1', whereArgs: [id]);
    if (rows.isNotEmpty) return rows.single['id'] as String;
    return store._syncActiveBranchSnapshot(
        db, await store._readContact(db, id));
  }

  Future<int> record(
      DatabaseExecutor db, String contactId, Map<String, dynamic> before,
      {String? turnId}) async {
    final branchId = await active(db, contactId);
    final h = await head(db, branchId);
    final after = await projection(db, contactId);
    final changes = delta.between(before, after);
    if (changes.isEmpty && turnId == null) return h['revision'] as int;
    if (turnId == null) await requireIdle(db, branchId);
    final revision = (h['revision'] as int) + 1;
    await db.insert('story_operations', {
      'branch_id': branchId,
      'revision': revision,
      'turn_id': turnId,
      'delta': jsonEncode(changes)
    });
    await db.update('story_heads',
        {'revision': revision, 'metadata': jsonEncode(after['metadata'])},
        where: 'branch_id = ?', whereArgs: [branchId]);
    return revision;
  }

  Future<void> writeMetadata(DatabaseExecutor db, Map values) async {
    for (final entry in values.entries) {
      if (entry.value == null) {
        await db
            .delete('app_meta', where: 'meta_key = ?', whereArgs: [entry.key]);
      } else {
        await db.insert(
            'app_meta', {'meta_key': entry.key, 'meta_value': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<void> requireIdle(DatabaseExecutor db, String branchId) async {
    if ((await db.query('story_turns',
            where: 'branch_id = ? AND status = ?',
            whereArgs: [branchId, 'pending'],
            limit: 1))
        .isNotEmpty) {
      throw StateError('当前故事仍在生成');
    }
  }

  Future<StoryTurnHandle> begin(String contactId, Message message) =>
      store._db.transaction((db) async {
        if (message.turnId == null || message.role != MessageRole.user) {
          throw StateError('缺少轮次标识');
        }
        final branchId = await active(db, contactId);
        final pending = await db.query('story_turns',
            where: 'branch_id = ? AND status = ?',
            whereArgs: [branchId, 'pending']);
        if (pending.isNotEmpty) throw StateError('当前故事已有未结束请求');
        final h = await head(db, branchId);
        final beforeRevision = (h['revision'] as int) + 1;
        await db.update('story_heads', {'revision': beforeRevision},
            where: 'branch_id = ?', whereArgs: [branchId]);
        final count = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM messages WHERE contact_id = ?',
            [contactId]))!;
        await db.insert('story_turns', {
          'id': message.turnId,
          'branch_id': branchId,
          'contact_id': contactId,
          'start_sequence': count,
          'before_revision': beforeRevision,
          'input': message.content,
          'status': 'pending'
        });
        await store._writeMessageRows(db, contactId, [message],
            startSequence: count);
        await store._syncActiveBranchSnapshot(
            db, await store._readContact(db, contactId));
        return StoryTurnHandle(
            id: message.turnId!,
            contactId: contactId,
            branchId: branchId,
            startSequence: count,
            beforeRevision: beforeRevision);
      });
  Future<void> check(DatabaseExecutor db, StoryTurnHandle turn) async {
    if (await active(db, turn.contactId) != turn.branchId ||
        (await head(db, turn.branchId))['revision'] != turn.beforeRevision) {
      throw StateError('故事分支或版本已变化');
    }
    final rows = await db.query('story_turns',
        where: 'branch_id = ? AND id = ? AND status = ?',
        whereArgs: [turn.branchId, turn.id, 'pending']);
    if (rows.length != 1 ||
        rows.single['start_sequence'] != turn.startSequence ||
        rows.single['before_revision'] != turn.beforeRevision ||
        rows.single['contact_id'] != turn.contactId) {
      throw StateError('轮次已经结束或恢复位置不匹配');
    }
  }

  Future<void> saveAttempt(
      DatabaseExecutor db, StoryTurnHandle turn, List<Message> messages) async {
    if (messages.any((m) => m.turnId != turn.id)) throw StateError('消息不属于当前轮次');
    await db.delete('messages',
        where: 'contact_id = ? AND sequence >= ?',
        whereArgs: [turn.contactId, turn.startSequence]);
    await store._writeMessageRows(db, turn.contactId, messages,
        startSequence: turn.startSequence);
  }

  Future<void> commit(
          StoryTurnHandle turn, Contact contact, List<Message> messages) =>
      store._db.transaction((db) async {
        await check(db, turn);
        if (contact.id != turn.contactId ||
            messages.any((m) => m.status != MessageStatus.sent) ||
            !messages.any((m) => m.role == MessageRole.assistant)) {
          throw StateError('不能提交不完整轮次');
        }
        final before = await projection(db, turn.contactId);
        await store._writeContact(db, contact);
        await saveAttempt(db, turn, messages);
        await store._syncActiveBranchSnapshot(db, contact);
        final revision = await record(db, contact.id, before, turnId: turn.id);
        await db.update('story_turns', {'status': 'completed'},
            where: 'branch_id = ? AND id = ?',
            whereArgs: [turn.branchId, turn.id]);
        final reply =
            messages.lastWhere((m) => m.role == MessageRole.assistant);
        // 新自动检查点只存位置与版本；内容通过可逆日志按需重建。
        await db.insert('conversation_checkpoints', {
          'id': 'checkpoint-${turn.id}',
          'contact_id': contact.id,
          'branch_id': turn.branchId,
          'source_message_id': reply.id,
          'label': reply.content.length > 32
              ? reply.content.substring(0, 32)
              : reply.content,
          'contact_payload': '',
          'messages_payload': '[]',
          'message_count': turn.startSequence + messages.length,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'is_key': 0,
          'story_revision': revision
        });
      });
  Future<void> abort(StoryTurnHandle turn, List<Message> messages) =>
      store._db.transaction((db) async {
        await check(db, turn);
        await saveAttempt(
            db,
            turn,
            messages
                .map((m) => m.copyWith(
                    status: m.status == MessageStatus.cancelled
                        ? MessageStatus.cancelled
                        : MessageStatus.failed))
                .toList());
        await db.update('story_turns', {'status': 'aborted'},
            where: 'branch_id = ? AND id = ?',
            whereArgs: [turn.branchId, turn.id]);
        await store._syncActiveBranchSnapshot(
            db, await store._readContact(db, turn.contactId));
      });
  Future<void> recover() => store._db.transaction((db) async {
        final turns = await db
            .query('story_turns', where: 'status = ?', whereArgs: ['pending']);
        for (final turn in turns) {
          final id = turn['contact_id'] as String;
          final messages = await store._readMessages(db, id);
          for (final message in messages.where((m) => m.turnId == turn['id'])) {
            await db.update(
                'messages',
                {
                  'payload': jsonEncode(message
                      .copyWith(status: MessageStatus.cancelled)
                      .toJson())
                },
                where: 'id = ?',
                whereArgs: [message.id]);
          }
          await db.update('story_turns', {'status': 'aborted'},
              where: 'branch_id = ? AND id = ?',
              whereArgs: [turn['branch_id'], turn['id']]);
          await store._syncActiveBranchSnapshot(
              db, await store._readContact(db, id));
        }
      });
  Future<Map<String, dynamic>> atRevision(
      DatabaseExecutor db, String branchId, int revision) async {
    if (revision < 0 ||
        revision > ((await head(db, branchId))['revision'] as int)) {
      throw StateError('恢复版本不存在');
    }
    final row = (await db.query('conversation_branches',
            where: 'id = ?', whereArgs: [branchId]))
        .single;
    final h = await head(db, branchId);
    dynamic value = {
      'contact':
          Contact.fromJson(store._decodeMap(row['contact_payload'])).toJson(),
      'metadata': jsonDecode(h['metadata'] as String)
    };
    final ops = await db.query('story_operations',
        where: 'branch_id = ? AND revision > ?',
        whereArgs: [branchId, revision],
        orderBy: 'revision DESC');
    for (final op in ops) {
      value = delta.apply(value, jsonDecode(op['delta'] as String) as List,
          reverse: true);
    }
    return Map<String, dynamic>.from(value as Map);
  }

  Future<Map<String, Object?>> materialize(
      DatabaseExecutor db, Map<String, Object?> row) async {
    if (row['contact_payload'] != '') return row;
    final state = await atRevision(
        db, row['branch_id'] as String, row['story_revision'] as int);
    final branch = (await db.query('conversation_branches',
            where: 'id = ?', whereArgs: [row['branch_id']]))
        .single;
    final messages = store
        ._messagesFromPayload(branch['messages_payload'])
        .take(row['message_count'] as int)
        .toList();
    return {
      ...row,
      'contact_payload': jsonEncode(state['contact']),
      'messages_payload': jsonEncode(messages.map((m) => m.toJson()).toList())
    };
  }

  Future<Map?> checkpointMetadata(DatabaseExecutor db,
      Map<String, Object?> checkpoint, String contactId) async {
    final revision = checkpoint['story_revision'] as int?;
    if (revision != null) {
      return (await atRevision(
          db, checkpoint['branch_id'] as String, revision))['metadata'] as Map;
    }
    // 老检查点没有元数据快照；存在锁或修订时无法证明恢复前状态。
    final metadata = (await projection(db, contactId))['metadata'] as Map;
    if (metadata.values.any((v) => v != null && v != '' && v != '[]')) {
      return null;
    }
    return {for (final key in keys(contactId)) key: null};
  }

  Future<StoryTruncation?> preview(String contactId, String? messageId) =>
      store._db.transaction((db) async {
        final branchId = await active(db, contactId);
        final h = await head(db, branchId);
        final all = await store._readMessages(db, contactId);
        if (all.isEmpty) return null;
        final message = messageId == null
            ? all.lastWhere(
                (m) => m.turnId != null || m.role == MessageRole.user,
                orElse: () => all.last)
            : all.where((m) => m.id == messageId).firstOrNull;
        if (message == null) return null;
        final turns = await db.query('story_turns',
            where: 'branch_id = ?',
            whereArgs: [branchId],
            orderBy: 'start_sequence ASC');
        final found = turns.where((t) => t['id'] == message.turnId).firstOrNull;
        if (found != null) {
          final start = found['start_sequence'] as int;
          return StoryTruncation(
              contactId: contactId,
              branchId: branchId,
              startSequence: start,
              expectedRevision: h['revision'] as int,
              beforeRevision: found['before_revision'] as int,
              turnCount: turns
                  .where((t) => (t['start_sequence'] as int) >= start)
                  .length,
              input: found['input'] as String,
              turnId: found['id'] as String);
        }
        // 老消息只在恰好存在此前完整前缀检查点时提供恢复，绝不猜测记忆。
        var index = all.indexOf(message);
        while (index >= 0 &&
            (all[index].role != MessageRole.user ||
                all[index].id.startsWith('debug-'))) {
          index--;
        }
        if (index < 0) return null;
        final checkpoints = await db.query('conversation_checkpoints',
            where: 'branch_id = ? AND message_count = ?',
            whereArgs: [branchId, index]);
        for (final raw in checkpoints) {
          final cp = await materialize(db, raw);
          final prefix = store._messagesFromPayload(cp['messages_payload']);
          if (!delta.same(prefix.map((m) => m.toJson()).toList(),
              all.take(index).map((m) => m.toJson()).toList())) {
            continue;
          }
          if (await checkpointMetadata(db, cp, contactId) == null) continue;
          return StoryTruncation(
              contactId: contactId,
              branchId: branchId,
              startSequence: index,
              expectedRevision: h['revision'] as int,
              beforeRevision: cp['story_revision'] as int? ?? 0,
              turnCount: all
                  .skip(index)
                  .where((m) =>
                      m.role == MessageRole.user && !m.id.startsWith('debug-'))
                  .length,
              input: all[index].content,
              legacyCheckpointId: cp['id'] as String);
        }
        return null;
      });
  Future<void> truncate(StoryTruncation target) =>
      store._db.transaction((db) async {
        await requireIdle(db, target.branchId);
        if (await active(db, target.contactId) != target.branchId ||
            (await head(db, target.branchId))['revision'] !=
                target.expectedRevision) {
          throw StateError('故事已变化，请重新选择撤销位置');
        }
        final all = await store._readMessages(db, target.contactId);
        if (target.startSequence < 0 || target.startSequence > all.length) {
          throw StateError('消息位置已变化');
        }
        Map<String, dynamic> restored;
        if (target.legacyCheckpointId != null) {
          final rows = await db.query('conversation_checkpoints',
              where: 'id = ? AND branch_id = ?',
              whereArgs: [target.legacyCheckpointId, target.branchId]);
          if (rows.isEmpty) throw StateError('检查点不存在');
          final cp = await materialize(db, rows.single);
          if (!delta.same(
              store
                  ._messagesFromPayload(cp['messages_payload'])
                  .map((m) => m.toJson())
                  .toList(),
              all.take(target.startSequence).map((m) => m.toJson()).toList())) {
            throw StateError('旧检查点与当前历史不匹配');
          }
          final metadata = await checkpointMetadata(db, cp, target.contactId);
          if (metadata == null) throw StateError('旧检查点缺少记忆元数据恢复依据');
          restored = {
            'contact': store._decodeMap(cp['contact_payload']),
            'metadata': metadata
          };
        } else {
          final turn = await db.query('story_turns',
              where: 'branch_id = ? AND id = ? AND start_sequence = ?',
              whereArgs: [
                target.branchId,
                target.turnId,
                target.startSequence
              ]);
          if (turn.isEmpty ||
              turn.single['before_revision'] != target.beforeRevision) {
            throw StateError('轮次不存在或恢复版本不匹配');
          }
          restored =
              await atRevision(db, target.branchId, target.beforeRevision);
        }
        final contact = Contact.fromJson(
            Map<String, dynamic>.from(restored['contact'] as Map));
        if (contact.id != target.contactId) throw StateError('恢复数据不属于当前故事');
        await store._writeContact(db, contact);
        await writeMetadata(db, restored['metadata'] as Map);
        await db.delete('messages',
            where: 'contact_id = ? AND sequence >= ?',
            whereArgs: [target.contactId, target.startSequence]);
        final cps = await db.query('conversation_checkpoints',
            where: 'branch_id = ?', whereArgs: [target.branchId]);
        for (final cp in cps) {
          final count = cp['message_count'] as int;
          final revision = cp['story_revision'] as int?;
          var remove = count > target.startSequence ||
              (revision != null && revision > target.beforeRevision);
          if (!remove) {
            final snapshot = await materialize(db, cp);
            remove = !delta.same(
                store
                    ._messagesFromPayload(snapshot['messages_payload'])
                    .map((m) => m.toJson())
                    .toList(),
                all.take(count).map((m) => m.toJson()).toList());
          }
          if (!remove) continue;
          await db.update('conversation_branches', {'fork_checkpoint_id': null},
              where: 'fork_checkpoint_id = ?', whereArgs: [cp['id']]);
          await db.delete('conversation_checkpoints',
              where: 'id = ?', whereArgs: [cp['id']]);
        }
        await db.delete('story_turns',
            where: 'branch_id = ? AND start_sequence >= ?',
            whereArgs: [target.branchId, target.startSequence]);
        await db.delete('story_operations',
            where: 'branch_id = ? AND revision > ?',
            whereArgs: [target.branchId, target.beforeRevision]);
        await db.update(
            'story_heads',
            {
              'revision': target.expectedRevision + 1,
              'metadata': jsonEncode(restored['metadata'])
            },
            where: 'branch_id = ?',
            whereArgs: [target.branchId]);
        await store._syncActiveBranchSnapshot(db, contact);
      });
  Future<void> fork(DatabaseExecutor db, Map<String, Object?> checkpoint,
      String newId) async {
    final source = checkpoint['branch_id'] as String;
    final revision = checkpoint['story_revision'] as int?;
    if (revision == null) return;
    final p = await atRevision(db, source, revision);
    await db.insert('story_heads', {
      'branch_id': newId,
      'revision': revision,
      'metadata': jsonEncode(p['metadata'])
    });
    for (final row in await db.query('story_operations',
        where: 'branch_id = ? AND revision <= ?',
        whereArgs: [source, revision])) {
      await db
          .insert('story_operations', {...row, 'id': null, 'branch_id': newId});
    }
    for (final row in await db.query('story_turns',
        where: 'branch_id = ? AND start_sequence < ?',
        whereArgs: [source, checkpoint['message_count']])) {
      await db.insert('story_turns', {...row, 'branch_id': newId});
    }
  }

  Future<void> activateMetadata(DatabaseExecutor db, String branchId) async {
    final rows = await db
        .query('story_heads', where: 'branch_id = ?', whereArgs: [branchId]);
    final branch = (await db.query('conversation_branches',
            where: 'id = ?', whereArgs: [branchId]))
        .single;
    final metadata = rows.isEmpty
        ? {for (final key in keys(branch['contact_id'] as String)) key: null}
        : jsonDecode(rows.single['metadata'] as String) as Map;
    await writeMetadata(db, metadata);
  }

  Future<Map<String, dynamic>> export(DatabaseExecutor db) async => {
        'heads': await db.query('story_heads'),
        'turns': await db.query('story_turns'),
        'operations': await db.query('story_operations', orderBy: 'id ASC')
      };
  void validateProjection(dynamic value, String contactId) {
    if (value is! Map ||
        value.length != 2 ||
        value['contact'] is! Map ||
        value['metadata'] is! Map) {
      throw const FormatException('剧情日志结构错误');
    }
    if (Contact.fromJson(Map<String, dynamic>.from(value['contact'] as Map))
            .id !=
        contactId) {
      throw const FormatException('剧情日志联系人错误');
    }
    final metadata = value['metadata'] as Map;
    if (metadata.length != 2 ||
        !keys(contactId).every(metadata.containsKey) ||
        metadata.values.any((v) => v != null && v is! String)) {
      throw const FormatException('记忆元数据不匹配');
    }
    final locks = metadata['memory_locks_v1_$contactId'];
    if (locks != null && locks != '') {
      final parsed = jsonDecode(locks as String);
      if (parsed is! List || parsed.any((id) => id is! String)) {
        throw const FormatException('记忆锁格式错误');
      }
    }
    final revision = metadata['memory_revision_v1_$contactId'];
    if (revision != null && revision != '') {
      MemoryRevisionRecord.fromJson(
          Map<String, dynamic>.from(jsonDecode(revision as String) as Map));
    }
  }

  Future<void> restore(
      DatabaseExecutor db, Map<String, dynamic> archive) async {
    for (final pair in {
      'heads': 'story_heads',
      'turns': 'story_turns',
      'operations': 'story_operations'
    }.entries) {
      await db.delete(pair.value);
      final items = archive[pair.key] ?? [];
      if (items is! List) throw const FormatException('轮次日志格式错误');
      for (final row in items) {
        if (row is! Map) throw const FormatException('轮次日志格式错误');
        await db.insert(pair.value, Map<String, Object?>.from(row));
      }
    }
    for (final branch in await db.query('conversation_branches')) {
      final id = branch['id'] as String;
      final contactId = branch['contact_id'] as String;
      final contact =
          Contact.fromJson(store._decodeMap(branch['contact_payload']));
      if (contact.id != contactId) throw const FormatException('分支联系人不匹配');
      final messages = store._messagesFromPayload(branch['messages_payload']);
      if (branch['is_active'] == 1) {
        if (!delta.same(contact.toJson(),
                (await store._readContact(db, contactId)).toJson()) ||
            !delta.same(
                messages.map((m) => m.toJson()).toList(),
                (await store._readMessages(db, contactId))
                    .map((m) => m.toJson())
                    .toList())) {
          throw const FormatException('备份当前分支与正文不一致');
        }
      }
      final heads = await db
          .query('story_heads', where: 'branch_id = ?', whereArgs: [id]);
      final turns = await db.query('story_turns',
          where: 'branch_id = ?',
          whereArgs: [id],
          orderBy: 'start_sequence ASC');
      final ops = await db.query('story_operations',
          where: 'branch_id = ?', whereArgs: [id], orderBy: 'revision DESC');
      if (heads.isEmpty) {
        if (turns.isNotEmpty || ops.isNotEmpty) {
          throw const FormatException('缺少轮次版本');
        }
        continue;
      }
      final revision = heads.single['revision'] as int;
      if (revision < 0) throw const FormatException('轮次版本错误');
      dynamic value = {
        'contact': contact.toJson(),
        'metadata': jsonDecode(heads.single['metadata'] as String)
      };
      validateProjection(value, contactId);
      for (final op in ops) {
        if ((op['revision'] as int) > revision ||
            (op['revision'] as int) <= 0) {
          throw const FormatException('日志版本错误');
        }
        value = delta.apply(value, jsonDecode(op['delta'] as String) as List,
            reverse: true);
        validateProjection(value, contactId);
      }
      var previous = -1;
      for (final turn in turns) {
        final start = turn['start_sequence'] as int;
        final before = turn['before_revision'] as int;
        if (turn['contact_id'] != contactId ||
            start <= previous ||
            start >= messages.length ||
            before < 0 ||
            before > revision ||
            !['completed', 'aborted', 'pending'].contains(turn['status']) ||
            messages[start].turnId != turn['id'] ||
            messages[start].role != MessageRole.user ||
            messages[start].content != turn['input']) {
          throw const FormatException('轮次与消息不匹配');
        }
        if (turn['status'] == 'completed' &&
            !ops.any((op) =>
                op['turn_id'] == turn['id'] &&
                (op['revision'] as int) > before)) {
          throw const FormatException('缺少轮次提交日志');
        }
        previous = start;
      }
    }
    for (final row
        in await db.query('conversation_branches', where: 'is_active = 1')) {
      await activateMetadata(db, row['id'] as String);
    }
  }
}
