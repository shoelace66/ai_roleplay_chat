import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/deepseek_long_context_eval.dart' as evaluation;

void main() {
  test('DeepSeek 长对话一致性与缓存命中评测', () async {
    if ((Platform.environment['DEEPSEEK_API_KEY'] ?? '').trim().isEmpty) {
      return;
    }
    await evaluation.runEvaluation();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
