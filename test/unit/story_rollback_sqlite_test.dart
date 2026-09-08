import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_chat_demo/core/data/models/app_settings.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/datasources/sqlite_chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/story_turn_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/event_recall_coordinator.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late SqliteChatPersistence store;
  late ChatProvider provider;
  late _Model model;
  Contact initial() => Contact(
      id: 'story',
      name: '调查故事',
      avatar: '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
      continuity: ContinuityState(revision: 0, definitions: const [
        StateDefinition(
            id: 'clue',
            name: '已确认的线索',
            description: '只记证据',
            initialValue: '未知',
            updateRule: '证据必须在正文出现')
      ], values: {
        'clue': '未知'
      }));
  Future<void> openProvider() async {
    provider = ChatProvider(
        persistence: store, repository: ChatRepository(aiService: model));
    await provider.initialize();
    await provider.saveProviderSettings(
        const ProviderSettings(llm: LlmProfile(apiKey: 'local-mock')));
  }

  Future<void> send(String marker) async {
    final state = provider.selectedContact!.continuity;
    model.response = jsonEncode({
      'protocolVersion': 'roleplay-memory-v4',
      'memoryPatch': {
        'stateTransition': {
          'baseRevision': state.revision,
          'changes': state.definitions.isEmpty
              ? []
              : [
                  {
                    'key': state.definitions.first.id,
                    'from': state.values[state.definitions.first.id] ??
                        state.definitions.first.initialValue,
                    'to': marker
                  }
                ]
        },
        'worldKnowledge': ['世界$marker'],
        'selfKnowledge': ['角色$marker'],
        'userKnowledge': ['用户$marker'],
        'belongings': ['(新增)物品$marker'],
        'eventBrief': {
          'description': '事件$marker',
          'keywords': [marker],
          'theme': [marker]
        },
        'summary': {
          'description': '摘要$marker',
          'keywords': [marker]
        },
        'relatedEventIds': provider.memoryNodes.map((n) => n.id).toList(),
      },
      'reply': '回应$marker'
    });
    await provider.sendMessage(marker);
    expect(provider.error, isNull);
    expect(
        provider.totalMessageCount,
        (await store.readSnapshot())
            .messagesByContact[provider.selectedContactId]!
            .length);
  }

  Future<void> restart() async {
    provider.dispose();
    await store.close();
    store = _CommitGateStore(path);
    await openProvider();
  }

  List<Map<String, dynamic>> jsonMessages(List<Message> messages) =>
      messages.map((m) => m.toJson()).toList();
  test('资料与系统属性事务保存并在重启后保留，旧编辑器拒绝覆盖', () async {
    await send('原始剧情');
    final original = provider.selectedContact!.deepCopy();
    final branch = provider.activeConversationBranch?.id;
    final data = original.toJson()
      ..['name'] = '修改后的角色'
      ..['avatar'] = 'data:image/png;base64,dGVzdA=='
      ..['personality'] = ['谨慎', '幽默']
      ..['worldKnowledge'] = ['修改后的知识']
      ..['belongings'] = <String>[]
      ..['mood'] = '放松';
    final draft = Contact.fromJson(data);
    final beforeMessages = jsonMessages(provider.messages);
    final beforeGraph = jsonEncode(original.eventGraph.toJson());
    expect(
        await provider.updateContactProfile(
            original: original, draft: draft, expectedBranchId: branch),
        isTrue);
    expect(provider.selectedContact!.name, '修改后的角色');
    expect(jsonMessages(provider.messages), beforeMessages);
    expect(
        jsonEncode(provider.selectedContact!.eventGraph.toJson()), beforeGraph);
    expect(provider.selectedContact!.continuity.revision,
        original.continuity.revision + 1);
    expect(
        await provider.updateContactProfile(
            original: original, draft: draft, expectedBranchId: branch),
        isFalse);
    await restart();
    expect(provider.selectedContact!.name, '修改后的角色');
    expect(provider.selectedContact!.avatar, draft.avatar);
    expect(provider.selectedContact!.worldKnowledge.items, ['修改后的知识']);
    expect(provider.selectedContact!.belongings, isEmpty);
    final edited = provider.selectedContact!.deepCopy();
    await send('资料修改之后');
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.toJson(), edited.toJson());
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('roleplay-story-test-');
    path = '${directory.path}/story.db';
    store = SqliteChatPersistence(
        databaseFactory: databaseFactoryFfi, databasePath: path);
    await store.initialize();
    await store.replaceSnapshot(ChatSnapshot(contacts: [initial()]));
    model = _Model();
    await openProvider();
  });
  tearDown(() async {
    provider.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('历史删除精确恢复完整剧情，后续实际Prompt和备份没有污染标记', () async {
    await send('保留剧情');
    final before = await store.readSnapshot();
    await send('POISON_A');
    final targetMessage =
        provider.messages.last.id; // assistant belongs to its user turn
    await send('POISON_B');
    final removedIds = provider.memoryNodes
        .where((n) => n.event.description.contains('POISON'))
        .map((n) => n.id)
        .toList();
    final target = await provider.previewDeleteMessage(targetMessage);
    expect(target!.turnCount, 2);
    expect(await provider.deleteStoryFrom(target), isTrue);
    final after = await store.readSnapshot();
    expect(after.contacts.single.toJson(), before.contacts.single.toJson());
    expect(jsonMessages(after.messagesByContact['story']!),
        jsonMessages(before.messagesByContact['story']!));
    expect(provider.conversationCheckpoints, hasLength(1));
    final recall = await EventRecallCoordinator().recall(
      graph: provider.selectedContact!.eventGraph,
      currentInput: '保留剧情',
      recentMessages: [],
      hotNodeIds: {},
      mainProfile: const LlmProfile(apiKey: 'local-mock'),
      memoryRecallProfile: null,
      invokeModel: (
              {required prompt,
              required profile,
              required requestBudget}) async =>
          '{"keywords":[],"theme":[]}',
    );
    expect(
        recall.nodes.every((n) =>
            !removedIds.contains(n.id) &&
            !n.event.description.contains('POISON')),
        isTrue);
    final backup = await provider.exportBackupJson();
    expect(backup, isNot(contains('POISON')));
    expect(await provider.restoreBackupJson(backup), isTrue);
    await send('新的发展');
    expect(model.prompts.last, isNot(contains('POISON')));
    for (final id in removedIds) {
      expect(model.prompts.last, isNot(contains(id)));
    }
    expect(
        provider.memoryNodes.every((n) => !removedIds.contains(n.id)), isTrue);
  });

  test('重启后连续撤回，配置、手工值、锁与修订撤销记录一起恢复', () async {
    final baseline = initial().toJson();
    await send('第一轮');
    final first = provider.selectedContact!.toJson();
    final node = provider.memoryNodes.single;
    expect(
        await provider.reviseMemory(
            node.id, const EventMemory(description: '手工修正')),
        isTrue);
    expect(await provider.setMemoryLocked(node.id, true), isTrue);
    final beforeConfig = provider.selectedContact!.continuity;
    expect(
        await provider.updateStoryState(ContinuityState(
            revision: beforeConfig.revision,
            definitions: const [
              StateDefinition(id: 'clue', name: '改名线索', updateRule: '自定规则')
            ],
            values: {
              'clue': '手工值'
            })),
        isTrue);
    final modified = provider.selectedContact!.toJson();
    final metadata = await store.readMetadata('memory_revision_v1_story');
    await send('第二轮');
    await restart();
    expect(provider.canRecall, isTrue);
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.toJson(), modified);
    expect(provider.isMemoryLocked(node.id), isTrue);
    expect(await store.readMetadata('memory_revision_v1_story'), metadata);
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.toJson(), baseline);
    expect(provider.messages, isEmpty);
    expect(provider.canUndoMemoryRevision, isFalse);
    expect(provider.isMemoryLocked(node.id), isFalse);
    expect(await store.readMetadata('memory_revision_v1_story'), isNull);
    expect(first, isNot(equals(modified)));
  });

  test('跨摘要层和淘汰队列回滚恢复标记、来源边和原顺序', () async {
    await provider.saveAppSettings(const AppSettings(
        summaryThreshold: 2,
        ultraSummaryThreshold: 1,
        maxShortQueue: 3,
        maxLongQueue: 2,
        maxUltraQueue: 1));
    await send('一');
    await send('二');
    final baseline = provider.selectedContact!.toJson();
    await send('三');
    final target = provider.messages.last.id;
    await send('四');
    await send('五');
    await send('六');
    expect(provider.selectedContact!.eventGraph.ultraLongTermQueue, isNotEmpty);
    expect(provider.selectedContact!.eventGraph.edges, isNotEmpty);
    expect(await provider.deleteMessage(target), isTrue);
    expect(provider.selectedContact!.toJson(), baseline);
  });

  test('发送后加载更早消息再撤回，万条历史逐条一致', () async {
    provider.dispose();
    await store.close();
    await store.initialize();
    final history = List.generate(
        10000,
        (i) => Message(
            id: 'old-$i',
            role: i.isEven ? MessageRole.user : MessageRole.assistant,
            content: '旧正文$i',
            createdAt: DateTime.fromMillisecondsSinceEpoch(i)));
    await store.replaceSnapshot(ChatSnapshot(
        contacts: [initial()], messagesByContact: {'story': history}));
    await openProvider();
    expect(provider.messages.length, lessThan(history.length));
    await send('新轮次');
    expect(await provider.loadOlderMessages(), isTrue);
    expect(await provider.recallLastTurn(), isTrue);
    expect(
        jsonMessages((await store.readSnapshot()).messagesByContact['story']!),
        jsonMessages(history));
  });

  test('重发和修改后重发先截断，原输入只执行一次模型请求', () async {
    await send('保留');
    await send('旧输入');
    final user = provider.messages[2];
    await send('被截断的后续');
    model.response =
        '{"memoryPatch":{"eventBrief":{"description":"新回复"}},"reply":"新回复"}';
    final calls = model.prompts.length;
    await provider.resendMessage('story', user.id);
    expect(model.prompts.length, calls + 1);
    expect(provider.messages, hasLength(4));
    expect(provider.messages[2].content, '旧输入');
    expect(model.prompts.last, isNot(contains('被截断的后续')));
    expect(
        await provider.editMessage(provider.messages[2].id, '修改后的输入'), isTrue);
    expect(provider.messages[2].content, '修改后的输入');
    expect(provider.messages, hasLength(4));
  });

  test('SQLite检查点写入失败使整轮事务回滚，重试清理旧草稿', () async {
    await send('成功');
    final baseline = provider.selectedContact!.toJson();
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(
        "CREATE TRIGGER fail_checkpoint BEFORE INSERT ON conversation_checkpoints BEGIN SELECT RAISE(ABORT, 'injected failure'); END");
    model.response =
        '{"memoryPatch":{"worldKnowledge":["POISON"],"eventBrief":{"description":"POISON"}},"reply":"POISON"}';
    await provider.sendMessage('失败');
    expect(provider.error, isNotNull);
    expect(provider.selectedContact!.toJson(), baseline);
    expect((await store.readSnapshot()).contacts.single.toJson(), baseline);
    expect(provider.conversationCheckpoints, hasLength(1));
    expect(await db.query('story_operations'), hasLength(1));
    final failed = provider.messages.firstWhere((m) => m.content == '失败');
    await db.execute('DROP TRIGGER fail_checkpoint');
    model.response = '{"memoryPatch":{},"reply":"重试成功"}';
    await provider.resendMessage('story', failed.id);
    expect(provider.error, isNull);
    expect(provider.messages, hasLength(4));
    expect(
        provider.messages.every((m) => m.status == MessageStatus.sent), isTrue);
    expect(jsonEncode(provider.selectedContact!.toJson()),
        isNot(contains('POISON')));
  });

  test('生成期间删除、重复发送受互斥保护，流式取消不提交记忆', () async {
    await send('保留');
    final baseline = provider.selectedContact!.toJson();
    await provider.saveProviderSettings(const ProviderSettings(
        llm: LlmProfile(
            apiKey: 'local-mock', parameters: LlmParameters(stream: true))));
    model.stream = StreamController<String>();
    final sending = provider.sendMessage('取消输入');
    await model.streamStarted.future;
    model.stream!
        .add('{"memoryPatch":{"worldKnowledge":["POISON"]},"reply":"流式草稿');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(await provider.deleteMessage(provider.messages.first.id), isFalse);
    await provider.sendMessage('重复点击');
    provider.cancelGeneration();
    await sending;
    await model.stream!.close();
    expect(provider.selectedContact!.toJson(), baseline);
    expect(provider.messages.where((m) => m.content == '重复点击'), isEmpty);
    expect(provider.messages.last.status, MessageStatus.cancelled);
    expect(await provider.deleteMessage(provider.messages.last.id), isTrue);
    expect(provider.messages, hasLength(2));
    expect(provider.selectedContact!.toJson(), baseline);
  });

  test('已创建分支保留独立记忆，被删除检查点解除来源，备份保留可撤回性', () async {
    await send('共同历史');
    await send('分叉来源');
    final source = provider.conversationCheckpoints.first;
    final main = provider.activeConversationBranch!.id;
    expect(await provider.createBranchFromCheckpoint(source.id, name: '独立分支'),
        isTrue);
    await send('分支专属');
    final forkState = provider.selectedContact!.toJson();
    final forkId = provider.activeConversationBranch!.id;
    expect(await provider.switchConversationBranch(main), isTrue);
    expect(await provider.deleteMessage(provider.messages[2].id), isTrue);
    expect(provider.conversationCheckpoints.any((c) => c.id == source.id),
        isFalse);
    expect(
        provider.conversationBranches
            .singleWhere((b) => b.id == forkId)
            .forkCheckpointId,
        isNull);
    final backup = await provider.exportBackupJson();
    expect(await provider.restoreBackupJson(backup), isTrue);
    expect(await provider.switchConversationBranch(forkId), isTrue);
    expect(provider.selectedContact!.toJson(), forkState);
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.continuity.values['clue'], '分叉来源');
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.continuity.values['clue'], '共同历史');
    expect(await provider.switchConversationBranch(main), isTrue);
    await send('主分支继续');
    expect(model.prompts.last, isNot(contains('分支专属')));
    expect(model.prompts.last, isNot(contains('分叉来源')));
  });

  test('过期删除预览和状态编辑被拒绝，损坏日志备份整体恢复失败', () async {
    await send('原始');
    final target =
        (await provider.previewDeleteMessage(provider.messages.first.id))!;
    final stale = provider.selectedContact!.continuity;
    await send('新增');
    final baseline = await store.readSnapshot();
    expect(await provider.deleteStoryFrom(target), isFalse);
    expect(await provider.updateStoryState(stale), isFalse);
    final backup =
        jsonDecode(await provider.exportBackupJson()) as Map<String, dynamic>;
    final heads = backup['timeline']['journal']['heads'] as List;
    heads.first['metadata'] = jsonEncode({'apiKey': 'unexpected'});
    expect(await provider.restoreBackupJson(jsonEncode(backup)), isFalse);
    expect((await store.readSnapshot()).contacts.single.toJson(),
        baseline.contacts.single.toJson());
    expect(jsonMessages(provider.messages),
        jsonMessages(baseline.messagesByContact['story']!));
    expect(provider.currentApiKey, 'local-mock');
  });

  test('中断进程遗留的pending轮次恢复成取消，可连续撤回此前成功轮', () async {
    await send('成功轮');
    final before = provider.selectedContact!.toJson();
    await store.beginStoryTurn(
        contactId: 'story',
        userMessage: Message(
            id: 'pending-user',
            turnId: 'pending-turn',
            role: MessageRole.user,
            content: '进程中断',
            status: MessageStatus.sending,
            createdAt: DateTime.now()));
    await restart();
    expect(provider.messages.last.status, MessageStatus.cancelled);
    expect(provider.selectedContact!.toJson(), before);
    final results = await Future.wait(
        [provider.recallLastTurn(), provider.recallLastTurn()]);
    expect(results.where((r) => r), hasLength(1));
    expect(provider.messages, hasLength(2));
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.messages, isEmpty);
  });

  test('旧历史只接受完全匹配的检查点前缀，拒绝只删UI；清除不匹配旧检查点', () async {
    final contact = provider.selectedContact!;
    final old = List.generate(
        4,
        (i) => Message(
            id: 'legacy-$i',
            role: i.isEven ? MessageRole.user : MessageRole.assistant,
            content: '旧正文$i',
            createdAt: DateTime.fromMillisecondsSinceEpoch(i)));
    await store.saveConversation(
        contact: contact, messages: old.take(2).toList());
    final cp = await store.createCheckpoint(
        contact: contact, sourceMessageId: 'legacy-1');
    await store.saveConversation(
        contact:
            contact.copyWith(worldKnowledge: WorldKnowledgeBucket(['POISON'])),
        messages: old);
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.update('conversation_checkpoints', {'story_revision': null},
        where: 'id = ?', whereArgs: [cp.id]);
    await db.delete('story_heads');
    await db.delete('story_operations');
    final raw = (await db.query('conversation_checkpoints')).single;
    await db.insert('conversation_checkpoints', {
      ...raw,
      'id': 'bad-checkpoint',
      'messages_payload':
          jsonEncode(jsonMessages([old[0].copyWith(content: 'POISON'), old[1]]))
    });
    expect(
        await store.previewStoryTruncation(
            contactId: 'story', messageId: 'legacy-0'),
        isNull);
    final target = await store.previewStoryTruncation(
        contactId: 'story', messageId: 'legacy-3');
    expect(target!.legacyCheckpointId, cp.id);
    await store.truncateStory(target);
    expect((await store.readSnapshot()).contacts.single.toJson(),
        contact.toJson());
    expect((await store.listCheckpoints('story')).map((c) => c.id), [cp.id]);
    // A snapshot at the same position with different content is not a recovery basis.
    await store.saveConversation(
        contact: contact,
        messages: [old[0].copyWith(content: '改过的历史'), ...old.skip(1)]);
    expect(
        await store.previewStoryTruncation(
            contactId: 'story', messageId: 'legacy-3'),
        isNull);
    expect(
        (await store.readSnapshot()).messagesByContact['story'], hasLength(4));
  });

  test('手工配置保存失败不发布内存值，跨分支旧编辑器不能覆盖状态', () async {
    await send('初始轮');
    final before = provider.selectedContact!.continuity;
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(
        "CREATE TRIGGER fail_contact BEFORE UPDATE ON contacts BEGIN SELECT RAISE(ABORT, 'injected configuration failure'); END");
    expect(
        await provider.updateStoryState(ContinuityState(
            revision: before.revision,
            definitions: before.definitions,
            values: {'clue': '不能保存'})),
        isFalse);
    expect(provider.selectedContact!.continuity.toJson(), before.toJson());
    expect((await store.readSnapshot()).contacts.single.continuity.toJson(),
        before.toJson());
    await db.execute('DROP TRIGGER fail_contact');
    final main = provider.activeConversationBranch!.id;
    expect(
        await provider.createBranchFromCheckpoint(
            provider.conversationCheckpoints.single.id,
            name: '不同分支'),
        isTrue);
    expect(await provider.updateStoryState(before, expectedBranchId: main),
        isFalse);
  });

  test('v3数据库升级保留旧完整检查点，仅在匹配位置允许撤回', () async {
    await send('旧第一轮');
    final first = provider.selectedContact!.toJson();
    await send('旧第二轮');
    final archive = await store.readTimelineArchive();
    provider.dispose();
    await store.close();
    final db = await databaseFactoryFfi.openDatabase(path);
    for (final snapshot in archive.checkpoints) {
      await db.update(
          'conversation_checkpoints',
          {
            'contact_payload': jsonEncode(snapshot.contact.toJson()),
            'messages_payload': jsonEncode(jsonMessages(snapshot.messages))
          },
          where: 'id = ?',
          whereArgs: [snapshot.checkpoint.id]);
    }
    await db.execute('DROP TABLE story_operations');
    await db.execute('DROP TABLE story_turns');
    await db.execute('DROP TABLE story_heads');
    await db.execute(
        'ALTER TABLE conversation_checkpoints DROP COLUMN story_revision');
    await db.setVersion(3);
    await db.close();
    store = SqliteChatPersistence(
        databaseFactory: databaseFactoryFfi, databasePath: path);
    await openProvider();
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.toJson(), first);
    expect(provider.messages, hasLength(2));
    expect(provider.canRecall, isFalse);
  });

  test('调试消息同属轮次，删除时一并截断且不额外调用模型', () async {
    provider.toggleDebugMode();
    await send('调试轮');
    expect(provider.messages, hasLength(4));
    expect(provider.messages.map((m) => m.turnId).toSet(), hasLength(1));
    final calls = model.prompts.length;
    expect(await provider.deleteMessage(provider.messages[1].id), isTrue);
    expect(provider.messages, isEmpty);
    expect(provider.selectedContact!.eventGraph.turnCount, 0);
    expect(model.prompts.length, calls);
  });

  test('旧正文的新检查点恢复当时元数据，无元数据的老检查点保守拒绝', () async {
    final contact = initial();
    final old = List.generate(
        4,
        (i) => Message(
            id: 'meta-old-$i',
            role: i.isEven ? MessageRole.user : MessageRole.assistant,
            content: '消息$i',
            createdAt: DateTime.fromMillisecondsSinceEpoch(i)));
    await store.saveConversation(
        contact: contact,
        messages: old.take(2).toList(),
        metadataUpdates: {'memory_locks_v1_story': '["prior-lock"]'});
    final checkpoint = await store.createCheckpoint(
        contact: contact, sourceMessageId: old[1].id);
    await store.saveConversation(
        contact: contact,
        messages: old,
        metadataUpdates: {'memory_locks_v1_story': '["later-lock"]'});
    final target = (await store.previewStoryTruncation(
        contactId: 'story', messageId: old.last.id))!;
    await store.truncateStory(target);
    expect(await store.readMetadata('memory_locks_v1_story'), '["prior-lock"]');
    await store.saveConversation(contact: contact, messages: old);
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.update('conversation_checkpoints', {'story_revision': null},
        where: 'id = ?', whereArgs: [checkpoint.id]);
    expect(
        await store.previewStoryTruncation(
            contactId: 'story', messageId: old.last.id),
        isNull);
    expect(
        (await store.readSnapshot()).messagesByContact['story'], hasLength(4));
  });

  test('提交完成前UI不发布成功正文和状态', () async {
    // Use a real SQLite store with only its commit entrance paused.
    provider.dispose();
    await store.close();
    final gate = _CommitGateStore(path);
    store = gate;
    await openProvider();
    gate.hold = true;
    final before = provider.selectedContact!.toJson();
    final sending = send('待提交');
    await gate.entered.future;
    expect(provider.messages, hasLength(1));
    expect(provider.messages.single.status, MessageStatus.sending);
    expect(provider.selectedContact!.toJson(), before);
    gate.release.complete();
    await sending;
    expect(provider.messages, hasLength(2));
    expect(
        provider.messages.every((m) => m.status == MessageStatus.sent), isTrue);
  });

  test('不同故事的定义、值、稳定前缀和备份不混用', () async {
    await send('案件内容');
    final firstSystem = model.systems.last;
    final story = Contact(
        id: 'other',
        name: '航海故事',
        avatar: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2),
        continuity: ContinuityState(revision: 0, definitions: const [
          StateDefinition(id: 'wind', name: '风向记录', initialValue: '北风')
        ], values: {
          'wind': '北风'
        }));
    await store.saveConversation(contact: story, messages: []);
    await restart();
    await provider.selectContact('other');
    await send('东风');
    expect(model.systems.last, contains('风向记录'));
    expect(model.systems.last, isNot(contains('已确认的线索')));
    expect(model.prompts.last, isNot(contains('案件内容')));
    expect(firstSystem, contains('已确认的线索'));
    final backup = await provider.exportBackupJson();
    expect(await provider.restoreBackupJson(backup), isTrue);
    await provider.selectContact('other');
    expect(provider.selectedContact!.continuity.values, {'wind': '东风'});
    await provider.selectContact('story');
    expect(provider.selectedContact!.continuity.values, {'clue': '案件内容'});
  });
}

