import 'dart:async';
import 'dart:convert';

import 'package:flutter_chat_demo/features/worldbook/domain/entities/world_book.dart';

import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/data/repositories/chat_repository.dart';
import 'package:flutter_chat_demo/features/chat/application/chat_view_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/infrastructure/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MemoryPersistence persistence;
  late _FakeAiService aiService;
  late ChatProvider provider;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    persistence = _MemoryPersistence(
      ChatSnapshot(contacts: <Contact>[_contact()]),
    );
    aiService = _FakeAiService();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(apiKey: 'test-key'),
      ),
    );
  });

  tearDown(() => provider.dispose());

  test('JSON 创建失败暴露具体字段，兼容字段创建成功并清除旧错误', () async {
    expect(await provider.addContactFromJson('{"name":"新角色","personality":{}}'),
        isFalse);
    expect(provider.error, contains(r'$.personality'));
    expect(provider.contacts, hasLength(1));
    expect(
        await provider.addContactFromJsonWithFallback(
            '{"性格":"温柔","current_states":{"好感度":10}}',
            fallbackName: '新角色'),
        isTrue);
    expect(provider.error, isNull);
    expect(provider.selectedContact!.personality, ['温柔']);
    expect(provider.selectedContact!.currentStates, {'好感度': '10'});
    expect(persistence.snapshot.contacts, hasLength(2));
  });

  test('成功发送在最终事务中同时提交消息和正文前事件', () async {
    aiService.mainResponse = '''
{"protocolVersion":"roleplay-memory-v2","memoryPatch":{"eventBrief":{"description":"林夏接过车票","keywords":["林夏","车票"]}},"reply":"她把车票仔细收进了口袋。"}
''';

    await provider.sendMessage('把车票给她');

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.status, MessageStatus.sent);
    expect(provider.messages.last.content, '她把车票仔细收进了口袋。');
    expect(provider.selectedContact?.eventGraph.turnCount, 1);
    expect(
      provider
          .selectedContact?.eventGraph.shortTermQueue.single.event.description,
      '林夏接过车票',
    );
    final committed = persistence.snapshot;
    expect(committed.messagesByContact['role-1'], hasLength(2));
    expect(committed.contacts.single.eventGraph.turnCount, 1);
  });

  test('模型失败保留 failed 用户消息但不提交任何记忆变化', () async {
    aiService.failure = const AiServiceException('模拟网络失败');

    await provider.sendMessage('这次会失败');

    expect(provider.messages.single.status, MessageStatus.failed);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.messagesByContact['role-1']?.single.status,
        MessageStatus.failed);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('撤回同时恢复消息历史和事件图', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"发生了一件事"}},"reply":"事情发生了。"}
