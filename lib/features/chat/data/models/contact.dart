import 'dart:math';

enum ContactCategory { story, contact, assistant }

class LruReadyBucket {
  const LruReadyBucket._({
    required this.items,
    required this.indexByValue,
  });

  factory LruReadyBucket([List<String> source = const <String>[]]) {
    final normalized = <String>[];
    final index = <String, int>{};
    for (final raw in source) {
      final value = raw.trim();
      if (value.isEmpty) continue;
      if (index.containsKey(value)) continue;
      normalized.add(value);
      index[value] = normalized.length - 1;
    }
    return LruReadyBucket._(
      items: List<String>.unmodifiable(normalized),
      indexByValue: Map<String, int>.unmodifiable(index),
    );
  }

  const LruReadyBucket.empty()
      : items = const <String>[],
        indexByValue = const <String, int>{};

  final List<String> items;
  final Map<String, int> indexByValue;
}

class WorldKnowledgeBucket extends LruReadyBucket {
  factory WorldKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return WorldKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const WorldKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const WorldKnowledgeBucket.empty() : super.empty();
}

class SelfKnowledgeBucket extends LruReadyBucket {
  factory SelfKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return SelfKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const SelfKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const SelfKnowledgeBucket.empty() : super.empty();
}

class UserKnowledgeBucket extends LruReadyBucket {
  factory UserKnowledgeBucket([List<String> source = const <String>[]]) {
    final base = LruReadyBucket(source);
    return UserKnowledgeBucket._(
      items: base.items,
      indexByValue: base.indexByValue,
    );
  }

  const UserKnowledgeBucket._({
    required super.items,
    required super.indexByValue,
  }) : super._();

  const UserKnowledgeBucket.empty() : super.empty();
}

class EventMemory {
  const EventMemory({
    this.time = '',
    this.location = '',
    this.characters = '',
    this.cause = '',
    this.process = '',
    this.result = '',
    this.attitude = '',
  });

  final String time;
  final String location;
  final String characters;
  final String cause;
  final String process;
  final String result;
  final String attitude;

  bool get isEmpty =>
      time.trim().isEmpty &&
      location.trim().isEmpty &&
      characters.trim().isEmpty &&
      cause.trim().isEmpty &&
      process.trim().isEmpty &&
      result.trim().isEmpty &&
      attitude.trim().isEmpty;

  factory EventMemory.fromJson(Map<String, dynamic> json) {
    String read(String key) => (json[key] ?? '').toString().trim();
    return EventMemory(
      time: read('time'),
      location: read('location'),
      characters: read('characters'),
      cause: read('cause'),
      process: read('process'),
      result: read('result'),
      attitude: read('attitude'),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'time': time,
      'location': location,
      'characters': characters,
      'cause': cause,
      'process': process,
      'result': result,
      'attitude': attitude,
    };
  }

  String toPromptLine() {
    final seg = <String>[];
    if (time.trim().isNotEmpty) seg.add('时间=$time');
    if (location.trim().isNotEmpty) seg.add('地点=$location');
    if (characters.trim().isNotEmpty) seg.add('人物=$characters');
    if (cause.trim().isNotEmpty) seg.add('起因=$cause');
    if (process.trim().isNotEmpty) seg.add('经过=$process');
    if (result.trim().isNotEmpty) seg.add('结果=$result');
    if (attitude.trim().isNotEmpty) seg.add('态度=$attitude');
    return seg.join('；');
  }

  String toSearchableText() {
    return '$time $location $characters $cause $process $result $attitude';
  }
}

class EventLruBucket {
  const EventLruBucket._({
    required this.items,
    required this.indexByKey,
  });

  factory EventLruBucket([List<EventMemory> source = const <EventMemory>[]]) {
    final normalized = <EventMemory>[];
    final index = <String, int>{};
    for (final e in source) {
      if (e.isEmpty) continue;
      final key = _eventKey(e);
      if (index.containsKey(key)) continue;
      normalized.add(e);
      index[key] = normalized.length - 1;
    }
    return EventLruBucket._(
      items: List<EventMemory>.unmodifiable(normalized),
      indexByKey: Map<String, int>.unmodifiable(index),
    );
  }

  const EventLruBucket.empty()
      : items = const <EventMemory>[],
        indexByKey = const <String, int>{};

  final List<EventMemory> items;
  final Map<String, int> indexByKey;

  static String _eventKey(EventMemory e) {
    return '${e.time}|${e.location}|${e.characters}|${e.cause}|${e.process}|${e.result}|${e.attitude}';
  }
}

