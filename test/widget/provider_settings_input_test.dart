import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/core/presentation/pages/provider_settings_page.dart';
import 'package:flutter_chat_demo/app.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';

Finder field(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label);

EditableText editor(WidgetTester tester, String label) =>
    tester.widget<EditableText>(
        find.descendant(of: field(label), matching: find.byType(EditableText)));

void main() {
  testWidgets('手机聊天页的 API 提供商按钮可直接打开设置并唤起输入连接', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final provider = ChatProvider();
    addTearDown(provider.dispose);
    await tester.pumpWidget(ChatApp(chatProvider: provider));
    await tester.pumpAndSettle();
    final directButton = find.byTooltip('API 提供商');
    expect(directButton, findsOneWidget);
    await tester.tap(directButton);
    await tester.pumpAndSettle();
    expect(find.text('API 提供商'), findsOneWidget);
    await tester.tap(field('API Key'));
    await tester.pump();
    expect(editor(tester, 'API Key').focusNode.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    tester.testTextInput.enterText('mock-mobile-key');
    await tester.pump();
    expect(editor(tester, 'API Key').controller.text, 'mock-mobile-key');
    expect(tester.takeException(), isNull);
  });

  testWidgets('主 LLM 逐字输入不丢焦点，保留光标、组合文本与密钥显隐', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ProviderSettingsPage()));
    await tester.tap(field('API Key'));
    await tester.pump();
    final controller = editor(tester, 'API Key').controller;
    for (final value in ['s', 'sk', 'sk-', 'sk-test-only']) {
      tester.testTextInput.updateEditingValue(TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length)));
      await tester.pump();
      expect(editor(tester, 'API Key').focusNode.hasFocus, isTrue);
      expect(editor(tester, 'API Key').controller, same(controller));
      expect(tester.testTextInput.hasAnyClients, isTrue);
    }
    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pump();
    await tester.tap(field('API Key'));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
      text: 'sk-test-only',
      selection: TextSelection.collapsed(offset: 3),
      composing: TextRange(start: 3, end: 7),
    ));
    await tester.pump();
    expect(editor(tester, 'API Key').controller.selection.baseOffset, 3);
    expect(editor(tester, 'API Key').controller.value.composing,
        const TextRange(start: 3, end: 7));
    expect(editor(tester, 'API Key').obscureText, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('切换 Profile 显示正确字段，编辑保存后重新打开仍一致', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var settings = const ProviderSettings(
      llm: LlmProfile(
          presetId: 'custom',
          model: 'model-a',
          apiKey: 'mock-a',
          baseUrl: 'https://a.invalid/v1'),
      fallbackLlmProfiles: [
        LlmProfile(
            presetId: 'custom',
            model: 'model-b',
            apiKey: 'mock-b',
            baseUrl: 'https://b.invalid/v1')
      ],
    );
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        final saved = await Navigator.of(context)
                            .push<ProviderSettings>(MaterialPageRoute(
                                builder: (_) =>
                                    ProviderSettingsPage(initial: settings)));
                        if (saved != null) settings = saved;
                      },
                      child: const Text('打开设置')),
                ))));
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('custom / model-b'));
    await tester.pumpAndSettle();
    expect(editor(tester, 'API Key').controller.text, 'mock-b');
    expect(editor(tester, 'Base URL').controller.text, 'https://b.invalid/v1');
    await tester.enterText(field('API Key'), 'mock-b-edited');
    await tester.pump();
    await tester.tap(find.text('custom / model-a'));
    await tester.pumpAndSettle();
    expect(editor(tester, 'API Key').controller.text, 'mock-a');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(settings.fallbackLlmProfiles.single.apiKey, 'mock-b-edited');
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('custom / model-b'));
    await tester.pumpAndSettle();
    expect(editor(tester, 'API Key').controller.text, 'mock-b-edited');
    expect(tester.takeException(), isNull);
  });

  testWidgets('召回、生图和 TTS 配置输入保持焦点', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProviderSettingsPage()));
    for (final tab in ['召回', '生图', 'TTS']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      if (tab == '召回') {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
      }
      final label = tab == '生图'
          ? 'API Key（部分服务免 key）'
          : tab == 'TTS'
              ? 'API Key（edge_tts 留空）'
              : 'API Key';
      await tester.tap(field(label));
      await tester.pump();
      for (final value in ['m', 'mock-key']) {
        tester.testTextInput.updateEditingValue(TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length)));
        await tester.pump();
        expect(editor(tester, label).focusNode.hasFocus, isTrue);
        expect(editor(tester, label).controller.text, value);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('每个 LLM API Profile 显示独立输出上限和可选 JSON 模式', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProviderSettingsPage()));

    await tester.scrollUntilVisible(
      find.text('输出上限（max_tokens）'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('输出上限（max_tokens）'), findsOneWidget);
    expect(find.textContaining('当前 API Profile 单次响应'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('JSON 响应模式'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('JSON 响应模式'));
    await tester.pump();
    final tile = tester.widget<SwitchListTile>(
      find.ancestor(
        of: find.text('JSON 响应模式'),
        matching: find.byType(SwitchListTile),
      ),
    );
    expect(tile.value, isTrue);
  });
}
