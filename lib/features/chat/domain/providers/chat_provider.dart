import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../../../constants/api_constants.dart';
import '../../../../constants/app_strings.dart';
import '../../data/agent.dart';
import '../../data/models/contact.dart';
import '../../data/models/message.dart';
import '../../data/repositories/chat_repository.dart';
import '../services/ai_service.dart';
import '../services/heartbeat_manager.dart';
import '../services/input_formatter.dart';
import '../structured/structured_input_prompt_composer.dart';
import '../structured/structured_output_regex_parser.dart';

/// 聊天状态管理器
///
/// 负责管理整个聊天应用的核心状态，包括：
/// - 联系人列表的增删改查
/// - 消息的发送与接收
/// - 与AI服务的交互
/// - 长期记忆的维护（事件图、知识库、物品等）
/// - 调试模式的切换
///
/// 使用 [ChangeNotifier] 模式，UI层通过监听此Provider来响应状态变化
class ChatProvider extends ChangeNotifier {
  /// 构造函数
  ///
  /// 支持依赖注入，便于单元测试
  /// - [repository] 聊天数据仓库
  /// - [formatter] 输入格式化服务
  /// - [heartbeat] 心跳管理器，用于检测连接状态
  /// - [agentStore] Agent数据持久化存储
  ChatProvider({
    ChatRepository? repository,
    InputFormatterService? formatter,
    HeartbeatManager? heartbeat,
    ChatAgentStore? agentStore,
  })  : _formatter = formatter ?? InputFormatterService(),
        _heartbeat = heartbeat ?? HeartbeatManager(),
        _repository = repository ?? ChatRepository(aiService: AiService()),
        _agentStore = agentStore ?? ChatAgentStore() {
    // 启动心跳检测，监听连接状态变化
    _heartbeat.start((status) {
      connectionStatus = status;
      notifyListeners();
    });
  }

  // ==================== 常量配置 ====================

  /// 事件总结阈值
  ///
  /// 当某个层级（短期/长期）中未总结的事件数量达到此值时，
  /// 触发LLM进行事件总结，将多个事件合并为一个更高层级的事件
  static const int _summaryThreshold = 10;

  /// 短期事件队列最大容量
  ///
  /// 超过此容量时，最旧的事件会被移除
  static const int _maxShortQueue = 120;

  /// 长期事件队列最大容量
  static const int _maxLongQueue = 60;

  /// 超长期事件队列最大容量
  static const int _maxUltraQueue = 30;

  /// 关键词提取正则表达式
  ///
  /// 匹配中文字符、英文字母、数字和下划线，最少2个字符
  /// 用于从用户输入中提取本地关键词
  static final RegExp _keywordTokenReg =
      RegExp(r'[\u4e00-\u9fffA-Za-z0-9_]{2,}');

  /// 调试模式输出Schema
  ///
  /// 定义LLM应返回的JSON结构，包含：
  /// - reply: AI的回复内容
  /// - memoryPatch: 记忆更新补丁，包含知识、事件、物品等
  static const String _debugOutputSchema = '''
{"reply":"...","memoryPatch":{"worldKnowledge":[],"selfKnowledge":[],"userKnowledge":[],"events":[{"time":"","location":"","characters":"","cause":"","process":"","result":"","attitude":""}],"belongings":[],"status":[],"mood":"","time":""}}
''';

  // ==================== 依赖服务 ====================

  /// 聊天数据仓库
  ///
  /// 负责与AI服务通信，发送请求并接收响应
  final ChatRepository _repository;

  /// 输入格式化服务
  ///
  /// 对用户输入进行预处理，如去除多余空白
  final InputFormatterService _formatter;

  /// 心跳管理器
  ///
  /// 定期检查与AI服务的连接状态
  final HeartbeatManager _heartbeat;

  /// Agent数据持久化存储
  ///
  /// 使用SharedPreferences存储联系人、消息历史、API设置等
  final ChatAgentStore _agentStore;

  // ==================== 状态数据 ====================

  /// 联系人列表
  final List<Contact> _contacts = <Contact>[];

  /// 按联系人ID索引的消息列表
  ///
  /// Key为联系人ID，Value为该联系人的消息历史
  final Map<String, List<Message>> _messagesByContact =
      <String, List<Message>>{};

  /// 临时关键词缓存
  ///
  /// 按联系人ID存储最近一次对话提取的关键词
  /// 用于关联事件搜索
  final Map<String, List<String>> _tempKeywordsByContact =
      <String, List<String>>{};

  /// 当前选中的联系人ID
  String? _selectedContactId;

  /// API密钥
  String _apiKey = '';

  /// 系统提示词
  ///
  /// 作为基础系统提示，会与联系人信息合并后发送给LLM
  String _systemPrompt = 'You are a helpful assistant.';

  // ==================== 公开状态（UI可直接访问） ====================

  /// 是否正在加载中
  bool isLoading = false;

  /// AI是否正在输入（用于显示打字指示器）
  bool isTyping = false;

  /// 是否已完成初始化
  bool isInitialized = false;

  /// 是否处于调试模式
  ///
  /// 调试模式下会显示完整的Prompt和关键词提取信息
  bool isDebugMode = false;

  /// 错误信息
  String? error;

