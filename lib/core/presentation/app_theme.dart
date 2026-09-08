import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared mobile surfaces, spacing, controls and navigation motion.
abstract final class AppTheme {
  static const fontFallback = [
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Segoe UI Emoji'
  ];
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF708A98),
      brightness: brightness,
      surface: dark ? const Color(0xFF2C3136) : const Color(0xFFFCFDFD),
      primary: dark ? const Color(0xFFA5BDC8) : const Color(0xFF526F7D),
      onPrimary: dark ? const Color(0xFF223039) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF37474F) : const Color(0xFFE7EEF1),
      onPrimaryContainer:
          dark ? const Color(0xFFD0DCE0) : const Color(0xFF415862),
      secondaryContainer:
          dark ? const Color(0xFF37474F) : const Color(0xFFE7EEF1),
      onSecondaryContainer:
          dark ? const Color(0xFFD0DCE0) : const Color(0xFF415862),
      onSurface: dark ? const Color(0xFFDDE2E5) : const Color(0xFF39434A),
      onSurfaceVariant:
          dark ? const Color(0xFFAFBAC1) : const Color(0xFF64717A),
    );
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF252A2F) : const Color(0xFFF4F6F6),
      fontFamilyFallback: fontFallback,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor:
            dark ? const Color(0xFF252A2F) : const Color(0xFFF4F6F6),
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 64,
        centerTitle: false,
        titleTextStyle: TextStyle(
            fontFamilyFallback: fontFallback,
            color: scheme.onSurface,
            fontSize: 20,
            fontWeight: FontWeight.w600),
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: shape,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF333A40) : const Color(0xFFF0F3F4),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.primary, width: 1.5)),
        errorBorder:
            border.copyWith(borderSide: BorderSide(color: scheme.error)),
        focusedErrorBorder: border.copyWith(
            borderSide: BorderSide(color: scheme.error, width: 1.5)),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: fontFallback),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
      )),
      textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: const StadiumBorder(),
      )),
      listTileTheme: ListTileThemeData(
          shape: shape,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 6)),
      dialogTheme: DialogThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: scheme.surface),
      bottomSheetTheme: BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: scheme.surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      snackBarTheme:
          SnackBarThemeData(behavior: SnackBarBehavior.floating, shape: shape),
      dividerTheme: DividerThemeData(
          color: scheme.outlineVariant.withValues(alpha: .35),
          space: 1,
          thickness: .5),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: scheme.onPrimaryContainer,
        unselectedLabelColor: scheme.onSurfaceVariant,
        indicator: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
        labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamilyFallback: fontFallback),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }
}
