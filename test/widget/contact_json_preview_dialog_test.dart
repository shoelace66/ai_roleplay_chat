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
}
