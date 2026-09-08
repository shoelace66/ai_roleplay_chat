import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_chat_demo/app.dart';
import 'package:flutter_chat_demo/core/data/models/provider_settings.dart';
import 'package:flutter_chat_demo/core/presentation/app_theme.dart';
import 'package:flutter_chat_demo/features/chat/data/models/contact.dart';
import 'package:flutter_chat_demo/features/chat/data/models/message.dart';
import 'package:flutter_chat_demo/features/chat/domain/providers/chat_provider.dart';
import 'package:flutter_chat_demo/features/chat/domain/repositories/chat_persistence.dart';
import 'package:flutter_chat_demo/features/chat/presentation/pages/contact_profile_page.dart';
import 'package:flutter_chat_demo/features/chat/presentation/widgets/contact_avatar.dart';

class ProfileStore implements ChatPersistence {
  ProfileStore(this.snapshot);
  ChatSnapshot snapshot;
  bool fail = false;
  final metadata = <String, String>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<ChatSnapshot> readSnapshot() async => snapshot;
  @override
  Future<void> replaceSnapshot(ChatSnapshot value) async {
    snapshot = value;
  }

  @override
  Future<void> saveConversation(
      {required Contact contact,
      required List<Message> messages,
      Map<String, String> metadataUpdates = const {}}) async {
    if (fail) throw StateError('测试写入失败');
    snapshot = ChatSnapshot(contacts: [
      contact.deepCopy()
    ], messagesByContact: {
      contact.id: [...messages]
    });
    metadata.addAll(metadataUpdates);
  }

