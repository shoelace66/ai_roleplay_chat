import 'package:flutter/material.dart';
import 'package:flutter_chat_demo/features/chat/data/models/continuity_state.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/story_state_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('手动创建、改名、清空、排序和删除记录项', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var state = const ContinuityState.empty();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => SingleChildScrollView(
                    child: StoryStateEditor(
                        value: state,
                        onChanged: (v) => setState(() => state = v)))))));
    Finder field(String label) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == label);
    await tester.tap(find.text('添加记录项'));
    await tester.pumpAndSettle();
    await tester.enterText(field('名称'), '航线');
    await tester.enterText(field('记录说明'), '记录目前已确认的航线');
    await tester.enterText(field('初值（可留空）'), '近海');
    await tester.enterText(field('更新规则'), '只有船长决定后才能修改');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final id = state.definitions.single.id;
    expect(state.values[id], '近海');
    expect(state.definitions.single.updateRule, '只有船长决定后才能修改');
    await tester.tap(find.text('航线'));
    await tester.pumpAndSettle();
    await tester.enterText(field('名称'), '确认航线');
    await tester.enterText(field('当前值（留空表示清空）'), '');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(state.definitions.single.id, id);
    expect(state.values[id], '');
    await tester.tap(find.text('添加记录项'));
    await tester.pumpAndSettle();
    await tester.enterText(field('名称'), '风向');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('上移').last);
    await tester.pumpAndSettle();
    expect(state.definitions.first.name, '风向');
    await tester.tap(find.byTooltip('删除记录项').last);
    await tester.pumpAndSettle();
    expect(state.values.containsKey(id), isFalse);
    expect(state.definitions.single.name, '风向');
    expect(tester.takeException(), isNull);
  });
}
