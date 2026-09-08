import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/presentation/app_theme.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/contact_editor_dialog.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(360, 640),
    const Size(390, 844),
    const Size(412, 915),
    const Size(540, 720),
    const Size(640, 360),
    const Size(844, 390),
  ]) {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('创建窗口 $size 字体 $scale 完整显示并在键盘上方提交', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        if (const bool.fromEnvironment('CAPTURE_UI')) {
          await tester.runAsync(() async {
            final font = File('C:/Windows/Fonts/msyh.ttc');
            if (await font.exists()) {
              final bytes = ByteData.sublistView(await font.readAsBytes());
              for (final family in ['Microsoft YaHei', 'Roboto', 'Ahem']) {
                await (FontLoader(family)..addFont(Future.value(bytes))).load();
              }
              await (FontLoader('MaterialIcons')
                    ..addFont(
                        rootBundle.load('fonts/MaterialIcons-Regular.otf')))
                  .load();
            }
          });
        }
        final boundary = GlobalKey();
        ContactDraft? result;
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.build(Brightness.light),
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                          onPressed: () async {
                            result = await showDialog<ContactDraft>(
                                context: context,
                                builder: (_) => const ContactEditorDialog());
                          },
                          child: const Text('打开'),
                        ))),
          ),
        ));
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        final mode = find.text('使用自然语言创建');
        await tester.ensureVisible(mode);
        final paragraph = tester.renderObject<RenderParagraph>(mode);
        expect(paragraph.didExceedMaxLines, isFalse);
        final rect = tester.getRect(mode);
        expect(rect.left, greaterThanOrEqualTo(12));
        expect(rect.right, lessThanOrEqualTo(size.width - 12));
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_UI') && scale == 1.3) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('reports/ui-v2.5.2').create(recursive: true);
            await File(
                    'reports/ui-v2.5.2/create-${size.width.toInt()}x${size.height.toInt()}.png')
                .writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(mode);
        await tester.pumpAndSettle();
        final description = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '自然语言描述');
        await tester.ensureVisible(description);
        await tester.enterText(description, '一个喜欢旅行的摄影师');
        tester.view.viewInsets =
            FakeViewPadding(bottom: size.height < 500 ? 120 : 260);
        await tester.pumpAndSettle();
        await tester.ensureVisible(description);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final submit = find.widgetWithText(FilledButton, '创建');
        expect(tester.getRect(submit).bottom,
            lessThanOrEqualTo(size.height - tester.view.viewInsets.bottom));
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(result?.naturalLanguage, '一个喜欢旅行的摄影师');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