''';
    await provider.sendMessage('推动这一轮');
    expect(provider.canRecall, isTrue);

    expect(await provider.recallLastTurn(), isTrue);

    expect(provider.messages, isEmpty);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.messagesByContact['role-1'], isEmpty);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('记忆修改记录跨重启保留且可以无损撤销', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏收到一张蓝色车票","keywords":["林夏","车票"]}},"reply":"她收下了。"}
''';
    await provider.sendMessage('给她车票');
    final node = provider.memoryNodes.single;

    expect(
      await provider.reviseMemory(
        node.id,
        const EventMemory(
          description: '林夏收到一张红色车票',
          keywords: <String>['林夏', '红色车票'],
        ),
      ),
      isTrue,
    );
    expect(provider.canUndoMemoryRevision, isTrue);
    expect(
      persistence.metadata.entries
          .singleWhere((entry) => entry.key.startsWith('memory_revision_v1_'))
          .value,
      isNotEmpty,
    );

    provider.dispose();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();

    expect(provider.canUndoMemoryRevision, isTrue);
    expect(await provider.undoLastMemoryRevision(), isTrue);
    expect(
      provider.memoryNodes.single.event.description,
      '林夏收到一张蓝色车票',
    );
    expect(
      persistence.metadata.entries
          .singleWhere((entry) => entry.key.startsWith('memory_revision_v1_'))
          .value,
      isEmpty,
    );
  });

  test('完整备份恢复角色消息和事件，但不改变 API 设置', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏记住了雨夜"}},"reply":"雨声还在窗外。"}
''';
    await provider.sendMessage('记住这个雨夜');
    final backup = await provider.exportBackupJson();
    final originalKey = provider.currentApiKey;

    await provider.addContact(name: '临时角色', avatar: '');
    expect(provider.contacts, hasLength(2));
    expect(await provider.restoreBackupJson(backup), isTrue);

    expect(provider.contacts, hasLength(1));
    expect(provider.messages, hasLength(2));
    expect(provider.memoryNodes.single.event.description, '林夏记住了雨夜');
    expect(provider.currentApiKey, originalKey);
  });

  test('停止非流式生成立即结束等待且不提交记忆', () async {
    aiService.pendingMain = Completer<String>();

    final sending = provider.sendMessage('等待中的请求');
    await Future<void>.delayed(Duration.zero);
    expect(provider.canCancelGeneration, isTrue);
    provider.cancelGeneration();
    await sending;

    expect(provider.isLoading, isFalse);
    expect(provider.isTyping, isFalse);
    expect(provider.error, isNull);
    expect(provider.messages.single.status, MessageStatus.cancelled);
    expect(provider.state.generationStatus, ChatGenerationStatus.cancelled);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
    expect(persistence.snapshot.contacts.single.eventGraph.turnCount, 0);
  });

  test('流式回复逐块更新可见消息并在完整 JSON 后原子提交记忆', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(
          apiKey: 'test-key',
          parameters: LlmParameters(stream: true),
        ),
      ),
    );
    final stream = StreamController<String>();
    aiService.pendingStream = stream;

    final sending = provider.sendMessage('开始流式回复');
    await Future<void>.delayed(Duration.zero);
    stream.add(
      '{"protocolVersion":"roleplay-memory-v5","reply":"你',
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(provider.messages.last.content, '你');
    expect(provider.messages.last.status, MessageStatus.sending);
    expect(provider.state.generationStatus, ChatGenerationStatus.streaming);

    stream.add('好","memoryPatch":{"eventBrief":{"description":"流式事件"}}}');
    await stream.close();
    await sending;

    expect(provider.messages, hasLength(2));
    expect(provider.messages.last.content, '你好');
    expect(provider.messages.last.status, MessageStatus.sent);
    expect(provider.state.generationStatus, ChatGenerationStatus.completed);
    expect(provider.memoryNodes.single.event.description, '流式事件');
    expect(persistence.snapshot.messagesByContact['role-1'], hasLength(2));
  });

  test('取消流式回复保留部分文本并标记 cancelled', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(
          apiKey: 'test-key',
          parameters: LlmParameters(stream: true),
        ),
      ),
    );
    final stream = StreamController<String>();
    aiService.pendingStream = stream;
    final sending = provider.sendMessage('取消流式回复');
    await Future<void>.delayed(Duration.zero);
    stream.add('{"memoryPatch":{},"reply":"部分');
    await Future<void>.delayed(const Duration(milliseconds: 40));
    provider.cancelGeneration();
    await sending;
    await stream.close();

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.status, MessageStatus.cancelled);
    expect(provider.messages.last.content, '部分');
    expect(provider.messages.last.status, MessageStatus.cancelled);
    expect(provider.state.generationStatus, ChatGenerationStatus.cancelled);
    expect(provider.selectedContact?.eventGraph.turnCount, 0);
  });

  test('修改上一轮后先撤回旧记忆再重新生成', () async {
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏收下蓝色车票"}},"reply":"她收下了蓝色车票。"}
''';
    await provider.sendMessage('给她蓝色车票');
    aiService.mainResponse = '''
{"memoryPatch":{"eventBrief":{"description":"林夏拒绝红色车票"}},"reply":"她轻轻摇头。"}
''';

    expect(
      await provider.regenerateLastTurn(editedInput: '改成给她红色车票'),
      isTrue,
    );

    expect(provider.messages, hasLength(2));
    expect(provider.messages.first.content, '改成给她红色车票');
    expect(provider.messages.last.content, '她轻轻摇头。');
    expect(provider.memoryNodes, hasLength(1));
    expect(provider.memoryNodes.single.event.description, '林夏拒绝红色车票');
    expect(provider.selectedContact?.eventGraph.turnCount, 1);
  });

  test('已完成剧情不能仅改正文、删除消息或切换候选', () async {
    aiService.mainResponse = '{"memoryPatch":{},"reply":"原回复"}';
    await provider.sendMessage('原问题');
    final assistantId = provider.messages.last.id;
    final userId = provider.messages.first.id;
    expect(await provider.editMessage(assistantId, '修订后的回复'), isFalse);
    expect(await provider.deleteMessage(userId), isFalse);
    expect(await provider.generateReplyCandidate(assistantId), isFalse);
    expect(await provider.applyReplyCandidate(assistantId, '候选'), isFalse);
    expect(provider.messages.last.content, '原回复');
    expect(provider.messages, hasLength(2));
    expect(aiService.requestedModels, hasLength(1));
  });

  test('失败消息仍可编辑删除', () async {
    aiService.failure = const AiServiceException('失败');
    await provider.sendMessage('失败输入');
    final id = provider.messages.single.id;
    expect(await provider.editMessage(id, '新输入'), isTrue);
    expect(await provider.deleteMessage(id), isTrue);
    expect(persistence.snapshot.messagesByContact['role-1'], isEmpty);
  });

  test('简短合法回复只调用一次，非法正文不写入状态也不自动重试', () async {
    aiService.mainResponse = '{"memoryPatch":{},"reply":"嗯。"}';
    await provider.sendMessage('好吗');
    expect(provider.messages.last.content, '嗯。');
    expect(aiService.requestedModels, hasLength(1));
    aiService.mainResponse = '{"memoryPatch":{"currentStates":{}}';
    await provider.sendMessage('继续');
    expect(provider.messages.last.status, MessageStatus.failed);
    expect(provider.selectedContact!.eventGraph.turnCount, 1);
    expect(aiService.requestedModels, hasLength(2));
  });

  test('状态原子提交、跨重启和备份保留、撤回同时恢复衣着与地点', () async {
    await provider.updateWorldBook(const WorldBook(locations: [
      WorldLocation(id: 'station', name: '旧车站'),
    ]));
    aiService.mainResponse = _stateReply(0, [
      _change('scene/location', null, '车站'),
      _change('actor/林夏/outfit', null, '白衬衫、黑裙'),
    ]);
    await provider.sendMessage('开始');
    expect(provider.error, isNull);
    expect(provider.selectedContact!.continuity.revision, 1);
    expect(provider.selectedContact!.worldBook.locations.single.name, '旧车站');
    final backup = await provider.exportBackupJson();
    expect(jsonDecode(backup)['contacts'][0]['continuity']['revision'], 1);

    provider.dispose();
    provider = ChatProvider(
        persistence: persistence,
        repository: ChatRepository(aiService: aiService));
    await provider.initialize();
    expect(provider.selectedContact!.continuity.values['actor/林夏/outfit'],
        '白衬衫、黑裙');
    aiService.mainResponse =
        _stateReply(1, [_change('scene/location', '车站', '屋内')]);
    await provider.sendMessage('进屋');
    expect(provider.error, isNull);
    expect(provider.selectedContact!.continuity.values['scene/location'], '屋内');
    expect(provider.selectedContact!.continuity.values['actor/林夏/outfit'],
        '白衬衫、黑裙');
    expect(await provider.recallLastTurn(), isTrue);
    expect(provider.selectedContact!.continuity.values['scene/location'], '车站');
    expect(provider.selectedContact!.continuity.revision, 1);
    expect(provider.selectedContact!.worldBook.locations.single.name, '旧车站');
    expect(await provider.restoreBackupJson(backup), isTrue);
    expect(provider.selectedContact!.continuity.revision, 1);
  });

  test('旧值不符整轮拒绝，不写入正文或任何部分记忆', () async {
    aiService.mainResponse =
        _stateReply(0, [_change('scene/location', null, '车站')]);
    await provider.sendMessage('开始');
    aiService.mainResponse = _stateReply(1, [
      _change('actor/林夏/outfit', null, '蓝裙'),
      _change('scene/location', '公园', '屋内'),
    ]);
    await provider.sendMessage('继续');
    expect(provider.messages, hasLength(3));
    expect(provider.messages.last.status, MessageStatus.failed);
    expect(provider.selectedContact!.continuity.values,
        {'scene/location': '车站', 'actor/林夏/outfit': ''});
    expect(persistence.snapshot.contacts.single.continuity.revision, 1);
    expect(provider.selectedContact!.eventGraph.turnCount, 1);
    expect(aiService.requestedModels, hasLength(2));
  });

  test('同一时刻连续发送只启动一轮', () async {
    aiService.pendingMain = Completer<String>();
    final first = provider.sendMessage('第一条');
    final duplicate = provider.sendMessage('第二条');
    await Future<void>.delayed(Duration.zero);
    aiService.pendingMain!.complete('{"memoryPatch":{},"reply":"收到"}');
    await Future.wait([first, duplicate]);
    expect(aiService.requestedModels, hasLength(1));
    expect(provider.messages, hasLength(2));
  });

  test('一次摘要只标记实际发送给模型的源事件', () async {
    provider.dispose();
    persistence.snapshot = ChatSnapshot(contacts: [
      _contact().copyWith(
        eventGraph: EventGraphMemory(shortTermQueue: [
          for (var i = 0; i < 12; i++)
            EventNode(
                id: 'old-$i',
                tier: EventTier.shortTerm,
                event: EventMemory(description: '旧事件$i'),
                createdAtMs: 12 - i),
        ]),
      )
    ]);
    provider = ChatProvider(
        persistence: persistence,
        repository: ChatRepository(aiService: aiService));
    await provider.initialize();
    aiService.mainResponse =
        '{"memoryPatch":{"summary":{"description":"指定十条事件的总结"},"eventBrief":{"description":"新事件"}},"reply":"继续。"}';
    await provider.sendMessage('继续');
    expect(provider.error, isNull);
    final nodes = provider.selectedContact!.eventGraph.shortTermQueue;
    expect(nodes.where((n) => n.summarized), hasLength(10));
    expect(nodes.singleWhere((n) => n.id == 'old-10').summarized, isFalse);
    expect(nodes.singleWhere((n) => n.id == 'old-11').summarized, isFalse);
  });

  test('模型自行总结不会丢弃原有事件或加入未请求的摘要', () async {
    aiService.mainResponse =
        '{"memoryPatch":{"summary":{"description":"擅自概括"},"eventBrief":{"description":"本轮事件"}},"reply":"继续。"}';
    await provider.sendMessage('继续');
    expect(provider.selectedContact!.eventGraph.longTermQueue, isEmpty);
    expect(
        provider.selectedContact!.eventGraph.shortTermQueue.single.summarized,
        isFalse);
  });

  test('实际发送的system逐字复用，状态在动态输入且上一轮正文保留原生角色', () async {
    aiService.mainResponse =
        _stateReply(0, [_change('actor/林夏/outfit', null, '白衬衫')]);
    await provider.sendMessage('开始');
    aiService.mainResponse =
        '{"memoryPatch":{"worldKnowledge":["发现旧站台"]},"reply":"我记住了。"}';
    await provider.sendMessage('继续');
    await provider.sendMessage('再继续');
    expect(aiService.systemPrompts.toSet(), hasLength(1));
    expect(
        RegExp('"protocolVersion"').allMatches(aiService.systemPrompts.first),
        hasLength(1));
    expect(aiService.userPrompts.last, contains('发现旧站台'));
    expect(aiService.userPrompts.last, contains('白衬衫'));
    expect(aiService.userPrompts.last, isNot(contains('我记住了。')));
    expect(aiService.histories.last.last.role, 'assistant');
    expect(aiService.histories.last.last.content, '我记住了。');
  });

  test('流式JSON中断不能把已显示草稿标为成功或写入状态', () async {
    await provider.saveProviderSettings(const ProviderSettings(
        llm: LlmProfile(
            apiKey: 'test-key', parameters: LlmParameters(stream: true))));
    aiService.mainResponse = '{"memoryPatch":{},"reply":"未完成';
    await provider.sendMessage('继续');
    expect(provider.messages.last.content, '未完成');
    expect(
        provider.messages
            .every((message) => message.status == MessageStatus.failed),
        isTrue);
    expect(provider.selectedContact!.eventGraph.turnCount, 0);
  });

  test('事务写入失败，正文和状态不留下成功的半轮', () async {
    persistence.failCompletedSave = true;
    aiService.mainResponse =
        _stateReply(0, [_change('scene/location', null, '车站')]);
    await provider.sendMessage('开始');
    expect(provider.error, isNotNull);
    expect(provider.selectedContact!.continuity.revision, 0);
    expect(
        provider.messages
            .every((message) => message.status == MessageStatus.failed),
        isTrue);
    expect(persistence.snapshot.contacts.single.continuity.revision, 0);
  });

  test('记忆锁跨重启持久化并阻止作废和删除', () async {
    aiService.mainResponse =
        '{"memoryPatch":{"eventBrief":{"description":"不可删除的记忆"}},"reply":"记住了"}';
    await provider.sendMessage('锁定它');
    final nodeId = provider.memoryNodes.single.id;

    expect(await provider.setMemoryLocked(nodeId, true), isTrue);
    expect(provider.isMemoryLocked(nodeId), isTrue);
    expect(await provider.invalidateMemory(nodeId), isFalse);
    expect(await provider.deleteMemory(nodeId), isFalse);

    provider.dispose();
    provider = ChatProvider(
      persistence: persistence,
      repository: ChatRepository(aiService: aiService),
    );
    await provider.initialize();
    expect(provider.isMemoryLocked(nodeId), isTrue);
  });

  test('主 LLM Profile 失败后自动使用备用 Profile', () async {
    await provider.saveProviderSettings(
      const ProviderSettings(
        llm: LlmProfile(apiKey: 'primary', model: 'bad-model'),
        fallbackLlmProfiles: <LlmProfile>[
          LlmProfile(apiKey: 'fallback', model: 'good-model'),
        ],
      ),
    );
    aiService.failingModels.add('bad-model');
    aiService.mainResponse = '{"memoryPatch":{},"reply":"备用成功"}';

    await provider.sendMessage('测试 fallback');

    expect(provider.error, isNull);
    expect(provider.messages.last.content, '备用成功');
    expect(aiService.requestedModels, containsAll(['bad-model', 'good-model']));
  });
}