  /// 当前连接状态
  ConnectionStatus connectionStatus = ConnectionStatus.connected;

  // ==================== Getters ====================

  /// 获取不可修改的联系人列表副本
  List<Contact> get contacts => List<Contact>.unmodifiable(_contacts);

  /// 获取当前选中的联系人ID
  String? get selectedContactId => _selectedContactId;

  /// 获取当前API密钥
  String get currentApiKey => _apiKey;

  /// 获取当前系统提示词
  String get currentSystemPrompt => _systemPrompt;

  /// 获取当前选中的联系人对象
  ///
  /// 如果未选中任何联系人，返回null
  Contact? get selectedContact {
    final id = _selectedContactId;
    if (id == null) return null;
    for (final c in _contacts) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 获取当前联系人的消息列表
  ///
  /// 如果未选中联系人，返回空列表
  List<Message> get messages {
    final id = _selectedContactId;
    if (id == null) return const <Message>[];
    return List<Message>.unmodifiable(_messagesByContact[id] ?? <Message>[]);
  }

  // ==================== 初始化与配置 ====================

  /// 初始化Provider
  ///
  /// 从持久化存储加载：
  /// 1. Agent设置（API密钥、系统提示词）
  /// 2. 联系人列表
  /// 3. 各联系人的消息历史
  ///
  /// 如果联系人列表为空，自动创建一个演示联系人
  Future<void> initialize() async {
    // 加载Agent设置
    final settings = await _agentStore.readAgentSettings();
    _apiKey = (settings['apiKey'] ?? '').toString();
    _systemPrompt = (settings['systemPrompt'] ?? _systemPrompt).toString();
    ApiConstants.runtimeApiKey = _apiKey;

    // 加载联系人和消息
    final localContacts = await _agentStore.readContacts();
    final localMessages = await _agentStore.readMessagesByContact();
    _contacts
      ..clear()
      ..addAll(
          localContacts.isEmpty ? <Contact>[demoContact()] : localContacts);

    // 初始化消息列表
    if (_contacts.isNotEmpty) {
      _selectedContactId = _contacts.first.id;
      for (final c in _contacts) {
        _messagesByContact[c.id] =
            List<Message>.from(localMessages[c.id] ?? const <Message>[]);
      }
    }
    isInitialized = true;
    notifyListeners();
  }

  /// 保存API密钥
  ///
  /// 同时更新内存状态和持久化存储
  Future<void> saveApiKey(String apiKey) async {
    _apiKey = apiKey.trim();
    ApiConstants.runtimeApiKey = _apiKey;
    final settings = await _agentStore.readAgentSettings();
    settings['apiKey'] = _apiKey;
    await _agentStore.saveAgentSettings(settings);
    notifyListeners();
  }

  /// 保存系统提示词
  Future<void> saveSystemPrompt(String prompt) async {
    _systemPrompt = prompt.trim();
    final settings = await _agentStore.readAgentSettings();
    settings['systemPrompt'] = _systemPrompt;
    await _agentStore.saveAgentSettings(settings);
    notifyListeners();
  }

  /// 切换调试模式
  ///
  /// 调试模式下会在聊天界面显示：
  /// - 关键词提取结果（本地提取和LLM提取）
  /// - 完整的系统Prompt
  void toggleDebugMode() {
    isDebugMode = !isDebugMode;
    notifyListeners();
  }

  // ==================== 联系人管理 ====================

  /// 选择联系人
  ///
  /// 切换当前活跃的聊天对象
  void selectContact(String contactId) {
    if (_selectedContactId == contactId) return;
    if (!_contacts.any((c) => c.id == contactId)) return;
    _selectedContactId = contactId;
    notifyListeners();
  }

  /// 添加新联系人
  ///
  /// 创建联系人并自动选中新联系人
  /// 返回是否添加成功（失败原因：ID已存在或参数无效）
  Future<bool> addContact({
    required String name,
    required String contactId,
    required String avatar,
    List<String> personality = const <String>[],
    List<String> appearance = const <String>[],
    List<String> backgroundStory = const <String>[],
  }) async {
    final normalizedName = name.trim();
    final normalizedId = contactId.trim();
    if (normalizedName.isEmpty || normalizedId.isEmpty) return false;
    if (_contacts.any((e) => e.id == normalizedId)) return false;

    final contact = Contact(
      id: normalizedId,
      name: normalizedName,
      avatar: avatar.trim(),
      personality: personality,
      appearance: appearance,
      backgroundStory: backgroundStory,
      createdAt: DateTime.now(),
    );
    _contacts.add(contact);
    _messagesByContact.putIfAbsent(contact.id, () => <Message>[]);
    _selectedContactId = contact.id;
    await _agentStore.saveContacts(_contacts);
    await _agentStore.saveMessagesByContact(_messagesByContact);
    notifyListeners();
    return true;
  }

  // ==================== 消息发送核心流程 ====================

  /// 发送消息
  ///
  /// 完整的消息处理流程：
  /// 1. 验证输入并创建用户消息
  /// 2. 提取关键词（本地 + LLM）
  /// 3. 构建系统Prompt（基础提示 + 联系人信息）
  /// 4. 发送请求到AI服务
  /// 5. 解析响应并提取回复内容
  /// 6. 更新联系人记忆（memoryPatch）
  /// 7. 触发事件总结（如达到阈值）
  Future<void> sendMessage(String rawInput) async {
    final selected = selectedContact;
    if (selected == null) {
      error = AppStrings.noContact;
      notifyListeners();
      return;
    }

    // 格式化输入
    final input = _formatter.normalize(rawInput);
    if (input.isEmpty || isLoading) return;

    // 创建用户消息
    final userMessage = Message(
      id: 'user-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.user,
      content: input,
      createdAt: DateTime.now(),
    );
    final currentList =
        _messagesByContact.putIfAbsent(selected.id, () => <Message>[]);
    currentList.add(userMessage);
    await _agentStore.saveMessagesByContact(_messagesByContact);

    // 设置加载状态
    isLoading = true;
    isTyping = true;
    error = null;
    notifyListeners();

    try {
      final currentContact = selectedContact;

      // 步骤1: 提取关键词
      final keywords = await _extractTurnKeywords(
        contactId: selected.id,
        contactName: selected.name,
        userInput: userMessage.content,
      );

      // 构建搜索查询（用户输入 + 关键词）
      final query = _buildKeywordSearchInput(
        userInput: userMessage.content,
        keywords: keywords.mergedKeywords.isEmpty
            ? (_tempKeywordsByContact[selected.id] ?? const <String>[])
            : keywords.mergedKeywords,
      );

      // 步骤2: 构建Prompt联系人（包含筛选后的事件和知识）
      final promptContact =
          _buildPromptContact(currentContact, userInput: query);

      // 步骤3: 合并系统Prompt
      final mergedSystemPrompt = _mergeSystemPromptWithContact(
        basePrompt: _systemPrompt,
        contact: promptContact,
      );

      // 步骤4: 添加当前事件层级提示
      final systemPrompt = _appendCurrentEventTierHint(
        basePrompt: mergedSystemPrompt,
        graph: currentContact?.eventGraph,
        userInput: query,
        promptEvents: promptContact?.events.items ?? const <EventMemory>[],
      );

      // 调试模式：显示关键词和完整Prompt
      if (isDebugMode) {
        final structured =
            StructuredInputPromptComposer.composeStructuredOutputPrompt(
          userInput: userMessage.content,
          systemPrompt: systemPrompt,
          outputSchema: _debugOutputSchema,
        );
        currentList.add(
          Message(
            id: 'debug-${DateTime.now().microsecondsSinceEpoch}',
            role: MessageRole.user,
            content: '【调试信息】关键词提取\n'
                '本地(JSON): ${jsonEncode({
                  "keywords": keywords.localKeywords
                })}\n'
                'LLM(JSON): ${jsonEncode({"keywords": keywords.llmKeywords})}\n'
                '合并(JSON): ${jsonEncode({
                  "keywords": keywords.mergedKeywords
                })}\n\n'
                '【调试信息】完整 Prompt\n$structured',
            createdAt: DateTime.now(),
          ),
        );
        await _agentStore.saveMessagesByContact(_messagesByContact);
      }

      // 步骤5: 发送AI请求
      final reply = await _repository.askAi(
        contactId: selected.id,
        contactName: selected.name,
        userMessage: userMessage,
        systemPrompt: systemPrompt,
      );

      // 步骤6: 提取回复内容（从JSON中提取reply字段）
      final replyContent =
          StructuredOutputRegexParser.extractReply(reply.content) ??
              reply.content;
      currentList.add(
        Message(
          id: reply.id,
          role: reply.role,
          content: replyContent,
          createdAt: reply.createdAt,
        ),
      );
      await _agentStore.saveMessagesByContact(_messagesByContact);

      // 步骤7: 更新联系人记忆
      await _updateContactFromMemoryPatch(selected, reply.content);
    } on AiServiceException catch (e) {
      error = e.userMessage;
      _heartbeat.markReconnecting();
    } catch (e, st) {
      debugPrint('sendMessage failed: $e');
      debugPrint('$st');
      final raw = e.toString().trim();
      error = raw.isEmpty ? AppStrings.networkError : '请求失败：$raw';
      _heartbeat.markReconnecting();
    } finally {
      isLoading = false;
      isTyping = false;
      notifyListeners();
    }
  }

  // ==================== 记忆更新与事件管理 ====================

  /// 从AI响应中提取记忆补丁并更新联系人
  ///
  /// 处理流程：
  /// 1. 解析memoryPatch JSON
  /// 2. 提取各类知识、事件、物品、状态
  /// 3. 将新事件加入短期队列
  /// 4. 更新物品关联和边关系
  /// 5. 触发事件总结（如达到阈值）
  /// 6. 持久化更新后的联系人
  Future<void> _updateContactFromMemoryPatch(
    Contact contact,
    String response,
  ) async {
    final patch = StructuredOutputRegexParser.extractMemoryPatch(response);
    if (patch == null) return;

    // 提取各类数据
    final incomingEvents = _extractEvents(patch['events']);
    final world = _mergeUnique(
      contact.worldKnowledge.items,
      _extractStrings(patch['worldKnowledge']),
    );
    final self = _mergeUnique(
      contact.selfKnowledge.items,
      _extractStrings(patch['selfKnowledge']),
    );
    final user = _mergeUnique(
      contact.userKnowledge.items,
      _extractStrings(patch['userKnowledge']),
    );
    final status =
        _mergeUnique(contact.status, _extractStrings(patch['status']));
    final patchBelongings = _extractBelongingPatchItems(patch['belongings']);

    // 更新事件图
    // 每轮清空belongingEventQueues和edges，只保留当前轮的关联
    var graph = contact.eventGraph.copyWith(
      turnCount: contact.eventGraph.turnCount + 1,
      belongingEventQueues: const <String, List<String>>{},
      edges: const <EventEdge>[],
    );

    // 将新事件加入短期队列
    String? currentEventNodeId;
    if (incomingEvents.isNotEmpty) {
      graph = _enqueueNode(
        graph,
        tier: EventTier.shortTerm,
        event: incomingEvents.first,
      );
      currentEventNodeId = graph.shortTermQueue.isNotEmpty
          ? graph.shortTermQueue.first.id
          : null;
    }

    // 更新物品关联和边关系
    graph = _applyBelongingQueuesAndEdges(
      graph: graph,
      eventNodeId: currentEventNodeId,
      patch: patchBelongings,
    );

    // 触发事件总结
    graph = await _promoteBySummary(contact, graph);

    // 更新联系人数据
    final idx = _contacts.indexWhere((e) => e.id == contact.id);
    if (idx < 0) return;
    _contacts[idx] = Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      personality: contact.personality,
      appearance: contact.appearance,
      backgroundStory: contact.backgroundStory,
      worldKnowledge: WorldKnowledgeBucket(world),
      selfKnowledge: SelfKnowledgeBucket(self),
      userKnowledge: UserKnowledgeBucket(user),
      events: EventLruBucket(
        _dedupeEvents(<EventMemory>[
          ...contact.events.items,
          ...incomingEvents,
          ..._flattenGraphEvents(graph),
        ]),
      ),
      eventGraph: graph,
      belongings: _applyBelongingsQueueUpdate(
        current: contact.belongings,
        patch: patchBelongings,
      ),
      status: status,
      mood: _extractString(patch['mood'], fallback: contact.mood),
      time: _extractString(patch['time'], fallback: contact.time),
      createdAt: contact.createdAt,
    );
    await _agentStore.saveContacts(_contacts);
  }

  /// 根据总结阈值触发事件升级
  ///
  /// 检查短期和长期队列，如果未总结事件数达到阈值，
  /// 则调用LLM进行事件总结，将事件升级到更高层级
  Future<EventGraphMemory> _promoteBySummary(
    Contact contact,
    EventGraphMemory graph,
  ) async {
    var current = graph;
    // 检查短期队列是否需要总结
    if (_unsummarizedCount(current, EventTier.shortTerm) >= _summaryThreshold) {
      current = await _mergeRecentEvents(
        contact,
        current,
        EventTier.shortTerm,
        EventTier.longTerm,
      );
    }
    // 检查长期队列是否需要总结
    if (_unsummarizedCount(current, EventTier.longTerm) >= _summaryThreshold) {
      current = await _mergeRecentEvents(
        contact,
        current,
        EventTier.longTerm,
        EventTier.ultraLongTerm,
      );
    }
    return current;
  }

  /// 合并近期事件
  ///
  /// 将指定层级的未总结事件合并为一个更高层级的事件
  /// 流程：
  /// 1. 收集未总结事件
  /// 2. 构建总结Prompt并请求LLM
  /// 3. 解析LLM的总结决策（n和event）
  /// 4. 创建总结事件并加入目标队列
  /// 5. 建立边关系（总结事件 -> 被总结事件）
  /// 6. 标记被总结事件
  Future<EventGraphMemory> _mergeRecentEvents(
    Contact contact,
    EventGraphMemory graph,
    EventTier source,
    EventTier target,
  ) async {
    // 收集未总结事件
    final unsummarized =
        _queueByTier(graph, source).where((e) => !e.summarized).toList();
    if (unsummarized.length < _summaryThreshold) return graph;
    final candidates = unsummarized.take(_summaryThreshold).toList();

    // 请求LLM进行总结决策
    _MergeDecision decision;
    try {
      final raw = await _repository.askUtility(
        contactId: contact.id,
        contactName: contact.name,
        prompt: _buildSummaryPrompt(source, target, candidates),
      );
      decision = _normalizeMergeDecision(_parseMergeDecision(raw), candidates);
    } catch (_) {
      // 失败时使用强制总结（合并所有候选事件）
      decision = _MergeDecision(
        n: candidates.length,
        event: _buildForcedSummaryEvent(candidates),
      );
    }

    // 执行总结
    final sources = candidates.take(decision.n).toList();
    if (sources.isEmpty) return graph;

    // 创建总结事件节点
    final out = _enqueueNode(graph, tier: target, event: decision.event);
    final targetQueue = _queueByTier(out, target);
    if (targetQueue.isEmpty) return graph;
    final summaryNode = targetQueue.first;

    // 建立边关系（总结事件指向被总结事件）
    final edgeMap = <String, EventEdge>{
      for (final e in out.edges) e.toUniqueKey(): e
    };
    for (final s in sources) {
      final edge = EventEdge(fromNodeId: summaryNode.id, toNodeId: s.id);
      edgeMap[edge.toUniqueKey()] = edge;
    }

    // 标记被总结事件并返回更新后的图
    return _markNodesSummarized(
      out.copyWith(edges: edgeMap.values.toList()),
      sourceTier: source,
      sourceNodeIds: sources.map((e) => e.id).toSet(),
    );
  }

  /// 构建事件总结Prompt
  ///
  /// 要求LLM：
  /// - 将短期事件归并为长期事件，或长期归并为超长期
  /// - 优先输出可归并的最近N条（2 <= n <= 10）
  /// - 若过于离散，输出n=10强制总结
  String _buildSummaryPrompt(
    EventTier source,
    EventTier target,
    List<EventNode> candidates,
  ) {
    final b = StringBuffer();
    b.writeln('你是事件归并器。');
    b.writeln('任务：将以下${_tierLabel(source)}事件归并为 1 条${_tierLabel(target)}事件。');
    b.writeln(
      '只输出 JSON。格式：{"n":10,"event":{"time":"","location":"","characters":"","cause":"","process":"","result":"","attitude":""}}',
    );
    b.writeln('- 优先输出可归并的最近 N 条，n>=2 且 <=10。');
    b.writeln('- 若过于离散无法选择更小整体，输出 n=10 强制总结。');
    for (int i = 0; i < candidates.length; i++) {
      b.writeln('${i + 1}. ${candidates[i].event.toPromptLine()}');
    }
    return b.toString();
  }

  /// 解析LLM的总结决策
  _MergeDecision? _parseMergeDecision(String raw) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);
    if (payload == null) return null;
    final n = int.tryParse((payload['n'] ?? '').toString()) ?? 0;
    final eventRaw = payload['event'];
    if (eventRaw is! Map<String, dynamic>) {
      return _MergeDecision(n: n, event: const EventMemory());
    }
    return _MergeDecision(n: n, event: EventMemory.fromJson(eventRaw));
  }

  /// 规范化总结决策
  ///
  /// 确保n在有效范围内，如果LLM返回的事件为空则使用强制总结
  _MergeDecision _normalizeMergeDecision(
    _MergeDecision? decision,
    List<EventNode> candidates,
  ) {
    final fallback = _buildForcedSummaryEvent(candidates);
    if (decision == null) {
      return _MergeDecision(n: candidates.length, event: fallback);
    }
    final n = (decision.n >= 2 && decision.n <= candidates.length)
        ? decision.n
        : candidates.length;
    final event = decision.event.isEmpty ? fallback : decision.event;
    return _MergeDecision(n: n, event: event);
  }

  /// 构建强制总结事件
  ///
  /// 当LLM总结失败时使用，自动合并候选事件的关键信息
  EventMemory _buildForcedSummaryEvent(List<EventNode> candidates) {
    if (candidates.isEmpty) return const EventMemory();
    String pick(Iterable<String> values) {
      for (final value in values) {
        final v = value.trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final newest = candidates.first.event;
    final oldest = candidates.last.event;
    final lines = candidates
        .map((e) => e.event.toPromptLine().trim())
        .where((e) => e.isNotEmpty)
        .take(3);
    return EventMemory(
      time: <String>{
        if (newest.time.isNotEmpty) newest.time,
        if (oldest.time.isNotEmpty) oldest.time,
      }.join(' ~ '),
      location: pick(candidates.map((e) => e.event.location)),
      characters: pick(candidates.map((e) => e.event.characters)),
      cause: pick(candidates.map((e) => e.event.cause)),
      process: lines.isEmpty
          ? pick(candidates.map((e) => e.event.process))
          : lines.join('；'),
      result: pick(candidates.map((e) => e.event.result)),
      attitude: pick(candidates.map((e) => e.event.attitude)),
    );
  }

  // ==================== Prompt构建辅助方法 ====================

  /// 构建用于Prompt的联系人对象
  ///
  /// 从完整联系人中提取用于LLM输入的子集：
  /// - 事件：短期10条 + 长期5条 + 超长期2条 + 关联5条
  /// - 知识：各类型前5条
  /// - 物品：前5个
  Contact? _buildPromptContact(Contact? contact, {required String userInput}) {
    if (contact == null) return null;
    final memoryEvents = <EventMemory>[
      ...contact.eventGraph.shortTermQueue
          .where((e) => !e.summarized)
          .take(10)
          .map((e) => e.event),
      ...contact.eventGraph.longTermQueue
          .where((e) => !e.summarized)
          .take(5)
          .map((e) => e.event),
      ...contact.eventGraph.ultraLongTermQueue.take(2).map((e) => e.event),
    ];
    final related =
        contact.eventGraph.relatedEventsForPrompt(userInput).take(5);
    return Contact(
      id: contact.id,
      name: contact.name,
      avatar: contact.avatar,
      category: contact.category,
      personality: contact.personality,
      appearance: contact.appearance,
      backgroundStory: contact.backgroundStory,
      worldKnowledge:
          WorldKnowledgeBucket(_firstN(contact.worldKnowledge.items, 5)),
      selfKnowledge:
          SelfKnowledgeBucket(_firstN(contact.selfKnowledge.items, 5)),
      userKnowledge:
          UserKnowledgeBucket(_firstN(contact.userKnowledge.items, 5)),
      events: EventLruBucket(
          _dedupeEvents(<EventMemory>[...memoryEvents, ...related])),
      eventGraph: contact.eventGraph,
      belongings: _firstN(contact.belongings, 5),
      status: contact.status,
      mood: contact.mood,
      time: contact.time,
      createdAt: contact.createdAt,
    );
  }

  /// 提取本轮对话关键词
  ///
  /// 结合本地提取和LLM提取：
  /// - 本地：使用正则表达式提取关键词
  /// - LLM：请求专门的LLM进行关键词抽取
  /// 合并结果并缓存，用于后续关联事件搜索
  Future<_KeywordExtraction> _extractTurnKeywords({
    required String contactId,
    required String contactName,
    required String userInput,
  }) async {
    // 本地关键词提取
    final local = _extractLocalKeywords(userInput).toList();

    // LLM关键词提取
    List<String> llm = const <String>[];
    try {
      final raw = await _repository.askUtility(
        contactId: contactId,
        contactName: contactName,
        prompt: _buildKeywordPrompt(userInput),
      );
      llm = _parseKeywordsFromRaw(raw);
    } catch (_) {
      llm = const <String>[];
    }

    // 如果LLM提取失败，使用本地提取结果
    if (llm.isEmpty) llm = List<String>.from(local);

    // 合并并去重
    final merged = _mergeUnique(local, llm);
    _tempKeywordsByContact[contactId] = merged;
    return _KeywordExtraction(
      localKeywords: local,
      llmKeywords: llm,
      mergedKeywords: merged,
    );
  }

  /// 构建关键词提取Prompt
  String _buildKeywordPrompt(String userInput) {
    return '你是关键词抽取器。只输出 JSON：{"keywords":["关键词1","关键词2"]}。最多 8 个关键词。用户输入：${userInput.trim()}';
  }

  /// 构建关键词搜索输入
  ///
  /// 将用户输入和关键词合并，用于事件搜索
  String _buildKeywordSearchInput({
    required String userInput,
    required List<String> keywords,
  }) {
    final input = userInput.trim();
    if (keywords.isEmpty) return input;
    return '$input\n${keywords.join(' ')}';
  }

  /// 从LLM响应中解析关键词列表
  List<String> _parseKeywordsFromRaw(String raw) {
    final payload = StructuredOutputRegexParser.parsePrimaryPayload(raw);
    final list = payload?['keywords'];
    if (list is! List) return const <String>[];
    final out = <String>[];
    for (final item in list) {
      final value = item?.toString().trim() ?? '';
      if (value.isEmpty || out.contains(value)) continue;
      out.add(value);
    }
    return out;
  }

  /// 从输入中提取本地关键词
  ///
  /// 使用正则表达式匹配中文字符、英文单词等
  Set<String> _extractLocalKeywords(String input) {
    final out = <String>{};
    for (final m in _keywordTokenReg.allMatches(input.toLowerCase())) {
      final token = m.group(0)?.trim();
      if (token == null || token.isEmpty) continue;
      out.add(token);
      if (out.length >= 8) break;
    }
    return out;
  }

  // ==================== 事件图操作辅助方法 ====================

  /// 应用物品队列和边关系更新
  ///
  /// 当物品被标记为新增或提及时：
  /// 1. 将当前事件ID加入物品的关联队列
  /// 2. 在物品节点和事件节点之间建立边
  EventGraphMemory _applyBelongingQueuesAndEdges({
    required EventGraphMemory graph,
    required String? eventNodeId,
    required List<_BelongingPatchItem> patch,
  }) {
    if (patch.isEmpty || eventNodeId == null || eventNodeId.isEmpty) {
      return graph;
    }
    final queues = <String, List<String>>{
      for (final e in graph.belongingEventQueues.entries)
        e.key: List<String>.from(e.value),
    };
    var out = graph;
    for (final item in patch) {
      final queue = queues.putIfAbsent(item.name, () => <String>[]);
      queue.add(eventNodeId);
      // 限制队列长度
      if (queue.length > 100) queue.removeRange(0, queue.length - 100);
      // 建立边关系
      out = _appendEdge(
        out,
        fromNodeId: _belongingNodeId(item.name),
        toNodeId: eventNodeId,
      );
    }
    return out.copyWith(belongingEventQueues: queues);
  }

  /// 将事件节点加入指定层级队列
  ///
  /// 创建新节点并：
  /// 1. 添加到队列头部（最新的在前）
  /// 2. 限制队列长度
  /// 3. 与前一个节点建立边关系（时间顺序）
  EventGraphMemory _enqueueNode(
    EventGraphMemory graph, {
    required EventTier tier,
    required EventMemory event,
  }) {
    if (event.isEmpty) return graph;
    // 创建新节点
    final node = EventNode(
      id: '${tier.storageKey}-${DateTime.now().microsecondsSinceEpoch}-${event.toPromptLine().hashCode.abs()}',
      tier: tier,
      event: event,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      summarized: false,
    );
    switch (tier) {
      case EventTier.shortTerm:
        final prev =
            graph.shortTermQueue.isEmpty ? null : graph.shortTermQueue.first.id;
        var out = graph.copyWith(
          shortTermQueue: <EventNode>[node, ...graph.shortTermQueue]
              .take(_maxShortQueue)
              .toList(),
        );
        // 建立时间顺序边
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
        return out;
      case EventTier.longTerm:
        final prev =
            graph.longTermQueue.isEmpty ? null : graph.longTermQueue.first.id;
        var out = graph.copyWith(
          longTermQueue: <EventNode>[node, ...graph.longTermQueue]
              .take(_maxLongQueue)
              .toList(),
        );
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
        return out;
      case EventTier.ultraLongTerm:
        final prev = graph.ultraLongTermQueue.isEmpty
            ? null
            : graph.ultraLongTermQueue.first.id;
        var out = graph.copyWith(
          ultraLongTermQueue: <EventNode>[node, ...graph.ultraLongTermQueue]
              .take(_maxUltraQueue)
              .toList(),
        );
        if (prev != null) {
          out = _appendEdge(out, fromNodeId: node.id, toNodeId: prev);
        }
        return out;
    }
  }

  /// 添加边关系到事件图
  ///
  /// 使用唯一键去重，避免重复边
  EventGraphMemory _appendEdge(
    EventGraphMemory graph, {
    required String fromNodeId,
    required String toNodeId,
  }) {
    if (fromNodeId.trim().isEmpty || toNodeId.trim().isEmpty) return graph;
    final edge = EventEdge(fromNodeId: fromNodeId, toNodeId: toNodeId);
    final edgeMap = <String, EventEdge>{
      for (final e in graph.edges) e.toUniqueKey(): e,
      edge.toUniqueKey(): edge,
    };
    return graph.copyWith(edges: edgeMap.values.toList());
  }

  /// 标记节点为已总结
  ///
  /// 在事件总结后，将被合并的原始节点标记为summarized=true
  EventGraphMemory _markNodesSummarized(
    EventGraphMemory graph, {
    required EventTier sourceTier,
    required Set<String> sourceNodeIds,
  }) {
    if (sourceNodeIds.isEmpty) return graph;
    List<EventNode> mark(List<EventNode> queue) => queue
        .map(
          (n) => sourceNodeIds.contains(n.id)
              ? EventNode(
                  id: n.id,
                  tier: n.tier,
                  event: n.event,
                  createdAtMs: n.createdAtMs,
                  summarized: true,
                )
              : n,
        )
        .toList();
    switch (sourceTier) {
      case EventTier.shortTerm:
        return graph.copyWith(shortTermQueue: mark(graph.shortTermQueue));
      case EventTier.longTerm:
        return graph.copyWith(longTermQueue: mark(graph.longTermQueue));
      case EventTier.ultraLongTerm:
        return graph;
    }
  }

  /// 获取指定层级的未总结事件数量
  int _unsummarizedCount(EventGraphMemory graph, EventTier tier) =>
      _queueByTier(graph, tier).where((n) => !n.summarized).length;

  /// 获取指定层级的事件队列
  List<EventNode> _queueByTier(EventGraphMemory graph, EventTier tier) {
    switch (tier) {
      case EventTier.shortTerm:
        return graph.shortTermQueue;
      case EventTier.longTerm:
        return graph.longTermQueue;
      case EventTier.ultraLongTerm:
        return graph.ultraLongTermQueue;
    }
  }

  /// 扁平化事件图，获取所有事件
  List<EventMemory> _flattenGraphEvents(EventGraphMemory graph) =>
      <EventMemory>[
        ...graph.shortTermQueue.map((e) => e.event),
        ...graph.longTermQueue.map((e) => e.event),
        ...graph.ultraLongTermQueue.map((e) => e.event),
      ];

  // ==================== 数据提取辅助方法 ====================

  /// 从JSON中提取事件列表
  List<EventMemory> _extractEvents(dynamic value) {
    if (value is! List) return const <EventMemory>[];
    final out = <EventMemory>[];
    for (final item in value) {
      if (item is! Map) continue;
      final map = item.map((k, v) => MapEntry(k.toString(), v));
      final e = EventMemory.fromJson(map);
      if (!e.isEmpty) out.add(e);
    }
    return out;
  }

  /// 从JSON中提取字符串列表
  List<String> _extractStrings(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 从JSON中提取字符串
  String _extractString(dynamic value, {required String fallback}) {
    final s = (value ?? '').toString().trim();
    return s.isEmpty ? fallback : s;
  }

  /// 合并两个列表并去重
  List<String> _mergeUnique(List<String> a, List<String> b) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in a.followedBy(b)) {
      final v = item.trim();
      if (v.isEmpty || !seen.add(v)) continue;
      out.add(v);
    }
    return out;
  }

  /// 去除重复事件
  List<EventMemory> _dedupeEvents(List<EventMemory> input) {
    final out = <EventMemory>[];
    final seen = <String>{};
    for (final e in input) {
      final key = e.toPromptLine().trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(e);
    }
    return out;
  }

  /// 从JSON中提取物品补丁项
  ///
  /// 解析格式：(新增)物品名 或 (提及)物品名
  List<_BelongingPatchItem> _extractBelongingPatchItems(dynamic value) {
    if (value is! List) return const <_BelongingPatchItem>[];
    final out = <_BelongingPatchItem>[];
    final reg = RegExp(r'^[\(\（]\s*(新增|提及)\s*[\)\）]\s*(.+)$');
    for (final raw in value) {
      final text = raw?.toString().trim() ?? '';
      final m = reg.firstMatch(text);
      if (m == null) continue;
      final tag = m.group(1)?.trim() ?? '';
      final name = m.group(2)?.trim() ?? '';
      if (name.isEmpty) continue;
      out.add(
        _BelongingPatchItem(
          type: tag == '新增'
              ? _BelongingPatchType.added
              : _BelongingPatchType.mentioned,
          name: name,
        ),
      );
    }
    return out;
  }

  /// 应用物品队列更新
  ///
  /// 将新增或提及的物品移到队列末尾（表示最近使用）
  List<String> _applyBelongingsQueueUpdate({
    required List<String> current,
    required List<_BelongingPatchItem> patch,
  }) {
    if (patch.isEmpty) return List<String>.from(current);
    final out = <String>[...current];
    for (final item in patch) {
      final idx = out.indexWhere((e) => e == item.name);
      if (idx >= 0) out.removeAt(idx);
      out.add(item.name);
    }
    return out;
  }

  /// 获取列表的前N个元素
  List<String> _firstN(List<String> items, int n) =>
      items.length <= n ? List<String>.from(items) : items.sublist(0, n);

  /// 获取事件层级的标签
  String _tierLabel(EventTier tier) => switch (tier) {
        EventTier.shortTerm => '短期',
        EventTier.longTerm => '长期',
        EventTier.ultraLongTerm => '超长期',
      };

  /// 合并系统提示词和联系人信息
  String _mergeSystemPromptWithContact({
    required String basePrompt,
    Contact? contact,
  }) {
    final base = basePrompt.trim();
    if (contact == null) return base;
    return StructuredInputPromptComposer.composeSystemPromptWithContactObject(
      basePrompt: base,
      contact: contact,
    );
  }

  /// 添加当前事件层级提示
  ///
  /// 帮助LLM理解当前对话关联的事件层级（短期/长期/超长期/联想）
  String _appendCurrentEventTierHint({
    required String basePrompt,
    required EventGraphMemory? graph,
    required String userInput,
    required List<EventMemory> promptEvents,
  }) {
    final base = basePrompt.trim();
    if (graph == null) return base;
    final tier = _resolveCurrentEventTier(
      graph: graph,
      userInput: userInput,
      promptEvents: promptEvents,
    );
    if (tier == null) return base;
    final suffix = '## 当前事件分类\n- 当前 event 分类: $tier';
    return base.isEmpty ? suffix : '$base\n\n$suffix';
  }

  /// 解析当前事件层级
  ///
  /// 根据用户输入和Prompt中的事件，判断当前对话最关联的事件层级
  String? _resolveCurrentEventTier({
    required EventGraphMemory graph,
    required String userInput,
    required List<EventMemory> promptEvents,
  }) {
    // 构建事件到层级的映射
    final keyToTier = <String, String>{};
    for (final node in graph.shortTermQueue) {
      keyToTier.putIfAbsent(node.event.toPromptLine().trim(), () => '短期');
    }
    for (final node in graph.longTermQueue) {
      keyToTier.putIfAbsent(node.event.toPromptLine().trim(), () => '长期');
    }
    for (final node in graph.ultraLongTermQueue) {
      keyToTier.putIfAbsent(node.event.toPromptLine().trim(), () => '超长期');
    }

    // 检查是否是联想事件
    final related = graph
        .relatedEventsForPrompt(userInput)
        .map((e) => e.toPromptLine().trim())
        .toSet();
    for (final e in promptEvents) {
      final key = e.toPromptLine().trim();
      if (key.isEmpty) continue;
      if (related.contains(key)) return '联想';
      final tier = keyToTier[key];
      if (tier != null) return tier;
    }

    // 默认返回最优先的非空层级
    if (graph.shortTermQueue.isNotEmpty) return '短期';
    if (graph.longTermQueue.isNotEmpty) return '长期';
    if (graph.ultraLongTermQueue.isNotEmpty) return '超长期';
    return null;
  }

  /// 生成物品节点的ID
  String _belongingNodeId(String name) =>
      'belonging:${name.trim().toLowerCase()}';

  @override
  void dispose() {
    _heartbeat.stop();
    super.dispose();
  }
}

// ==================== 内部数据类 ====================

/// 关键词提取结果
class _KeywordExtraction {
  const _KeywordExtraction({
    required this.localKeywords,
    required this.llmKeywords,
    required this.mergedKeywords,
  });

  /// 本地正则提取的关键词
  final List<String> localKeywords;

  /// LLM提取的关键词
  final List<String> llmKeywords;

  /// 合并后的关键词（去重）
  final List<String> mergedKeywords;
}

/// 事件总结决策
class _MergeDecision {
  const _MergeDecision({
    required this.n,
    required this.event,
  });

  /// 要合并的事件数量
  final int n;

  /// 总结后的事件
  final EventMemory event;
}

/// 物品补丁类型
enum _BelongingPatchType { added, mentioned }

/// 物品补丁项
class _BelongingPatchItem {
  const _BelongingPatchItem({
    required this.type,
    required this.name,
  });

  /// 补丁类型（新增或提及）
  final _BelongingPatchType type;

  /// 物品名称
  final String name;
}
