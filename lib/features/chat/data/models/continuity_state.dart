/// 用户为当前故事定义的记录项。ID 稳定，改名不会改变当前值的归属。
class StateDefinition {
  const StateDefinition(
      {required this.id,
      required this.name,
      this.description = '',
      this.initialValue = '',
      this.type = 'string',
      this.enumValues = const [],
      this.updateRule = ''});
  final String id;
  final String name;
  final String description;
  final String initialValue;
  final String type;
  final List<String> enumValues;
  final String updateRule;

  // Explicit clearing remains supported; nonempty values obey the enum.
  bool accepts(String value) =>
      value.isEmpty || enumValues.isEmpty || enumValues.contains(value);

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': name,
        'type': type,
        if (enumValues.isNotEmpty) 'enum': enumValues,
        'description': description,
        'defaultValue': initialValue,
        'updateRule': updateRule
      };

  // Old reversible journals compare these keys exactly; preserve their shape.
  Map<String, dynamic> toStorageJson() => {
        'id': id,
        'name': name,
        'description': description,
        'initialValue': initialValue,
        'updateRule': updateRule,
        if (enumValues.isNotEmpty) 'enum': enumValues,
      };
  factory StateDefinition.fromJson(Map json) {
    for (final key in [
      'id',
      'name',
      'label',
      'type',
      'description',
      'initialValue',
      'defaultValue',
      'updateRule'
    ]) {
      if (json[key] != null && json[key] is! String) {
        throw const FormatException('状态定义必须使用文本');
      }
    }
    for (final pair in [('label', 'name'), ('defaultValue', 'initialValue')]) {
      if (json[pair.$1] != null &&
          json[pair.$2] != null &&
          json[pair.$1] != json[pair.$2]) {
        throw FormatException('${pair.$1} 与旧字段 ${pair.$2} 的内容冲突');
      }
    }
    final options = json['enum'];
    if (options != null &&
        (options is! List || options.any((v) => v is! String))) {
      throw const FormatException('enum 必须是文本数组');
    }
    return StateDefinition(
        id: json['id'] as String? ?? '',
        name: (json['label'] ?? json['name']) as String? ?? '',
        type: json['type'] as String? ?? 'string',
        enumValues: List<String>.unmodifiable(options as List? ?? const []),
        description: json['description'] as String? ?? '',
        initialValue:
            (json['defaultValue'] ?? json['initialValue']) as String? ?? '',
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
      if (definition.type != 'string') {
        throw FormatException('状态 ${definition.id} 的 type 仅支持 string');
      }
      if (definition.enumValues.any((v) => v.trim().isEmpty) ||
          definition.enumValues.toSet().length !=
              definition.enumValues.length) {
        throw FormatException('状态 ${definition.id} 的 enum 选项不能为空或重复');
      }
      if (!definition.accepts(definition.initialValue) ||
          !definition
              .accepts(values[definition.id] ?? definition.initialValue)) {
        throw FormatException(
            '状态 ${definition.id} 的默认值或当前值必须属于 enum：${definition.enumValues.join('、')}');
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
  Map<String, dynamic> toStorageJson() => {
        ...toJson(),
        'definitions': definitions.map((d) => d.toStorageJson()).toList(),
      };
}
