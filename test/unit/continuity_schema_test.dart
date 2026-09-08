import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact_json_example.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/chat_backup_codec.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/contact_import_parser.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/continuity_state_machine.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/reversible_json_delta.dart';

void main() {
  const parser = ContactImportParser();
  Map<String, dynamic> example() =>
      jsonDecode(contactJsonExample) as Map<String, dynamic>;

  test('升级后旧格式的定义变更日志仍可精确回滚', () {
    final before = {
      'schemaVersion': 2,
      'revision': 1,
      'definitions': [
        {
          'id': 'place',
          'name': '位置',
          'description': '',
          'initialValue': '车站',
          'updateRule': ''
        }
      ],
      'values': {'place': '车站'},
    };
    final after = jsonDecode(jsonEncode(before)) as Map<String, dynamic>;
    after['definitions'][0]['description'] = '记录实际到达地点';
    after['revision'] = 2;
    const delta = ReversibleJsonDelta();
    final oldLog = delta.between(before, after);
    final upgraded = ContinuityState.fromJson(after).toStorageJson();
    expect(delta.apply(upgraded, oldLog, reverse: true), before);
  });

  test('完整内置示例无需兼容修正，定义选项和当前值保存后保留', () {
    final result = parser.parseDetailed(contactJsonExample);
    expect(result.issues, isEmpty);
    final state = result.data!.continuity;
    expect(state.revision, 1);
    expect(state.definitions, hasLength(6));
    expect(state.byName['关系阶段'], '熟悉');
    expect(state.definitions[3].initialValue, '初识');
    final saved = jsonDecode(jsonEncode(state.toJson()));
    expect(saved['definitions'][0]['label'], '当前时间');
    expect(saved['definitions'][0]['type'], 'string');
    expect(saved['definitions'][0]['enum'], contains('凌晨'));
    expect(saved['definitions'][0].containsKey('name'), isFalse);
    expect(ContinuityState.fromJson(saved).toJson(), state.toJson());
    expect(ContinuityState.fromJson(state.toStorageJson()).toJson(),
        state.toJson());
    const codec = ChatBackupCodec();
    final backup = codec.encode(ChatSnapshot(
      contacts: [
        Contact.fromJson({...example(), 'id': 'example'})
      ],
      messagesByContact: const {'example': []},
    ));
    expect(
        jsonDecode(backup)['contacts'][0]['continuity']['definitions'][0]
            ['label'],
        '当前时间');
    expect(codec.decode(backup).contacts.single.continuity.toJson(),
        state.toJson());
  });

  test('省略 values 使用默认值，明确空值保留为空', () {
    final json = example();
    json['continuity'].remove('values');
    var result = parser.parseDetailed(jsonEncode(json));
    expect(result.data!.continuity.byName['当前时间'], '下午');
    json['continuity']['values'] = {'time_of_day': ''};
    result = parser.parseDetailed(jsonEncode(json));
    expect(result.data!.continuity.byName['当前时间'], '');
  });

  test('旧存档 name initialValue 可读取并导出新结构，冲突字段拒绝覆盖', () {
    final state = ContinuityState.fromJson({
      'revision': 3,
      'definitions': [
        {'id': 'place', 'name': '位置', 'initialValue': '车站'}
      ],
      'values': {'place': '河边'},
    });
    expect(state.byName['位置'], '河边');
    expect(state.toJson()['definitions'][0]['defaultValue'], '车站');
    final json = example();
    json['continuity']['definitions'][0]['name'] = '冲突名称';
    final result = parser.parseDetailed(jsonEncode(json));
    expect(result.data, isNull);
    expect(result.issues.any((e) => e.isError && e.message.contains('内容不同')),
        isTrue);
  });

  test('字段别名及全角标点仍可导入 enum，不更改 ID 或选项文字', () {
    final result = parser.parseDetailed('''{
      "名称"： "林夏"， "continuity"： {
        "revision"： 1， "definitions"： [{
          "id"： "time_of_day"， "label"： "当前时间"， "type"： "string"，
          "enum"： ["清晨"， "下午"]， "defaultValue"： "下午"
        }]
      }
    }''');
    expect(result.data!.continuity.byName['当前时间'], '下午');
    expect(result.data!.continuity.definitions.first.enumValues, ['清晨', '下午']);
  });

  test('enum 错误定位到字段或数组下标，包含实际值与可选值', () {
    for (final entry in {
      'type': 'number',
      'enum': ['清晨', 42],
      'defaultValue': '午夜'
    }.entries) {
      final json = example();
      json['continuity']['definitions'][0][entry.key] = entry.value;
      final result = parser.parseDetailed(jsonEncode(json));
      expect(result.data, isNull);
      expect(
          result.issues.any((e) =>
              e.isError &&
              e.path.startsWith(r'$.continuity.definitions[0].' + entry.key)),
          isTrue);
    }
    final json = example();
    json['continuity']['values']['time_of_day'] = '午夜';
    final result = parser.parseDetailed(jsonEncode(json));
    expect(result.data, isNull);
    final issue = result.issues
        .singleWhere((e) => e.path == r'$.continuity.values.time_of_day');
    expect(issue.message, contains('午夜'));
    expect(issue.message, contains('凌晨'));
  });

  test('模型更新遵守 enum，非法值不改变状态，合法值及清空可提交', () {
    final state = parser.parse(contactJsonExample)!.continuity;
    ContinuityState apply(String to) =>
        const ContinuityStateMachine().apply(current: state, transition: {
          'baseRevision': 1,
          'changes': [
            {'key': 'time_of_day', 'from': '下午', 'to': to}
          ],
        });
    expect(() => apply('午夜'), throwsFormatException);
    expect(state.byName['当前时间'], '下午');
    expect(apply('傍晚').byName['当前时间'], '傍晚');
    expect(apply('').byName['当前时间'], '');
  });
}
