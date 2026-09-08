import 'package:flutter_chat_demo/features/chat/domain/services/contact_import_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = ContactImportParser();

  test('显式空配置优先于兼容旧值，旧固定路径与旧状态一起迁移', () {
    final empty = parser.parse(
        '{"name":"故事","continuity":{"revision":3,"definitions":[],"values":{}},"currentStates":{"已删除":"不能复活"}}')!;
    expect(empty.continuity.definitions, isEmpty);
    expect(empty.currentStates, isEmpty);
    final legacy = parser.parse(
        '{"name":"旧故事","continuity":{"revision":2,"values":{"scene/location":"车站"}},"currentStates":{"线索":"脚印"}}')!;
    expect(legacy.continuity.byName, {'scene/location': '车站', '线索': '脚印'});
  });

  test('拒绝非法 JSON、非对象和缺少名称的数据', () {
    expect(parser.parse('{broken'), isNull);
    expect(parser.parse('[]'), isNull);
    expect(parser.parse('{"avatar":"A"}'), isNull);
  });

  test('解析完整字段并规范化状态与设定', () {
    final result = parser.parse('''
{
  "id": " role-1 ",
  "name": " 林夏 ",
  "personalInfo": ["侦探", ""],
  "currentStates": {" 信任 ": " 中 "},
  "settings": [
    {"key": " 城市 ", "value": " 雨城 ", "relate": ["雨", "车站"]},
    {"key": "无效", "value": ""}
  ]
}
''');

    expect(result, isNotNull);
    expect(result!.requestedId, 'role-1');
    expect(result.name, '林夏');
    expect(result.personalInfo, <String>['侦探']);
    expect(result.currentStates, <String, String>{'信任': '中'});
    expect(result.settings.single, <String, dynamic>{
      'key': '城市',
      'value': '雨城',
      'relate': <String>['雨', '车站'],
    });
  });

  test('JSON 非空字段优先，否则使用表单后备字段', () {
    final result = parser.parse(
      '{"name":"JSON 名称","avatar":"","currentStates":{}}',
      fallback: const ContactImportFallback(
        name: '后备名称',
        avatar: '后备头像',
        fixedInput: '后备设定',
        currentStates: <String, String>{'关系': '陌生'},
        voice: 'voice-1',
      ),
    );

    expect(result?.name, 'JSON 名称');
    expect(result?.avatar, '后备头像');
    expect(result?.fixedInput, '后备设定');
    expect(result?.currentStates, <String, String>{'关系': '陌生'});
    expect(result?.voice, 'voice-1');
  });
}
