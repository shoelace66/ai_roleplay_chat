import 'package:flutter/material.dart';
import 'app_router.dart';
import 'core/presentation/app_theme.dart';
import 'features/chat/domain/providers/chat_provider.dart';

class ChatApp extends StatelessWidget {
  const ChatApp({super.key, required this.chatProvider});
  final ChatProvider chatProvider;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI 角色对话',
        theme: AppTheme.build(Brightness.light),
        darkTheme: AppTheme.build(Brightness.dark),
        themeMode: ThemeMode.system,
        themeAnimationDuration: const Duration(milliseconds: 240),
        initialRoute: AppRoutes.chat,
        onGenerateRoute: AppRouter(chatProvider).onGenerateRoute,
      );
}