class _FakeAiService extends AiService {
  String mainResponse = '';
  AiServiceException? failure;
  Completer<String>? pendingMain;
  StreamController<String>? pendingStream;
  final Set<String> failingModels = <String>{};
  final List<String> requestedModels = <String>[];
  final List<String> systemPrompts = [];
  final List<String> userPrompts = [];
  final List<List<AiChatMessage>> histories = [];

  @override
  Future<String> ask(
    String prompt, {
    required String contactId,
    required String contactName,
    String? systemPrompt,
    List<AiChatMessage> history = const <AiChatMessage>[],
    bool requireJsonObject = false,
    LlmProfile? profile,
    RecallRequestBudget? requestBudget,
  }) async {
    if (prompt.contains('提取本轮对话中的关键词')) {
      return '{"keywords":["车票"],"theme":[]}';
    }
    requestedModels.add(profile?.model ?? '');
    systemPrompts.add(systemPrompt ?? '');
    userPrompts.add(prompt);
    histories.add(List<AiChatMessage>.from(history));
    if (failingModels.contains(profile?.model)) {
      throw const AiServiceException('模拟 Profile 失败');
    }
    final error = failure;
    if (error != null) throw error;
    final pending = pendingMain;
    if (pending != null) return pending.future;
    return mainResponse;
  }

