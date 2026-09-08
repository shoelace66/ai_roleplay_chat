import 'dart:math';
import 'package:flutter_chat_demo/features/chat/domain/services/reversible_json_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const delta = ReversibleJsonDelta();
  test('列表仅保存变动中段，递归映射区分不存在与null', () {
    final before = {
      'queue': [1, 2, 3, 4],
      'map': {'a': null, 'b': '旧值'}
    };
    final after = {
      'queue': [1, 9, 3, 4],
      'map': {'b': '新值', 'c': null}
    };
    final changes = delta.between(before, after);
    expect(changes.first, {
      'path': ['queue'],
      'index': 1,
      'before': [2],
      'after': [9]
    });
    expect(delta.apply(before, changes), after);
    expect(delta.apply(after, changes, reverse: true), before);
    expect(
        () => delta.apply({
              'queue': [1, 7, 3, 4],
              'map': before['map']
            }, changes),
        throwsStateError);
  });
  test('1000组嵌套映射和列表变化均可正反恢复', () {
    final rng = Random(482);
    dynamic random(int depth) {
      if (depth == 0) {
        return [null, '', rng.nextInt(9), true, '文本'][rng.nextInt(5)];
      }
      return rng.nextBool()
          ? [for (var i = 0; i < rng.nextInt(6); i++) random(depth - 1)]
          : {for (var i = 0; i < rng.nextInt(6); i++) 'k$i': random(depth - 1)};
    }

    for (var i = 0; i < 1000; i++) {
      final a = random(3), b = random(3);
      final changes = delta.between(a, b);
      expect(delta.apply(a, changes), b);
      expect(delta.apply(b, changes, reverse: true), a);
    }
  });
}