enum EventTier { shortTerm, longTerm, ultraLongTerm }

extension EventTierX on EventTier {
  String get storageKey {
    switch (this) {
      case EventTier.shortTerm:
        return 'short';
      case EventTier.longTerm:
        return 'long';
      case EventTier.ultraLongTerm:
        return 'ultra';
    }
  }
}

class EventNode {
  const EventNode({
    required this.id,
    required this.tier,
    required this.event,
    required this.createdAtMs,
    this.summarized = false,
  });

  final String id;
  final EventTier tier;
  final EventMemory event;
  final int createdAtMs;
  final bool summarized;

  factory EventNode.fromJson(Map<String, dynamic> json) {
    final tierText = (json['tier'] ?? '').toString();
    return EventNode(
      id: (json['id'] ?? '').toString(),
      tier: _eventTierFromStorage(tierText),
      event: EventMemory.fromJson(_asMap(json['event'])),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : 0,
      summarized: json['summarized'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'tier': tier.storageKey,
      'event': event.toJson(),
      'createdAtMs': createdAtMs,
      'summarized': summarized,
    };
  }
}

class EventEdge {
  const EventEdge({
    required this.fromNodeId,
    required this.toNodeId,
  });

  final String fromNodeId;
  final String toNodeId;

  String toUniqueKey() => '$fromNodeId->$toNodeId';

