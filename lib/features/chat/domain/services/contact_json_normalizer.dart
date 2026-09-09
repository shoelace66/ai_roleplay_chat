import 'dart:convert';
import '../../data/models/continuity_state.dart';

/// Import-only compatibility. Runtime state transitions and backups stay strict.
class ContactImportIssue {
  const ContactImportIssue(this.path, this.message,
      {this.isError = false, this.offset});

  final String path;
  final String message;
  final bool isError;
  final int? offset;

  String get description => '$path：$message';
}

class ContactJsonNormalization {
  const ContactJsonNormalization(this.json, this.issues);
  final Map<String, dynamic>? json;
  final List<ContactImportIssue> issues;
}

class ContactJsonNormalizer {
  final List<ContactImportIssue> _issues = [];

  static const _fields = <String, List<String>>{
    'id': ['角色id', '故事id'],
    'name': [
      '名称',
      '名字',
      '角色名称',
      '角色名',
      '故事名称',
      '故事名',
      'title',
      'char_name',
      'characterName'
    ],
    'avatar': ['头像', 'emoji', 'icon'],
    'fixedInput': [
      '固定输入',
      '固定输入内容',
      '固定设定',
      '角色设定',
      '系统提示词',
      'systemPrompt',
      'prompt',
      'description',
      'char_persona'
    ],
    'currentStates': ['当前状态', '状态记录', 'states', 'currentState'],
    'continuity': ['故事状态', '连续性状态'],
    'personality': ['性格', '性格特征'],
    'appearance': ['外貌', '外观', '外貌特征'],
    'personalInfo': ['个人信息', '基本信息'],
    'settings': ['设定', '世界设定'],
    'backgroundStory': ['背景', '背景故事', 'background', 'backstory', 'scenario'],
    'narrativeRules': ['叙事规则', '写作规则'],
    'otherCharacteristics': ['其他特征', '其他特点'],
    'worldKnowledge': ['世界知识'],
    'selfKnowledge': ['自身知识', '角色知识'],
    'userKnowledge': ['用户知识'],
    'belongings': ['物品', '随身物品', 'inventory'],
    'status': ['状态', '角色状态'],
    'mood': ['心情', '情绪'],
    'time': ['时间'],
    'voice': ['音色', 'voiceId'],
  };
  static const _listFields = {
    'personality',
    'appearance',
    'personalInfo',
    'backgroundStory',
    'narrativeRules',
    'otherCharacteristics',
    'worldKnowledge',
    'selfKnowledge',
    'userKnowledge',
    'belongings',
    'status',
  };

  ContactJsonNormalization normalize(String source) {
    _issues.clear();
    final prepared = _prepare(source);
    dynamic decoded;
    try {
      decoded = jsonDecode(prepared);
    } on FormatException catch (error) {
      final offset = (error.offset ?? 0).clamp(0, prepared.length);
      final prefix = prepared.substring(0, offset);
      final line = '\n'.allMatches(prefix).length + 1;
      final column = offset - prefix.lastIndexOf('\n');
      final character = _characterAt(prepared, offset);
      final excerpt = _lineExcerpt(prepared, offset);
      _error(
          r'$',
          'JSON 语法错误，第 $line 行、第 $column 列，出错字符：$character。'
              '${error.message}。\n$excerpt\n'
              '请检查这个字符之前是否缺少逗号、冒号或引号，以及括号是否配对。'
              '位置按兼容处理后的文本计算。',
          offset: prepared == source ? offset : null);
      return ContactJsonNormalization(null, List.unmodifiable(_issues));
    }
    for (var depth = 0; depth < 4; depth++) {
      if (decoded is List) {
        if (decoded.length != 1 || decoded.single is! Map) {
          _error(r'$', '需要一个角色/故事对象；数组只能包含一个对象，不能一次导入多个。');
          return ContactJsonNormalization(null, List.unmodifiable(_issues));
        }
        decoded = decoded.single;
        _note(r'$', '已取出单元素数组中的对象。');
        continue;
      }
      if (decoded is! Map) break;
      final map = Map<String, dynamic>.from(decoded);
      if (map.keys.any((key) => _match(key, _fields, fuzzy: false) == 'name')) {
        break;
      }
      const wrappers = {
        'data',
        'character',
        'story',
        'contact',
        '角色',
        '故事',
        '角色卡'
      };
      final candidates = map.keys
          .where((key) =>
              wrappers.contains(_key(key)) &&
              (map[key] is Map || map[key] is List))
          .toList();
      if (candidates.length > 1) {
        _error(r'$', '发现多个对象包装字段：${candidates.join('、')}，请只保留要创建的对象。');
        return ContactJsonNormalization(null, List.unmodifiable(_issues));
      }
      if (candidates.isEmpty) break;
      final wrapper = candidates.single;
      for (final key in map.keys.where((key) => key != wrapper)) {
        _note('\$.$key', '包装对象外的字段不参与导入，请确认没有需要保留的内容。');
      }
      decoded = map[wrapper];
      _note('\$.$wrapper', '已取出包装内的角色/故事对象。');
    }
    if (decoded is! Map) {
      _error(r'$', '顶层需要 JSON 对象，例如 {"name":"角色名称"}。');
      return ContactJsonNormalization(null, List.unmodifiable(_issues));
    }
    final json = _canonicalize(decoded, _fields, r'$');
    for (final key in json.keys.toList()) {
      final path = '\$.$key';
      if (_listFields.contains(key)) {
        json[key] = _list(json[key], path);
      } else if (key == 'currentStates') {
        json[key] = _values(json[key], path);
      } else if (key == 'continuity') {
        if (json[key] != null) json[key] = _continuity(json[key]);
      } else if (key == 'settings') {
        json[key] = _settings(json[key]);
      } else {
        json[key] = _text(json[key], path);
      }
    }
    return ContactJsonNormalization(json, List.unmodifiable(_issues));
  }