  @override
  Stream<String> askStream(
    String prompt, {
    required String contactId,
    required String contactName,
    String? systemPrompt,
    List<AiChatMessage> history = const <AiChatMessage>[],
    bool requireJsonObject = false,
    LlmProfile? profile,
  }) {
    histories.add(List<AiChatMessage>.from(history));
    final stream = pendingStream;
    if (stream != null) return stream.stream;
    return Stream<String>.value(mainResponse);
  }
}

class _MemoryPersistence implements ChatPersistence {
  _MemoryPersistence(this.snapshot);

  ChatSnapshot snapshot;
  bool failCompletedSave = false;
  final Map<String, String> metadata = <String, String>{};

  @override
  Future<void> initialize() async {}

  @override
  Future<ChatSnapshot> readSnapshot() async => snapshot;

  @override
  Future<void> replaceSnapshot(ChatSnapshot value) async {
    snapshot = _copy(value);
  }

  @override
  Future<void> saveConversation({
    required Contact contact,
    required List<Message> messages,
    Map<String, String> metadataUpdates = const <String, String>{},
  }) async {
    if (failCompletedSave &&
        messages.any((m) =>
            m.role == MessageRole.assistant &&
            m.status == MessageStatus.sent)) {
      failCompletedSave = false;
      throw StateError('模拟事务失败');
    }
    final contacts = <Contact>[
      ...snapshot.contacts.where((item) => item.id != contact.id),
      contact.deepCopy(),
    ];
    snapshot = ChatSnapshot(
      contacts: contacts,
      messagesByContact: <String, List<Message>>{
        ...snapshot.messagesByContact,
        contact.id: List<Message>.from(messages),
      },
    );
    metadata.addAll(metadataUpdates);
  }