  factory EventEdge.fromJson(Map<String, dynamic> json) {
    return EventEdge(
      fromNodeId: (json['fromNodeId'] ?? '').toString(),
      toNodeId: (json['toNodeId'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fromNodeId': fromNodeId,
      'toNodeId': toNodeId,
    };
  }
}

enum KnowledgeType { world, self, user }

class KnowledgeNode {
  const KnowledgeNode({
    required this.id,
    required this.type,
    required this.content,
    required this.createdAtMs,
  });

  final String id;
  final KnowledgeType type;
  final String content;
  final int createdAtMs;

  factory KnowledgeNode.fromJson(Map<String, dynamic> json) {
    final typeText = (json['type'] ?? '').toString();
    return KnowledgeNode(
      id: (json['id'] ?? '').toString(),
      type: _knowledgeTypeFromStorage(typeText),
      content: (json['content'] ?? '').toString(),
      createdAtMs: (json['createdAtMs'] is num)
          ? (json['createdAtMs'] as num).toInt()
          : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'content': content,
      'createdAtMs': createdAtMs,
    };
  }
}

class EventGraphMemory {
  const EventGraphMemory({
    this.shortTermQueue = const <EventNode>[],
    this.longTermQueue = const <EventNode>[],
    this.ultraLongTermQueue = const <EventNode>[],
    this.knowledgeNodes = const <KnowledgeNode>[],
    this.belongingEventQueues = const <String, List<String>>{},
    this.settingEventQueues = const <String, List<String>>{},
    this.edges = const <EventEdge>[],
    this.turnCount = 0,
  });

  final List<EventNode> shortTermQueue;
  final List<EventNode> longTermQueue;
  final List<EventNode> ultraLongTermQueue;
  final List<KnowledgeNode> knowledgeNodes;
  final Map<String, List<String>> belongingEventQueues;
  final Map<String, List<String>> settingEventQueues;
  final List<EventEdge> edges;
  final int turnCount;

  factory EventGraphMemory.fromJson(Map<String, dynamic> json) {
    return EventGraphMemory(
      shortTermQueue: _readEventNodeList(json['shortTermQueue']),
      longTermQueue: _readEventNodeList(json['longTermQueue']),
      ultraLongTermQueue: _readEventNodeList(json['ultraLongTermQueue']),
      knowledgeNodes: _readKnowledgeNodeList(json['knowledgeNodes']),
      belongingEventQueues:
          _readBelongingEventQueues(json['belongingEventQueues']),
      settingEventQueues: _readBelongingEventQueues(json['settingEventQueues']),
      edges: _readEventEdgeList(json['edges']),
      turnCount:
          (json['turnCount'] is num) ? (json['turnCount'] as num).toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'shortTermQueue': shortTermQueue.map((e) => e.toJson()).toList(),
      'longTermQueue': longTermQueue.map((e) => e.toJson()).toList(),
      'ultraLongTermQueue': ultraLongTermQueue.map((e) => e.toJson()).toList(),
      'knowledgeNodes': knowledgeNodes.map((e) => e.toJson()).toList(),
      'belongingEventQueues': belongingEventQueues,
      'settingEventQueues': settingEventQueues,
      'edges': edges.map((e) => e.toJson()).toList(),
      'turnCount': turnCount,
    };
  }

  EventGraphMemory copyWith({
    List<EventNode>? shortTermQueue,
    List<EventNode>? longTermQueue,
    List<EventNode>? ultraLongTermQueue,
    List<KnowledgeNode>? knowledgeNodes,
    Map<String, List<String>>? belongingEventQueues,
    Map<String, List<String>>? settingEventQueues,
    List<EventEdge>? edges,
    int? turnCount,
  }) {
    return EventGraphMemory(
      shortTermQueue: shortTermQueue ?? this.shortTermQueue,
      longTermQueue: longTermQueue ?? this.longTermQueue,
      ultraLongTermQueue: ultraLongTermQueue ?? this.ultraLongTermQueue,
      knowledgeNodes: knowledgeNodes ?? this.knowledgeNodes,
      belongingEventQueues: belongingEventQueues ?? this.belongingEventQueues,
      settingEventQueues: settingEventQueues ?? this.settingEventQueues,
      edges: edges ?? this.edges,
      turnCount: turnCount ?? this.turnCount,
    );
  }

  List<EventMemory> get memoryEventsForPrompt {
    final short = shortTermQueue.where((e) => !e.summarized).take(10).toList();
    final long = longTermQueue.where((e) => !e.summarized).take(5).toList();
    final ultra = ultraLongTermQueue.take(2).toList();
    return <EventMemory>[
      ...short.map((e) => e.event),
      ...long.map((e) => e.event),
      ...ultra.map((e) => e.event),
    ];
  }

  List<EventMemory> relatedEventsForPrompt(String userInput, {int maxResults = 5}) {
    final keywords = _extractKeywords(userInput);
    if (keywords.isEmpty) return const <EventMemory>[];

    final allNodes = <EventNode>[
      ...shortTermQueue,
      ...longTermQueue,
      ...ultraLongTermQueue,
    ];
    if (allNodes.isEmpty) return const <EventMemory>[];

    final scored = <_ScoredNode>[];
    for (final node in allNodes) {
      final score = _keywordHitCount(
        keywords,
        _extractKeywords(node.event.toSearchableText()),
      );
      if (score > 0) scored.add(_ScoredNode(node: node, score: score));
    }
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      return b.node.createdAtMs.compareTo(a.node.createdAtMs);
    });

    final idToNode = <String, EventNode>{for (final n in allNodes) n.id: n};
    final adjacent = <String, Set<String>>{};
    for (final edge in edges) {
      adjacent
          .putIfAbsent(edge.fromNodeId, () => <String>{})
          .add(edge.toNodeId);
      adjacent
          .putIfAbsent(edge.toNodeId, () => <String>{})
          .add(edge.fromNodeId);
    }

    final result = <EventMemory>[];
    final seen = <String>{};

    for (final hit in scored) {
      if (result.length >= maxResults) break;
      if (seen.add(hit.node.id)) result.add(hit.node.event);
      final neighbors = adjacent[hit.node.id] ?? const <String>{};
      for (final id in neighbors) {
        if (result.length >= maxResults) break;
        final node = idToNode[id];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    if (result.length >= maxResults) return result.take(maxResults).toList();

    final scoredBelongings = <_ScoredBelonging>[];
    for (final key in belongingEventQueues.keys) {
      final score = _keywordHitCount(keywords, _extractKeywords(key));
      if (score > 0) {
        scoredBelongings.add(_ScoredBelonging(name: key, score: score));
      }
    }
    scoredBelongings.sort((a, b) => b.score.compareTo(a.score));
    for (final b in scoredBelongings) {
      final queue = belongingEventQueues[b.name] ?? const <String>[];
      for (final eventId in queue.reversed) {
        if (result.length >= maxResults) break;
        final node = idToNode[eventId];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    // 搜索 settingEventQueues（类似 belongings 的搜索逻辑）
    final scoredSettings = <_ScoredSetting>[];
    for (final key in settingEventQueues.keys) {
      final score = _keywordHitCount(keywords, _extractKeywords(key));
      if (score > 0) {
        scoredSettings.add(_ScoredSetting(key: key, score: score));
      }
    }
    scoredSettings.sort((a, b) => b.score.compareTo(a.score));
    for (final s in scoredSettings) {
      final queue = settingEventQueues[s.key] ?? const <String>[];
      for (final eventId in queue.reversed) {
        if (result.length >= maxResults) break;
        final node = idToNode[eventId];
        if (node == null) continue;
        if (seen.add(node.id)) result.add(node.event);
      }
    }

    return result.take(maxResults).toList();
  }

  static int _keywordHitCount(Set<String> lhs, Set<String> rhs) {
    var c = 0;
    for (final k in lhs) {
      if (rhs.contains(k)) c++;
    }
    return c;
  }

  static final RegExp _tokenReg = RegExp(r'[\u4e00-\u9fffA-Za-z0-9_]{2,}');

  static Set<String> _extractKeywords(String raw) {
    final out = <String>{};
    for (final m in _tokenReg.allMatches(raw.toLowerCase())) {
      final token = m.group(0)?.trim();
      if (token == null || token.isEmpty) continue;
      out.add(token);
    }
    return out;
  }
}

class _ScoredNode {
  const _ScoredNode({required this.node, required this.score});
  final EventNode node;
  final int score;
}

class _ScoredBelonging {
  const _ScoredBelonging({required this.name, required this.score});
  final String name;
  final int score;
}

class _ScoredSetting {
  const _ScoredSetting({required this.key, required this.score});
  final String key;
  final int score;
}

class Contact {
  Contact({
    required this.id,
    required this.name,
    required this.avatar,
    this.category = ContactCategory.contact,
    this.personality = const <String>[],
    this.appearance = const <String>[],
    this.personalInfo = const <String>[],
    this.settings = const <Map<String, dynamic>>[],
    this.backgroundStory = const <String>[],
    this.worldKnowledge = const WorldKnowledgeBucket.empty(),
    this.selfKnowledge = const SelfKnowledgeBucket.empty(),
    this.userKnowledge = const UserKnowledgeBucket.empty(),
    this.events = const EventLruBucket.empty(),
    this.eventGraph = const EventGraphMemory(),
    this.belongings = const <String>[],
    this.status = const <String>[],
    this.mood = '',
    this.time = '',
    required this.createdAt,
  });

  final String id;
  final String name;
  final String avatar;
  final ContactCategory category;
  final List<String> personality;
  final List<String> appearance;
  final List<String> personalInfo;
  final List<Map<String, dynamic>> settings;
  final List<String> backgroundStory;
  final WorldKnowledgeBucket worldKnowledge;
  final SelfKnowledgeBucket selfKnowledge;
  final UserKnowledgeBucket userKnowledge;
  final EventLruBucket events;
  final EventGraphMemory eventGraph;
  final List<String> belongings;
  final List<String> status;
  final String mood;
  final String time;
  final DateTime createdAt;

  factory Contact.fromJson(Map<String, dynamic> json) {
    final categoryText = (json['category'] ?? '').toString();
    final createdAtIso = (json['createdAt'] ?? '').toString();
    final createdAtMs =
        (json['createdAtMs'] is num) ? (json['createdAtMs'] as num).toInt() : 0;
    return Contact(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      avatar: (json['avatar'] ?? '').toString(),
      category: _contactCategoryFromStorage(categoryText),
      personality: _readStringList(json['personality']),
      appearance: _readStringList(json['appearance']),
      personalInfo: _readStringList(json['personalInfo']),
      settings: _readSettingsList(json['settings']),
      backgroundStory: _readStringList(json['backgroundStory']),
      worldKnowledge:
          WorldKnowledgeBucket(_readStringList(json['worldKnowledge'])),
      selfKnowledge:
          SelfKnowledgeBucket(_readStringList(json['selfKnowledge'])),
      userKnowledge:
          UserKnowledgeBucket(_readStringList(json['userKnowledge'])),
      events: EventLruBucket(_readEventMemoryList(json['events'])),
      eventGraph: EventGraphMemory.fromJson(_asMap(json['eventGraph'])),
      belongings: _readStringList(json['belongings']),
      status: _readStringList(json['status']),
      mood: (json['mood'] ?? '').toString(),
      time: (json['time'] ?? '').toString(),
      createdAt: DateTime.tryParse(createdAtIso) ??
          DateTime.fromMillisecondsSinceEpoch(createdAtMs),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'avatar': avatar,
      'category': category.name,
      'personality': personality,
      'appearance': appearance,
      'personalInfo': personalInfo,
      'settings': settings,
      'backgroundStory': backgroundStory,
      'worldKnowledge': worldKnowledge.items,
      'selfKnowledge': selfKnowledge.items,
      'userKnowledge': userKnowledge.items,
      'events': events.items.map((e) => e.toJson()).toList(),
      'eventGraph': eventGraph.toJson(),
      'belongings': belongings,
      'status': status,
      'mood': mood,
      'time': time,
      'createdAt': createdAt.toIso8601String(),
      'createdAtMs': createdAt.millisecondsSinceEpoch,
    };
  }
}

Contact demoContact() {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  return Contact(
    id: 'demo-1',
    name: '阿星',
    avatar: '',
    personality: const <String>['直接', '理性'],
    appearance: const <String>['黑色外套'],
    backgroundStory: const <String>['与用户共同调查旧城区谜案'],
    worldKnowledge: WorldKnowledgeBucket(const <String>['旧城区夜里常停电']),
    selfKnowledge: SelfKnowledgeBucket(const <String>['擅长记录线索']),
    userKnowledge: UserKnowledgeBucket(const <String>['用户喜欢先看证据再下结论']),
    events: const EventLruBucket.empty(),
    eventGraph: EventGraphMemory(
      shortTermQueue: <EventNode>[
        EventNode(
          id: 'short-1',
          tier: EventTier.shortTerm,
          event: const EventMemory(
            time: '今晚',
            location: '旧城区钟楼',
            characters: '我、你',
            process: '巡查并记录停电异常',
          ),
          createdAtMs: nowMs,
        ),
      ],
    ),
    belongings: const <String>['手电筒'],
    status: const <String>['轻微疲劳'],
    mood: '专注',
    time: '深夜',
    category: ContactCategory.contact,
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
  );
}

ContactCategory _contactCategoryFromStorage(String raw) {
  for (final c in ContactCategory.values) {
    if (c.name == raw) return c;
  }
  return ContactCategory.contact;
}

EventTier _eventTierFromStorage(String raw) {
  for (final tier in EventTier.values) {
    if (tier.storageKey == raw || tier.name == raw) return tier;
  }
  return EventTier.shortTerm;
}

KnowledgeType _knowledgeTypeFromStorage(String raw) {
  for (final type in KnowledgeType.values) {
    if (type.name == raw) return type;
  }
  return KnowledgeType.world;
}

List<String> _readStringList(dynamic value) {
  if (value is! List) return const <String>[];
  return value
      .map((e) => e?.toString().trim() ?? '')
      .where((e) => e.isNotEmpty)
      .toList();
}

List<EventMemory> _readEventMemoryList(dynamic value) {
  if (value is! List) return const <EventMemory>[];
  final out = <EventMemory>[];
  for (final item in value) {
    if (item is! Map) continue;
    final event = EventMemory.fromJson(_asMap(item));
    if (!event.isEmpty) out.add(event);
  }
  return out;
}

List<EventNode> _readEventNodeList(dynamic value) {
  if (value is! List) return const <EventNode>[];
  final out = <EventNode>[];
  for (final item in value) {
    if (item is! Map) continue;
    final node = EventNode.fromJson(_asMap(item));
    if (node.id.trim().isEmpty) continue;
    out.add(node);
  }
  return out;
}

List<Map<String, dynamic>> _readSettingsList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  final out = <Map<String, dynamic>>[];
  for (final item in value) {
    if (item is! Map) continue;
    final map = _asMap(item);
    final key = (map['key'] ?? '').toString().trim();
    final value = (map['value'] ?? '').toString().trim();
    if (key.isEmpty || value.isEmpty) continue;
    final relate = _readStringList(map['relate']);
    out.add({
      'key': key,
      'value': value,
      'relate': relate,
    });
  }
  return out;
}

List<KnowledgeNode> _readKnowledgeNodeList(dynamic value) {
  if (value is! List) return const <KnowledgeNode>[];
  final out = <KnowledgeNode>[];
  for (final item in value) {
    if (item is! Map) continue;
    final node = KnowledgeNode.fromJson(_asMap(item));
    if (node.id.trim().isEmpty || node.content.trim().isEmpty) continue;
    out.add(node);
  }
  return out;
}

List<EventEdge> _readEventEdgeList(dynamic value) {
  if (value is! List) return const <EventEdge>[];
  final out = <EventEdge>[];
  final seen = <String>{};
  for (final item in value) {
    if (item is! Map) continue;
    final edge = EventEdge.fromJson(_asMap(item));
    if (edge.fromNodeId.trim().isEmpty || edge.toNodeId.trim().isEmpty) {
      continue;
    }
    if (!seen.add(edge.toUniqueKey())) continue;
    out.add(edge);
  }
  return out;
}

Map<String, List<String>> _readBelongingEventQueues(dynamic value) {
  if (value is! Map) return const <String, List<String>>{};
  final out = <String, List<String>>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isEmpty) continue;
    final ids = _readStringList(entry.value);
    if (ids.isEmpty) continue;
    out[key] = ids;
  }
  return out;
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, dynamic>{};
}