class _CommitGateStore extends SqliteChatPersistence {
  _CommitGateStore(String path)
      : super(databaseFactory: databaseFactoryFfi, databasePath: path);
  bool hold = false;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<void> commitStoryTurn(
      {required StoryTurnHandle turn,
      required Contact contact,
      required List<Message> messages}) async {
    if (hold) {
      entered.complete();
      await release.future;
    }
    await super
        .commitStoryTurn(turn: turn, contact: contact, messages: messages);
  }
}

class _Model extends AiService {
  String response = '{"memoryPatch":{},"reply":"模拟回复"}';
  final prompts = <String>[];
  final systems = <String>[];
  StreamController<String>? stream;
  final streamStarted = Completer<void>();
  @override
  Future<String> ask(String prompt,
      {String? contactId,
      String? contactName,
      String? systemPrompt,
      List<AiChatMessage> history = const <AiChatMessage>[],
      bool requireJsonObject = false,
      LlmProfile? profile,
      RecallRequestBudget? requestBudget}) async {
    if (systemPrompt == null || systemPrompt.isEmpty) {
      return '{"keywords":[],"theme":[]}';
    }
    prompts.add(prompt);
    systems.add(systemPrompt);
    return response;
  }

  @override
  Stream<String> askStream(String prompt,
      {required String contactId,
      required String contactName,
      String? systemPrompt,
      List<AiChatMessage> history = const <AiChatMessage>[],
      bool requireJsonObject = false,
      LlmProfile? profile}) {
    prompts.add(prompt);
    systems.add(systemPrompt ?? '');
    streamStarted.complete();
    return stream!.stream;
  }
}
