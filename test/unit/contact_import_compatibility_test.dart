import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/contact_import_parser.dart';

void main() {
  const parser = ContactImportParser();
  test('代码块、注释、尾逗号、中英别名和文本列表兼容且列出调整', () {
    final result = parser.parseDetailed('''```json
{
  // 角色卡
  "角色名称": "林夏",
  "fixed_input": "你是一名侦探",
  "personailty": "冷静，观察敏锐",
  "background_story": ["出生在雨城",],
  "当前状态": {"好感度": 10},
  "settings": {"城市": "雨城"},
}
```''');
    expect(result.errorMessage, isEmpty);
    expect(result.data!.name, '林夏');
    expect(result.data!.personality, ['冷静，观察敏锐']);
    expect(result.data!.fixedInput, '你是一名侦探');
    expect(result.data!.currentStates, {'好感度': '10'});
    expect(result.data!.settings.single['key'], '城市');
    expect(result.issues.length, greaterThan(5));
    expect(parser.parse(result.normalizedJson!)!.personality,
        result.data!.personality);
  });

  test('字符串内部的 URL、注释符、逗号和转义不被替换', () {
    const text = 'https://example.invalid/a//b /*保留*/ ,} ,] "原话" \\路径\n下一行';
    final result =
        parser.parseDetailed(jsonEncode({'name': 'A', 'fixedInput': text}));
    expect(result.data!.fixedInput, text);
    expect(result.issues, isEmpty);
  });

  test('不猜测短字段，未知字段显式警告，别名冲突明确报错', () {
    final unknown = parser.parseDetailed('{"nme":"A","mystery":"不会悄悄忽略"}');
    expect(unknown.isSuccess, isFalse);
    expect(unknown.errorMessage, contains(r'$.name'));
    expect(
        unknown.issues
            .any((issue) => issue.path == r'$.mystery' && !issue.isError),
        isTrue);
    final conflict = parser.parseDetailed('{"name":"A","名称":"B"}');
    expect(conflict.isSuccess, isFalse);
    expect(conflict.errorMessage, contains('内容不同'));
    expect(parser.parseDetailed('{"name":"A","名称":"A"}').isSuccess, isTrue);
  });

  test('非法结构定位到字段和数组元素，不吞掉类型错误', () {
    final result = parser.parseDetailed(
        '{"name":"A","personality":["温柔",{"bad":true}],"currentStates":[],"settings":[42]}');
    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains(r'$.personality[1]'));
    expect(result.errorMessage, contains(r'$.currentStates'));
    expect(result.errorMessage, contains(r'$.settings[0]'));
  });

  test('字符串外兼容全半角和 Unicode 空格及全角结构标点', () {
    final result =
        parser.parseDetailed('｛　"角色　名称"　：　"林　夏"，\u00a0"性 格"：［"温柔"，"认真"］　｝');
    expect(result.errorMessage, isEmpty);
    expect(result.data!.name, '林　夏');
    expect(result.data!.personality, ['温柔', '认真']);
    expect(result.issues.any((item) => item.message.contains('Unicode 空白')),
        isTrue);
    expect(result.issues.any((item) => item.message.contains('全角大括号')), isTrue);
  });

  test('不支持的全角引号明确指出实际字符和 Unicode 编码', () {
    final result = parser.parseDetailed('｛“name”："A"｝');
    expect(result.isSuccess, isFalse);
    expect(result.errorMessage, contains('“'));
    expect(result.errorMessage, contains('U+201C'));
  });

  test('状态重复、孤立当前值、负版本和类型错误给出具体路径', () {
    final result = parser.parseDetailed('''{"name":"A","continuity":{
      "revision":-1,
      "definitions":[{"id":"a","name":"地点"},{"id":"a","name":"地点"}],
      "values":{"b":"车站"}
    }}''');
    expect(result.errorMessage, contains(r'$.continuity.revision'));
    expect(result.errorMessage, contains(r'$.continuity.definitions[1].id'));
    expect(result.errorMessage, contains(r'$.continuity.definitions[1].label'));
    expect(result.errorMessage, contains(r'$.continuity.values.b'));
    expect(parser.parseDetailed('{"name":"A","continuity":[]}').errorMessage,
        contains(r'$.continuity'));
  });

  test('不模糊修改用户状态 ID，空定义不复活旧状态', () {
    expect(
        parser
            .parseDetailed(
                '{"name":"A","continuity":{"definitions":[{"id":"place","name":"地点"}],"values":{"plcae":"车站"}}}')
            .isSuccess,
        isFalse);
    final empty = parser.parseDetailed(
        '{"name":"A","continuity":{"definitions":[],"values":{}},"currentStates":{"旧项":"不要复活"}}');
    expect(empty.data!.continuity.definitions, isEmpty);
  });
}