  @override
  Future<void> deleteConversation(String contactId) async {
    snapshot = ChatSnapshot(
      contacts:
          snapshot.contacts.where((item) => item.id != contactId).toList(),
      messagesByContact: <String, List<Message>>{
        for (final entry in snapshot.messagesByContact.entries)
          if (entry.key != contactId) entry.key: entry.value,
      },
    );
  }

  @override
  Future<String?> readMetadata(String key) async => metadata[key];

  @override
  Future<void> writeMetadata(String key, String value) async {
    metadata[key] = value;
  }

  @override
  Future<void> close() async {}

  ChatSnapshot _copy(ChatSnapshot value) => ChatSnapshot(
        contacts: value.contacts.map((contact) => contact.deepCopy()).toList(),
        messagesByContact: <String, List<Message>>{
          for (final entry in value.messagesByContact.entries)
            entry.key: List<Message>.from(entry.value),
        },
      );
}

Contact _contact() => Contact(
      id: 'role-1',
      name: '林夏',
      avatar: '',
      fixedInput: '你是林夏。',
      currentStates: {'scene/location': '', 'actor/林夏/outfit': ''},
      createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    );

Map<String, dynamic> _change(String key, String? from, String to) =>
    {'key': key, 'from': from ?? '', 'to': to, 'evidence': to};
String _stateReply(int revision, List<Map<String, dynamic>> changes) =>
    jsonEncode({
      'protocolVersion': 'roleplay-memory-v3',
      'memoryPatch': {
        'eventBrief': {'description': '她点了点头'},
        'stateTransition': {'baseRevision': revision, 'changes': changes},
      },
      'reply': '此刻：${changes.map((change) => change['to']).join('；')}。',
    });
