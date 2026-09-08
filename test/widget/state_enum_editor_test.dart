import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/story_state_editor.dart';

void main() {
  testWidgets('编辑名称保留 enum，非法当前值提示错误后可以重试', (tester) async {
    var state = ContinuityState(revision: 1, definitions: const [
      StateDefinition(
          id: 'time',
          name: '时间',
          initialValue: '下午',
          enumValues: ['清晨', '下午', '傍晚']),
    ], values: {
      'time': '下午'
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StoryStateEditor(
                value: state, onChanged: (value) => state = value))));
    await tester.tap(find.text('时间'));
    await tester.pumpAndSettle();
    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await tester.enterText(field('名称'), '当前时间');
    await tester.ensureVisible(field('当前值（留空表示清空）'));
    await tester.enterText(field('当前值（留空表示清空）'), '午夜');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.definitions.first.name, '时间');
    expect(find.textContaining('必须属于 enum'), findsOneWidget);
    await tester.enterText(field('当前值（留空表示清空）'), '傍晚');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.definitions.first.name, '当前时间');
    expect(state.definitions.first.enumValues, ['清晨', '下午', '傍晚']);
    expect(state.byName['当前时间'], '傍晚');
    expect(tester.takeException(), isNull);
  });
}
