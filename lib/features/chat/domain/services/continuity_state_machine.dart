import '../../data/models/continuity_state.dart';

/// 仅校验用户定义字段、版本及旧值；自然语言更新规则由提示词约束。
class ContinuityStateMachine {
  const ContinuityStateMachine();
  ContinuityState apply(
      {required ContinuityState current,
      required dynamic transition,
      String userInput = '',
      String reply = '',
      String initialContext = ''}) {
    if (transition == null) return current;
    if (transition is! Map ||
        transition['baseRevision'] is! int ||
        transition['baseRevision'] != current.revision ||
        transition['changes'] is! List) {
      throw const FormatException('状态转移格式或版本不匹配');
    }
    final next = {
      for (final d in current.definitions)
        d.id: current.values[d.id] ?? d.initialValue
    };
    final seen = <String>{};
    var changed = false;
    for (final change in transition['changes'] as List) {
      if (change is! Map ||
          change['key'] is! String ||
          !next.containsKey(change['key']) ||
          !seen.add(change['key'] as String) ||
          !change.containsKey('from') ||
          !change.containsKey('to')) {
        throw const FormatException('状态更新必须属于已定义项，并提供 from/to');
      }
      final definition =
          current.definitions.firstWhere((d) => d.id == change['key']);
      final from = definition.readValue(change['from']);
      final to = definition.readValue(change['to']);
      if (from != definition.readValue(next[change['key']])) {
        throw FormatException('状态 ${definition.id} 的 from 与当前值不匹配');
      }
      // 空字符串是明确清空；遗漏字段才表示不变。
      changed = changed || next[change['key']] != to;
      next[change['key'] as String] = to;
    }
    if (!changed) return current;
    return ContinuityState(
        revision: current.revision + 1,
        definitions: current.definitions,
        values: next);
  }
}