  @override
  Future<void> deleteConversation(String contactId) async {}
  @override
  Future<String?> readMetadata(String key) async => metadata[key];
  @override
  Future<void> writeMetadata(String key, String value) async {
    metadata[key] = value;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatProvider provider;
  late ProfileStore store;
  final boundaryKey = GlobalKey();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final contact = Contact(
        id: 'lin',
        name: '林夏',
        avatar: '🌿',
        createdAt: DateTime(2026, 9, 8),
        fixedInput: '一位喜欢旅行与记录生活的摄影师。',
        personality: ['温柔\n但有自己的原则', '好奇'],
        worldKnowledge: WorldKnowledgeBucket(['雨城的电车在午夜停运']),
        belongings: ['相机', '蓝色车票'],
        currentStates: {'位置': '雨城 · 电车站'});
    store = ProfileStore(ChatSnapshot(contacts: [
      contact
    ], messagesByContact: {
      'lin': [
        Message(
            id: 'u1',
            role: MessageRole.user,
            content: '雨停了，我们去河边走走吧。',
            createdAt: DateTime(2026, 9, 8, 16, 20)),
        Message(
            id: 'a1',
            role: MessageRole.assistant,
            content:
                '林夏收起伞，望向街角透出的夕阳。\n\n“好啊。这个时间的河面，应该很漂亮。”\n\n她轻轻拍了拍挂在胸前的相机，朝你伸出手。',
            createdAt: DateTime(2026, 9, 8, 16, 21)),
      ]
    }));
    provider = ChatProvider(persistence: store);
    await provider.initialize();
  });
  tearDown(() => provider.dispose());

  Future<void> phone(WidgetTester tester,
      {double width = 390,
      double height = 844,
      bool dark = false,
      double scale = 1}) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.platformBrightnessTestValue =
        dark ? Brightness.dark : Brightness.light;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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
                ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
              .load();
          final emoji = File('C:/Windows/Fonts/seguiemj.ttf');
          if (await emoji.exists()) {
            await (FontLoader('Segoe UI Emoji')
                  ..addFont(Future.value(
                      ByteData.sublistView(await emoji.readAsBytes()))))
                .load();
          }
        }
      });
    }
    await tester.pumpWidget(RepaintBoundary(
        key: boundaryKey, child: ChatApp(chatProvider: provider)));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_UI')) return;
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('reports/ui-v2.5.2').create(recursive: true);
      await File('reports/ui-v2.5.2/$name.png')
          .writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [
    const Size(320, 568),
    const Size(412, 915),
    const Size(640, 360),
    const Size(844, 390)
  ]) {
    testWidgets('聊天适配 $size 和大字体键盘', (tester) async {
      await phone(tester, width: size.width, height: size.height, scale: 1.3);
      expect(tester.takeException(), isNull);
      await capture(
          tester, 'chat-${size.width.toInt()}x${size.height.toInt()}');
      tester.view.viewInsets =
          FakeViewPadding(bottom: size.height < 500 ? 120 : 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(
          find.byKey(const ValueKey('message-composer-input')),
          '第一行\n第二行\n第三行\n第四行\n第五行\n第六行');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final action =
          tester.getRect(find.byKey(const ValueKey('message-composer-action')));
      expect(action.bottom,
          lessThanOrEqualTo(size.height - tester.view.viewInsets.bottom));
      FocusManager.instance.primaryFocus?.unfocus();
      tester.view.resetViewInsets();
      tester.view.padding = size.height < 500
          ? const FakeViewPadding(left: 32, right: 32, bottom: 16)
          : const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.resetPadding);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('打开对象列表'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(ContactAvatar).last);
      await tester.pumpAndSettle();
      expect(find.text('角色资料'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final tab in ['状态', '记忆']) {
        await tester.tap(find.text(tab));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('模型入口收进更多菜单，底部选择面板可切换模型', (tester) async {
    await provider.saveProviderSettings(const ProviderSettings(
      llm: LlmProfile(presetId: 'custom', model: '正文模型 A'),
      fallbackLlmProfiles: [LlmProfile(presetId: 'custom', model: '正文模型 B')],
    ));
    await phone(tester, dark: true);
    expect(find.byIcon(Icons.hub_outlined), findsNothing);
    expect(find.byTooltip('API 提供商'), findsOneWidget);
    await tester.tap(find.byTooltip('聊天操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('切换模型'));
    await tester.pumpAndSettle();
    expect(find.text('正文模型 A'), findsOneWidget);
    expect(find.text('正文模型 B'), findsOneWidget);
    await capture(tester, 'model-picker-dark');
    await tester.tap(find.text('正文模型 B'));
    await tester.pumpAndSettle();
    expect(provider.providerSettings.llm.model, '正文模型 B');
    expect(find.text('切换模型'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机顶部和消息头像可编辑资料，改名与知识保存后显示', (tester) async {
    await phone(tester);
    await capture(tester, 'chat-light');
    await tester.tap(find.byKey(const ValueKey('contact-header')));
    await tester.pumpAndSettle();
    expect(find.text('角色资料'), findsOneWidget);
    await capture(tester, 'profile-light');
    await tester.enterText(
        find.byKey(const ValueKey('profile-name')), '林夏 · 旅人');
    await tester.tap(find.text('记忆'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('profile-worldKnowledge')), '电车已经恢复运营');
    await tester.tap(find.byKey(const ValueKey('save-contact-profile')));
    await tester.pumpAndSettle();
    expect(provider.selectedContact!.name, '林夏 · 旅人');
    expect(provider.selectedContact!.personality, ['温柔\n但有自己的原则', '好奇']);
    expect(provider.selectedContact!.worldKnowledge.items, ['电车已经恢复运营']);
    expect(provider.messages.length, 2);
    final avatar = find.byType(ContactAvatar).last;
    await tester.tap(avatar);
    await tester.pumpAndSettle();
    expect(find.text('角色资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机侧栏头像打开资料，取消修改保留原值', (tester) async {
    await phone(tester);
    await tester.tap(find.byTooltip('打开对象列表'));
    await tester.pumpAndSettle();
    await capture(tester, 'sidebar-light');
    await tester.tap(find.byType(ContactAvatar).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('profile-name')), '未保存');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.text('角色资料'), findsNothing);
    expect(provider.selectedContact!.name, '林夏');
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保持编辑草稿，重试可保存照片', (tester) async {
    const photo =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB1sAAAAASUVORK5CYII=';
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: ContactProfilePage(
            provider: provider,
            contact: provider.selectedContact!,
            pickAvatar: () async => photo)));
    await tester.tap(find.text('选择照片'));
    await tester.pumpAndSettle();
    store.fail = true;
    await tester.tap(find.byKey(const ValueKey('save-contact-profile')));
    await tester.pumpAndSettle();
    expect(provider.selectedContact!.avatar, '🌿');
    expect(find.textContaining('资料保存失败'), findsOneWidget);
    store.fail = false;
    await tester.tap(find.byKey(const ValueKey('save-contact-profile')));
    await tester.pumpAndSettle();
    expect(store.snapshot.contacts.single.avatar, photo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色和窄屏大字体不溢出', (tester) async {
    await phone(tester, dark: true);
    await capture(tester, 'chat-dark');
    await tester.tap(find.byKey(const ValueKey('contact-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('状态'));
    await tester.pumpAndSettle();
    await capture(tester, 'state-dark');
    await tester.tap(find.text('位置'));
    await tester.pumpAndSettle();
    final current = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '当前值（留空表示清空）');
    await tester.ensureVisible(current);
    await tester.enterText(current, '河边');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 800);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('save-contact-profile')));
    await tester.pumpAndSettle();
    expect(provider.selectedContact!.currentStates['位置'], '河边');
  });
}
