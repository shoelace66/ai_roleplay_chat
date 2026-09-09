import 'dart:async';
import 'dart:convert';

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