  String _prepare(String source) {
    var text = source.trim().replaceFirst(RegExp('^\uFEFF'), '');
    final fence = RegExp(r'^```(?:json|jsonc)?\s*\n?([\s\S]*?)\n?```$',
            caseSensitive: false)
        .firstMatch(text);
    if (fence != null) {
      text = fence.group(1)!.trim();
      _note(r'$', '已移除 Markdown 代码块标记。');
    }
    // A token-aware scan: never alter commas, comments, or quotes inside text.
    final chars = text.split('');
    var quoted = false;
    var escaped = false;
    var comments = false;
    var unicodeSpaces = false;
    var fullWidthPunctuation = false;
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
        continue;
      }
      if (c == '"') {
        quoted = true;
        continue;
      }
      final normalizedSpace = _outsideStringSpace(c);
      if (normalizedSpace != null) {
        chars[i] = normalizedSpace;
        unicodeSpaces = true;
        continue;
      }
      final normalizedPunctuation = const {
        '｛': '{',
        '｝': '}',
        '［': '[',
        '］': ']',
        '：': ':',
        '，': ',',
      }[c];
      if (normalizedPunctuation != null) {
        chars[i] = normalizedPunctuation;
        fullWidthPunctuation = true;
        continue;
      }
      if (c != '/' || i + 1 >= chars.length) continue;
      if (chars[i + 1] == '/') {
        comments = true;
        while (i < chars.length && chars[i] != '\n') {
          chars[i++] = ' ';
        }
      } else if (chars[i + 1] == '*') {
        final end = text.indexOf('*/', i + 2);
        if (end == -1) {
          continue; // Keep malformed comments for syntax diagnostics.
        }
        comments = true;
        while (i <= end + 1) {
          if (chars[i] != '\n' && chars[i] != '\r') chars[i] = ' ';
          i++;
        }
        i--;
      }
    }
    if (unicodeSpaces) {
      _note(r'$', '已将字符串外的全角空格、不换行空格等 Unicode 空白转换为标准 JSON 空白；字符串内原样保留。');
    }
    if (fullWidthPunctuation) {
      _note(r'$', '已将字符串外的全角大括号、方括号、冒号或逗号转换为半角 JSON 标点。');
    }
    if (comments) _note(r'$', '已移除字符串外的 JSON 注释。');
    quoted = false;
    escaped = false;
    var trailing = false;
    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
        continue;
      }
      if (c == '"') {
        quoted = true;
        continue;
      }
      if (c != ',') continue;
      var next = i + 1;
      while (next < chars.length && chars[next].trim().isEmpty) {
        next++;
      }
      if (next < chars.length && (chars[next] == ']' || chars[next] == '}')) {
        chars[i] = ' ';
        trailing = true;
      }
    }
    if (trailing) _note(r'$', '已移除对象或数组末尾多余的逗号。');
    return chars.join();
  }

  String _key(String key) => key.trim().toLowerCase().replaceAll(
      RegExp(r'[\s_\-\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]'), '');

  String? _outsideStringSpace(String value) {
    if (value == '\u2028' || value == '\u2029') return '\n';
    if (RegExp(r'^[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000\ufeff]$')
        .hasMatch(value)) {
      return ' ';
    }
    return null;
  }

  String _characterAt(String source, int offset) {
    if (offset >= source.length) return '文件结尾 EOF';
    final first = source.codeUnitAt(offset);
    var rune = first;
    if (first >= 0xD800 && first <= 0xDBFF && offset + 1 < source.length) {
      final second = source.codeUnitAt(offset + 1);
      if (second >= 0xDC00 && second <= 0xDFFF) {
        rune = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
      }
    }
    final value = String.fromCharCode(rune);
    final code = rune
        .toRadixString(16)
        .toUpperCase()
        .padLeft(rune > 0xFFFF ? 6 : 4, '0');
    final label = switch (value) {
      ' ' => '半角空格',
      '\t' => r'制表符 \t',
      '\n' => r'换行符 \n',
      '\r' => r'回车符 \r',
      '　' => '全角空格',
      _ => '“${value.replaceAll('`', r'\`')}”',
    };
    return '$label（U+$code）';
  }

  String _lineExcerpt(String source, int offset) {
    final safeOffset = offset.clamp(0, source.length);
    final start =
        source.lastIndexOf('\n', safeOffset == 0 ? 0 : safeOffset - 1) + 1;
    var end = source.indexOf('\n', safeOffset);
    if (end < 0) end = source.length;
    var line = source.substring(start, end).replaceAll('\t', '→   ');
    var caret =
        source.substring(start, safeOffset).replaceAll('\t', '    ').length;
    if (line.length > 80) {
      final windowStart = (caret - 32).clamp(0, line.length);
      final windowEnd = (windowStart + 72).clamp(0, line.length);
      line =
          '${windowStart > 0 ? '…' : ''}${line.substring(windowStart, windowEnd)}${windowEnd < line.length ? '…' : ''}';
      caret = caret - windowStart + (windowStart > 0 ? 1 : 0);
    }
    return '附近：$line\n定位：${' ' * caret}↑';
  }

  String? _match(String key, Map<String, List<String>> fields,
      {bool fuzzy = true}) {
    final normalized = _key(key);
    for (final field in fields.entries) {
      if ([field.key, ...field.value]
          .any((alias) => _key(alias) == normalized)) {
        return field.key;
      }
    }
    // Only an unambiguous, one-character ASCII typo on a sufficiently long key.
    // Short names/IDs and user-defined state keys must never be guessed.
    if (!fuzzy || !RegExp(r'^[a-z]{5,}$').hasMatch(normalized)) return null;
    final matches = fields.keys
        .where((field) => _oneEdit(normalized, _key(field)))
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  bool _oneEdit(String a, String b) {
    if ((a.length - b.length).abs() > 1) return false;
    var left = 0, right = 0, changes = 0;
    while (left < a.length && right < b.length) {
      if (a[left] == b[right]) {
        left++;
        right++;
        continue;
      }
      if (++changes > 1) return false;
      if (a.length == b.length) {
        if (left + 1 < a.length &&
            a[left] == b[right + 1] &&
            a[left + 1] == b[right]) {
          left++;
          right++;
        }
        left++;
        right++;
      } else if (a.length > b.length) {
        left++;
      } else {
        right++;
      }
    }
    return changes + (a.length - left) + (b.length - right) == 1;
  }

  Map<String, dynamic> _canonicalize(
      Map raw, Map<String, List<String>> fields, String path) {
    final result = <String, dynamic>{};
    final original = <String, String>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final canonical = _match(key, fields);
      if (canonical == null) {
        _note('$path.$key', '未识别的字段，不会导入；请检查字段名或将内容移到 fixedInput（固定设定）。');
        continue;
      }
      if (result.containsKey(canonical)) {
        if (jsonEncode(result[canonical]) != jsonEncode(entry.value)) {
          _error('$path.$key',
              '与 ${original[canonical]} 都对应 $canonical，但内容不同，请只保留一个。');
        } else {
          _note('$path.$key', '与 ${original[canonical]} 内容相同，已合并。');
        }
        continue;
      }
      if (key != canonical) _note('$path.$key', '已匹配为 $canonical。');
      original[canonical] = key;
      result[canonical] = entry.value;
    }
    return result;
  }

  String _text(dynamic value, String path) {
    if (value == null) return '';
    if (value is String) return value.trim();
    if (value is num || value is bool) {
      _note(path, '已将${value is num ? '数字' : '布尔值'}转为文本。');
      return value.toString();
    }
    _error(path, '需要文本，实际是${_type(value)}；例如 "文字内容"。');
    return '';
  }

  List<String> _list(dynamic value, String path) {
    if (value == null) return [];
    if (value is! List) {
      if (value is String || value is num || value is bool) {
        _note(path, '需要文本数组，已把单个值作为一项保留。');
        final item = _text(value, path);
        return item.isEmpty ? [] : [item];
      }
      _error(path, '需要文本或文本数组，实际是${_type(value)}；例如 ["理性", "温柔"]。');
      return [];
    }
    return [for (var i = 0; i < value.length; i++) _text(value[i], '$path[$i]')]
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Map<String, String> _values(dynamic value, String path) {
    if (value == null) return {};
    if (value is! Map) {
      _error(path, '需要“名称: 当前值”的对象，实际是${_type(value)}；例如 {"地点":"车站"}。');
      return {};
    }
    final result = <String, String>{};
    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) {
        _error(path, '状态名称或 ID 不能为空。');
        continue;
      }
      if (result.containsKey(key)) {
        _error('$path.$key', '去掉首尾空格后与其他状态重复。');
        continue;
      }
      result[key] = _text(entry.value, '$path.$key');
    }
    return result;
  }

  List<Map<String, dynamic>> _settings(dynamic raw) {
    const path = r'$.settings';
    if (raw == null) return [];
    if (raw is String) {
      _note(path, '已将文本作为一条设定保留。');
      return raw.trim().isEmpty
          ? []
          : [
              {'key': '设定', 'value': raw.trim(), 'relate': <String>[]}
            ];
    }
    if (raw is Map) {
      _note(path, '已将键值对象转换为设定列表。');
      raw = [
        for (final entry in raw.entries)
          {'key': entry.key, 'value': entry.value}
      ];
    }
    if (raw is! List) {
      _error(path, '需要设定数组或键值对象，实际是${_type(raw)}。');
      return [];
    }
    final result = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] is! Map) {
        _error('$path[$i]', '需要含 key 和 value 的对象。');
        continue;
      }
      final item = _canonicalize(
          raw[i] as Map,
          const {
            'key': ['name', '名称', '键'],
            'value': ['内容', '值'],
            'relate': ['关联', '相关', 'related']
          },
          '$path[$i]');
      final key = _text(item['key'], '$path[$i].key');
      final value = _text(item['value'], '$path[$i].value');
      if (key.isEmpty || value.isEmpty) {
        _note('$path[$i]', 'key 或 value 为空，这条空设定不会导入。');
        continue;
      }
      result.add({
        'key': key,
        'value': value,
        'relate': _list(item['relate'], '$path[$i].relate')
      });
    }
    return result;
  }

  Map<String, dynamic> _continuity(dynamic raw) {
    const path = r'$.continuity';
    if (raw is! Map) {
      _error(path, '需要含 definitions 和 values 的对象，实际是${_type(raw)}。');
      return {};
    }
    final json = _canonicalize(
        raw,
        const {
          'schemaVersion': ['格式版本'],
          'revision': ['版本', 'version'],
          'definitions': ['定义', '状态定义', '记录项'],
          'values': ['当前值', '状态值'],
        },
        path);
    final revision = json['revision'];
    if (revision == null) {
      json['revision'] = 0;
      _note('$path.revision', '未提供版本号，按新角色使用 0。');
    } else if (revision is String && int.tryParse(revision.trim()) != null) {
      json['revision'] = int.parse(revision.trim());
      _note('$path.revision', '已将文本版本号转为整数。');
    }
    if (json['revision'] is! int || (json['revision'] as int) < 0) {
      _error('$path.revision', '需要大于等于 0 的整数。');
      json['revision'] = 0;
    }
    final values = _values(json['values'], '$path.values');
    final definitions = json['definitions'];
    if (definitions != null && definitions is! List) {
      _error('$path.definitions',
          '需要状态定义数组，例如 [{"id":"location","label":"地点","type":"string"}]。');
    } else if (definitions is List) {
      final items = <Map<String, dynamic>>[];
      final ids = <String>{};
      final names = <String>{};
      for (var i = 0; i < definitions.length; i++) {
        final itemPath = '$path.definitions[$i]';
        if (definitions[i] is! Map) {
          _error(itemPath, '每条定义都需要是对象。');
          continue;
        }
        final item = _canonicalize(
            definitions[i] as Map,
            const {
              'id': ['标识'],
              'label': ['名称', '状态名称', 'name'],
              'type': ['类型'],
              'enum': ['选项', '可选值', '枚举'],
              'description': ['说明', '记录说明'],
              'defaultValue': ['初值', '初始值', 'initialValue'],
              'updateRule': ['更新规则', 'rule'],
            },
            itemPath);
        for (final key in [
          'id',
          'label',
          'description',
          'defaultValue',
          'updateRule'
        ]) {
          item[key] = _text(item[key], '$itemPath.$key');
        }
        item['type'] ??= 'string';
        if (item['type'] is String) {
          item['type'] = (item['type'] as String).trim().toLowerCase();
        }
        if (item['type'] == 'integer') item['type'] = 'int';
        if (!const ['string', 'int', 'enum'].contains(item['type'])) {
          _error('$itemPath.type',
              '支持 "string"、"int"、"enum"，实际是 ${jsonEncode(item['type'])}。');
        }
        final options = item['enum'];
        if (item['type'] == 'enum' &&
            (options == null || options is List && options.isEmpty)) {
          _error('$itemPath.enum', 'enum 类型必须提供非空选项数组。');
        }
        if (item['type'] == 'int') {
          if (options is List && options.isNotEmpty) {
            _error('$itemPath.enum', 'int 类型不能同时设置 enum 选项。');
          }
          try {
            item['defaultValue'] =
                StateDefinition(id: item['id'] as String, name: '', type: 'int')
                    .readValue(item['defaultValue']);
          } on FormatException catch (e) {
            _error('$itemPath.defaultValue', e.message);
          }
        }
        if (options != null && options is! List) {
          _error('$itemPath.enum',
              '需要文本数组，例如 ["清晨", "下午", "深夜"]，实际是 ${jsonEncode(options)}。');
        } else if (options is List) {
          final seen = <String>{};
          for (var j = 0; j < options.length; j++) {
            final option = options[j];
            if (option is! String || option.trim().isEmpty) {
              _error(
                  '$itemPath.enum[$j]', '选项必须是非空文本，实际是 ${jsonEncode(option)}。');
            } else if (!seen.add(option)) {
              _error('$itemPath.enum[$j]', '选项 ${jsonEncode(option)} 重复。');
            }
          }
          if (options.isNotEmpty &&
              item['defaultValue'] != '' &&
              !options.contains(item['defaultValue'])) {
            _error('$itemPath.defaultValue',
                '实际值 ${jsonEncode(item['defaultValue'])} 不在 enum 中；可选值：${jsonEncode(options)}。');
          }
        }
        if (item['id'] == '' && item['label'] != '') {
          item['id'] = item['label'];
          _note('$itemPath.id', '未提供 ID，已使用名称作为 ID。');
        }
        if (item['label'] == '') _error('$itemPath.label', '状态名称不能为空。');
        if (item['id'] == '') _error('$itemPath.id', '状态 ID 不能为空。');
        if (!ids.add(item['id'] as String)) {
          _error('$itemPath.id', '状态 ID “${item['id']}”重复。');
        }
        if (!names.add(item['label'] as String)) {
          _error('$itemPath.label', '状态名称“${item['label']}”重复。');
        }
        items.add(item);
      }
      // Exact display-name mapping is allowed; never fuzzy-match state values/IDs.
      for (final key in values.keys.toList()) {
        if (ids.contains(key)) continue;
        final matches = items.where((item) => item['label'] == key).toList();
        if (matches.length == 1) {
          final id = matches.single['id'] as String;
          if (values.containsKey(id) && values[id] != values[key]) {
            _error('$path.values.$key', '与 ID “$id”的当前值冲突。');
          } else {
            values[id] = values[key]!;
            values.remove(key);
            _note('$path.values.$key', '已按状态名称匹配到 ID “$id”。');
          }
        } else {
          _error('$path.values.$key',
              '没有对应的状态定义，请在 definitions 中添加该 ID 或修正当前值的键名。');
        }
      }
      for (final item in items) {
        final id = item['id'] as String;
        if (item['type'] == 'int' && values.containsKey(id)) {
          try {
            values[id] = StateDefinition(id: id, name: '', type: 'int')
                .readValue(values[id]);
          } on FormatException catch (e) {
            _error('$path.values.$id', e.message);
          }
        }
        final options = item['enum'];
        if (options is List &&
            options.isNotEmpty &&
            values.containsKey(id) &&
            values[id] != '' &&
            !options.contains(values[id])) {
          _error('$path.values.$id',
              '实际值 ${jsonEncode(values[id])} 不在 enum 中；可选值：${jsonEncode(options)}。');
        }
      }
      json['definitions'] = items;
    }
    json['values'] = values;
    return json;
  }

  String _type(dynamic value) => value is List
      ? '数组'
      : value is Map
          ? '对象'
          : value == null
              ? 'null'
              : '数字或布尔值';
  void _note(String path, String message) =>
      _issues.add(ContactImportIssue(path, message));
  void _error(String path, String message, {int? offset}) => _issues
      .add(ContactImportIssue(path, message, isError: true, offset: offset));
}
