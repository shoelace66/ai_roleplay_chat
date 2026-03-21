import '../../features/chat/data/models/contact.dart';
import '../data/models/app_settings.dart';

class StructuredInputPromptComposer {
  final AppSettings settings;

  StructuredInputPromptComposer({this.settings = const AppSettings()});

  int get _maxPromptListItems => settings.maxPromptListItems;
  int get _maxPromptLineLength => settings.maxPromptLineLength;
  int get _maxEdgeLines => settings.maxEdgeLines;
  int get _maxShortTermEvents => settings.maxShortTermEvents;
  int get _maxLongTermEvents => settings.maxLongTermEvents;
  int get _maxUltraTermEvents => settings.maxUltraTermEvents;

  static String _buildGuardrail({bool isStory = false}) {
    final typeLabel = isStory ? '故事' : '角色';
    final storySpecificRules = isStory
        ? '''
- 你是故事叙事者，基于上述"故事设定"和"事件记忆"继续讲述故事
- 必须严格遵循"故事设定"中的世界观、规则和人物设定
- 用户的输入是故事的下一步发展，你需要据此续写故事情节
- 保持故事的连贯性和逻辑性，与"事件记忆"中的历史事件保持一致
- 可主动引用"故事设定"中的设定条目来丰富叙事'''
        : '''
- 完全沉浸角色，不跳出设定
- 基于"当前状态"中的情绪、时间、事件调整语气''';
    return '''
【输出格式】必须输出合法 JSON，且仅包含以下结构：
{
  "reply": "$typeLabel回复内容，符合设定",
  "memoryPatch": {
    "worldKnowledge": ["新增的世界观知识，无则[]"],
    "selfKnowledge": ["新增的自我认知，无则[]"],
    "userKnowledge": ["新增的对用户了解，无则[]"],
    "events": [{"time":"","location":"","characters":"","cause":"","process":"","result":"","attitude":""}],
    "belongings": ["(新增)物品名","(提及)物品名，无则[]"],
    "status": ["状态变化，无则[]"],
    "mood": "当前情绪，无则空字符串",
    "time": "当前时间，无则空字符串"
  }
}

规则：
$storySpecificRules
- 可主动提及物品、背景故事、联想事件
- belongings 必须使用 "(新增)物品名" 或 "(提及)物品名" 格式
- 不要输出 Markdown 代码块
''';
  }

  String _buildRoleplayPrompt(Contact contact) {
    final buffer = StringBuffer();
    final isStory = contact.category == ContactCategory.story;

    buffer.writeln('## 基础信息');
    if (isStory) {
      buffer.writeln(' - 故事名称: ${contact.name}');
    } else {
      buffer.writeln(' - 姓名: ${contact.name}');
    }
    if (contact.avatar.isNotEmpty) {
      buffer.writeln(' - 头像: ${contact.avatar}');
    }
    buffer.writeln();

    buffer.writeln(isStory ? '## 故事设定' : '## 角色设定');
    if (isStory) {
      _writeStringList(buffer, '风格', contact.personality);
      if (contact.settings.isNotEmpty) {
        buffer.writeln('### 设定');
        for (final setting in contact.settings) {
          final key = setting['key'] as String? ?? '';
          final value = setting['value'] as String? ?? '';
          final relate = setting['relate'] as List<String>? ?? [];
          if (key.isEmpty || value.isEmpty) continue;
          buffer.writeln(' - $key: $value');
          if (relate.isNotEmpty) {
            buffer.writeln('   关联: ${relate.join(' ')}');
          }
        }
        buffer.writeln();
      }
    } else {
      _writeStringList(buffer, '外貌特征', contact.appearance);
      _writeStringList(buffer, '性格特点', contact.personality);
      _writeStringList(buffer, '个人信息', contact.personalInfo);
    }
    _writeStringList(buffer, '背景故事', contact.backgroundStory);

    buffer.writeln('## 知识储备');
    _writeStringList(buffer, '世界观知识', contact.worldKnowledge.items);
    _writeStringList(buffer, '自我认知', contact.selfKnowledge.items);
    _writeStringList(buffer, '对用户的了解', contact.userKnowledge.items);

    if (contact.belongings.isNotEmpty) {
      buffer.writeln('## 物品持有');
      for (final item in contact.belongings.take(_maxPromptListItems)) {
        final clipped = _clip(item);
        if (clipped.isEmpty) continue;
        buffer.writeln(' - $clipped');
      }
      buffer.writeln();
    }

    _writeEventMemorySections(buffer, contact);
    _writeEdgeSections(buffer, contact);

    buffer.writeln('## 当前状态');
    _writeStringList(buffer, '身体状态', contact.status);
    if (contact.mood.isNotEmpty) {
      buffer.writeln('### 情绪状态');
      buffer.writeln(' - ${_clip(contact.mood)}');
      buffer.writeln();
    }
    if (contact.time.isNotEmpty) {
      buffer.writeln('### 当前时间');
      buffer.writeln(' - ${_clip(contact.time)}');
      buffer.writeln();
    }

    return buffer.toString();
  }

  void _writeStringList(
    StringBuffer buffer,
    String title,
    List<String> items,
  ) {
    if (items.isEmpty) return;
    buffer.writeln('### $title');
    for (final item in items.take(_maxPromptListItems)) {
      final clipped = _clip(item);
      if (clipped.isEmpty) continue;
      buffer.writeln(' - $clipped');
    }
    buffer.writeln();
  }

