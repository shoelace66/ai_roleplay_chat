import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/continuity_state_machine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const machine = ContinuityStateMachine();
  final initial = ContinuityState(revision: 4, definitions: const [
    StateDefinition(
        id: 'a', name: '案件线索', initialValue: '未发现', updateRule: '仅记录确认的证据'),
    StateDefinition(id: 'b', name: '嫌疑人证词', initialValue: ''),
  ], values: {
    'a': '门锁有划痕',
    'b': '我没去过'
  });
  Map<String, dynamic> change(String key, dynamic from, dynamic to) =>
      {'key': key, 'from': from, 'to': to};
  ContinuityState apply(List<dynamic> changes, {int revision = 4}) =>
      machine.apply(
          current: initial,
          transition: {'baseRevision': revision, 'changes': changes});

  test('省略保留、显式空文本清空；原状态不可变', () {
    final next = apply([change('b', '我没去过', '')]);
    expect(next.values, {'a': '门锁有划痕', 'b': ''});
    expect(next.revision, 5);
    expect(initial.values['b'], '我没去过');
    expect(() => next.values.clear(), throwsUnsupportedError);
    expect(apply([]), same(initial));
  });
  test('版本、旧值、归属、重复和格式整批校验', () {
    expect(() => apply([], revision: 3), throwsFormatException);
    for (final invalid in [
      change('unknown', '', '新值'),
      change('a', '不匹配', '新值'),
      change('a', null, '新值'),
      change('a', '门锁有划痕', null),
      change('a', '门锁有划痕', 42),
      {'key': 'a', 'to': '新值'}
    ]) {
      expect(() => apply([change('b', '我没去过', ''), invalid]),
          throwsFormatException);
    }
    expect(() => apply([change('b', '我没去过', ''), change('b', '我没去过', '')]),
        throwsFormatException);
    expect(initial.revision, 4);
  });
  test('模型不能创建字段；自然语言规则不冒充本地语义验证', () {
    expect(
        () =>
            machine.apply(current: const ContinuityState.empty(), transition: {
              'baseRevision': 0,
              'changes': [change('scene/location', '', '车站')]
            }),
        throwsFormatException);
    expect(
        apply([change('a', '门锁有划痕', '长文本' * 1000)]).values['a'], '长文本' * 1000);
  });
  test('改名和排序保留稳定ID；删除后反序列化不复活', () {
    final state = ContinuityState(
        revision: 5,
        definitions: const [
          StateDefinition(id: 'b', name: '证人叙述'),
          StateDefinition(id: 'a', name: '证据')
        ],
        values: initial.values);
    expect(ContinuityState.fromJson(state.toJson()).byName,
        {'证人叙述': '我没去过', '证据': '门锁有划痕'});
    final contact = Contact(
        id: 'c',
        name: '侦探故事',
        avatar: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1),
        continuity: state);
    final deleted = contact.copyWith(continuity: const ContinuityState.empty());
    expect(Contact.fromJson(deleted.toJson()).continuity.definitions, isEmpty);
  });
  test('旧 currentStates 与固定路径状态无损迁为普通自定义字段', () {
    final contact = Contact.fromJson({
      'id': 'c',
      'name': '旧故事',
      'currentStates': {'任意旧状态': '', '心情': '平静'},
      'continuity': {
        'revision': 3,
        'values': {'scene/location': '车站', 'actor/甲/phase': 'completed'}
      }
    });
    expect(contact.continuity.byName, {
      'scene/location': '车站',
      'actor/甲/phase': 'completed',
      '任意旧状态': '',
      '心情': '平静'
    });
    final next = machine.apply(current: contact.continuity, transition: {
      'baseRevision': 3,
      'changes': [change('actor/甲/phase', 'completed', '自由描述')]
    });
    expect(next.values['actor/甲/phase'], '自由描述');
    expect(Contact.fromJson(contact.toJson()).toJson(), contact.toJson());
  });
}
