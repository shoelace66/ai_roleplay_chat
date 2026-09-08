import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/features/chat/domain/services/contact_import_parser.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/contact_json_preview_dialog.dart';

void main() {
  Future<void> open(
      WidgetTester tester, String source, ValueChanged<String?> onResult,
      {ContactImportFallback fallback = const ContactImportFallback()}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async => onResult(await showDialog<String>(
                          context: context,
                          builder: (_) => ContactJsonPreviewDialog(
                              title: '创建角色 JSON',
                              source: source,
                              fallback: fallback))),
                      child: const Text('打开')),
                ))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('格式不匹配显示具体字段，保留原文并允许修正后创建', (tester) async {
    String? result;
    const source = '{"name":"A","personality":[{"wrong":true}]}';
    await open(tester, source, (value) => result = value);
    expect(find.textContaining(r'$.personality[0]'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('contact-json-create')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    final input = find.byKey(const ValueKey('contact-json-preview-input'));
    expect(tester.widget<TextField>(input).controller!.text, source);
    await tester.enterText(input, '{"name":"A","personality":["温柔"]}');
    await tester.tap(find.byKey(const ValueKey('contact-json-create')));
    await tester.pumpAndSettle();
    expect(const ContactImportParser().parse(result!)!.personality, ['温柔']);
  });

  testWidgets('模糊匹配和未知字段先展示，确认后才创建', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    String? result;
    await open(
        tester, '{"角色名称":"林夏","extra":"未知内容"}', (value) => result = value);
    expect(find.textContaining('已匹配为 name'), findsOneWidget);
    expect(find.textContaining('未识别的字段'), findsOneWidget);
    final create = find.byKey(const ValueKey('contact-json-create'));
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.ensureVisible(
        find.byKey(const ValueKey('contact-json-confirm-adjustments')));
    await tester
        .tap(find.byKey(const ValueKey('contact-json-confirm-adjustments')));
    await tester.pump();
    await tester.tap(create);
    await tester.pumpAndSettle();
    expect(const ContactImportParser().parse(result!)!.name, '林夏');
  });

  testWidgets('编辑后重新验证新警告，不能沿用旧确认；可使用表单后备名称', (tester) async {
    String? result;
    await open(tester, '{"name":"A"}', (value) => result = value,
        fallback: const ContactImportFallback(name: '表单名称'));
    await tester.enterText(
        find.byKey(const ValueKey('contact-json-preview-input')),
        '{"personality":"温柔"}');
    await tester.tap(find.byKey(const ValueKey('contact-json-create')));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('已识别：表单名称'), findsOneWidget);
    expect(find.byKey(const ValueKey('contact-json-confirm-adjustments')),
        findsOneWidget);
  });

  testWidgets('手机尺寸与键盘弹出时诊断和编辑器可滚动，无布局溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await open(
        tester,
        '{"name":"A","continuity":{"definitions":[{"name":"地点"}],"values":{"错误ID":"车站"}}}',
        (_) {});
    await tester.tap(find.byKey(const ValueKey('contact-json-preview-input')));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('contact-json-create')), findsOneWidget);
  });
}