  void _writeEventMemorySections(StringBuffer buffer, Contact contact) {
    final short =
        contact.eventGraph.shortTermQueue.take(_maxShortTermEvents).toList();
    final long =
        contact.eventGraph.longTermQueue.take(_maxLongTermEvents).toList();
    final history = contact.eventGraph.ultraLongTermQueue
        .take(_maxUltraTermEvents)
        .toList();

    final inGraphKeys = <String>{
      ...short.map((e) => e.event.toPromptLine().trim()),
      ...long.map((e) => e.event.toPromptLine().trim()),
      ...history.map((e) => e.event.toPromptLine().trim()),
    };

    final related = <EventMemory>[];
    final seenRelated = <String>{};
    for (final event in contact.events.items) {
      final key = event.toPromptLine().trim();
      if (key.isEmpty || inGraphKeys.contains(key)) continue;
      if (!seenRelated.add(key)) continue;
      related.add(event);
      if (related.length >= 5) break;
    }

    buffer.writeln('## 事件记忆');
    buffer.writeln('短期事件：');
    _writeEventNodes(buffer, short);
    buffer.writeln('长期总结：');
    _writeEventNodes(buffer, long);
    buffer.writeln('历史事件：');
    _writeEventNodes(buffer, history);
    buffer.writeln('关联事件：');
    _writeEventMemories(buffer, related);
    buffer.writeln();
  }

  void _writeEventNodes(StringBuffer buffer, List<EventNode> nodes) {
    if (nodes.isEmpty) {
      buffer.writeln(' - （无）');
      return;
    }
    for (final node in nodes) {
      final state = node.summarized ? '已总结' : '未总结';
      final line = _clip(node.event.toPromptLine());
      buffer.writeln(' - [$state]${line.isEmpty ? "（空）" : line}');
    }
  }

  void _writeEventMemories(StringBuffer buffer, List<EventMemory> events) {
    if (events.isEmpty) {
      buffer.writeln(' - （无）');
      return;
    }
    for (final event in events) {
      final line = _clip(event.toPromptLine());
      if (line.isEmpty) continue;
      buffer.writeln(' - [联想]$line');
    }
  }

  void _writeEdgeSections(StringBuffer buffer, Contact contact) {
    final allNodes = <EventNode>[
      ...contact.eventGraph.shortTermQueue,
      ...contact.eventGraph.longTermQueue,
      ...contact.eventGraph.ultraLongTermQueue,
    ];
    final idToNode = <String, EventNode>{
      for (final node in allNodes) node.id: node
    };

    final eventEdges = contact.eventGraph.edges.values
        .where((edge) => idToNode.containsKey(edge.fromNodeId))
        .where((edge) => idToNode.containsKey(edge.toNodeId))
        .take(_maxEdgeLines)
        .toList();

    buffer.writeln('## 关系边');
    buffer.writeln('event-event 边：');
    if (eventEdges.isEmpty) {
      buffer.writeln(' - （无）');
    } else {
      for (final edge in eventEdges) {
        final from = idToNode[edge.fromNodeId]!;
        final to = idToNode[edge.toNodeId]!;
        final fromLine = _clip(from.event.toPromptLine());
        final toLine = _clip(to.event.toPromptLine());
        buffer.writeln(
          ' - ${fromLine.isEmpty ? "（空）" : fromLine} -> ${toLine.isEmpty ? "（空）" : toLine}',
        );
      }
    }

    buffer.writeln('event-belongings 边：');
    final lines = <String>[];
    contact.eventGraph.belongingEventQueues.forEach((belonging, queue) {
      if (lines.length >= _maxEdgeLines) return;
      final clippedBelonging = _clip(belonging);
      if (clippedBelonging.isEmpty) return;
      for (final eventId in queue.reversed) {
        if (lines.length >= _maxEdgeLines) break;
        final node = idToNode[eventId];
        if (node == null) continue;
        final line = _clip(node.event.toPromptLine());
        lines.add('$clippedBelonging -> ${line.isEmpty ? "（空）" : line}');
      }
    });
    if (lines.isEmpty) {
      buffer.writeln(' - （无）');
    } else {
      for (final line in lines) {
        buffer.writeln(' - $line');
      }
    }
    buffer.writeln();
  }

  String composeStructuredOutputPrompt({
    required String userInput,
    String? systemPrompt,
    required String outputSchema,
  }) {
    final input = userInput.trim();
    final prompt = (systemPrompt ?? '').trim();
    return <String>[
      if (prompt.isNotEmpty) ...[
        '【系统提示】',
        prompt,
        '',
      ],
      '【用户输入】',
      input,
      '',
      '【输出要求】',
      '1. 必须输出 JSON，不要包含额外说明。',
      '2. 输出必须严格遵循以下 schema：',
      outputSchema,
      '3. JSON 必须可直接解析，不要包含 Markdown 代码块标记。',
    ].join('\n');
  }

  String composeSystemPromptWithContactObject({
    required String basePrompt,
    required Contact contact,
  }) {
    final base = basePrompt.trim();
    final isStory = contact.category == ContactCategory.story;
    final guardrail = _buildGuardrail(isStory: isStory);
    final profile = _buildRoleplayPrompt(contact);
    if (base.isEmpty) return '$guardrail\n\n$profile';
    return '$base\n\n$guardrail\n\n$profile';
  }

  String _clip(String value) {
    final v = value.trim();
    if (v.isEmpty) return '';
    if (v.length <= _maxPromptLineLength) return v;
    return v.substring(0, _maxPromptLineLength);
  }
}
