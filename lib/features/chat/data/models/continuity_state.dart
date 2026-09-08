/// 用户为当前故事定义的记录项。ID 稳定，改名不会改变当前值的归属。
class StateDefinition {
  const StateDefinition(
      {required this.id,
      required this.name,
      this.description = '',
      this.initialValue = '',
      this.updateRule = ''});
  final String id;
  final String name;
  final String description;
  final String initialValue;
  final String updateRule;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'initialValue': initialValue,
        'updateRule': updateRule
      };
  factory StateDefinition.fromJson(Map json) {
    for (final key in [
      'id',
      'name',
      'description',
      'initialValue',
      'updateRule'
    ]) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('状态定义必须使用文本');
      }
    }
    return StateDefinition(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        initialValue: json['initialValue'] as String? ?? '',
        updateRule: json['updateRule'] as String? ?? '');
  }
}

/// 通用故事状态：定义低频变化，当前值按稳定 ID 单独保存。
class ContinuityState {
  const ContinuityState.empty()
      : revision = 0,
        definitions = const [],
        values = const {};
  ContinuityState(
      {required this.revision,
      required Map<String, String> values,
      List<StateDefinition>? definitions})
      : definitions = List.unmodifiable(definitions ??
            [
              for (final e in values.entries)
                StateDefinition(id: e.key, name: e.key, initialValue: e.value)
            ]),
        values = Map.unmodifiable(values) {
    final ids = <String>{};
    final names = <String>{};
    for (final definition in this.definitions) {
      if (definition.id.trim().isEmpty ||
          definition.name.trim().isEmpty ||
          !ids.add(definition.id) ||
          !names.add(definition.name.trim())) {
        throw const FormatException('状态名称和 ID 不能为空或重复');
      }
    }
    if (revision < 0 || values.keys.any((key) => !ids.contains(key))) {
      throw const FormatException('当前值不属于已定义的状态');
    }
  }
  final int revision;
  final List<StateDefinition> definitions;
  final Map<String, String> values;

  Map<String, String> get byName =>
      {for (final d in definitions) d.name: values[d.id] ?? d.initialValue};
  ContinuityState withLegacy(Map<String, String> legacy) {
    if (legacy.isEmpty) return this;
    final items = [...definitions];
    final next = {...values};
    for (final entry in legacy.entries) {
      if (entry.key.trim().isEmpty || items.any((d) => d.name == entry.key)) {
        continue;
      }
      var id = entry.key;
      while (items.any((d) => d.id == id)) {
        id = 'legacy:$id';
      }
      items.add(
          StateDefinition(id: id, name: entry.key, initialValue: entry.value));
      next[id] = entry.value;
    }
    return ContinuityState(
        revision: revision, definitions: items, values: next);
  }

  factory ContinuityState.fromJson(dynamic json) {
    if (json == null) return const ContinuityState.empty();
    if (json is! Map || json['values'] is! Map || json['revision'] is! int) {
      throw const FormatException('故事状态格式错误');
    }
    final values = <String, String>{};
    for (final entry in (json['values'] as Map).entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const FormatException('状态值必须使用文本');
      }
      values[entry.key as String] = entry.value as String;
    }
    final raw = json['definitions'];
    if (raw != null && raw is! List) throw const FormatException('状态定义格式错误');
    final definitions = raw == null
        ? null
        : (raw as List).map((item) {
            if (item is! Map) throw const FormatException('状态定义格式错误');
            return StateDefinition.fromJson(item);
          }).toList();
    return ContinuityState(
        revision: json['revision'] as int,
        definitions: definitions,
        values: values);
  }
  Map<String, dynamic> toJson() => {
        'schemaVersion': 2,
        'revision': revision,
        'definitions': definitions.map((d) => d.toJson()).toList(),
        'values': {
          for (final d in definitions) d.id: values[d.id] ?? d.initialValue
        }
      };
}
