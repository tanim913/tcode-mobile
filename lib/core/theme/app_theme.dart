/// Builds [ThemeData] from a set of [AppColorTokens].
///
/// Material 3 is the base, but heavily reshaped: default M3 has large corner
/// radii, tonal elevation tints and generous padding, which reads as a consumer
/// app. A code editor should feel dense and precise, so corners are tightened,
/// elevation tint is removed, and density is compact.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/theme/app_palettes.dart';

/// Which set of app colours to use. Persisted in settings.
enum AppThemeVariant {
  system('Follow system'),
  dark('Dark'),
  light('Light'),
  highContrast('High contrast');

  const AppThemeVariant(this.label);

  final String label;
}

abstract final class AppTheme {
  /// Corner radius used throughout. Small enough to read as a tool.
  static const double radius = 6;
  static const double radiusLarge = 10;

  static ThemeData dark({Color? accentOverride}) =>
      _build(AppPalettes.dark, Brightness.dark, accentOverride);

  static ThemeData light({Color? accentOverride}) =>
      _build(AppPalettes.light, Brightness.light, accentOverride);

  static ThemeData highContrast({Color? accentOverride}) =>
      _build(AppPalettes.highContrast, Brightness.dark, accentOverride);

  static ThemeData _build(
    AppColorTokens base,
    Brightness brightness,
    Color? accentOverride,
  ) {
    // The accent is user-configurable, so it is applied on top of the palette
    // rather than baked into it.
    final AppColorTokens t =
        accentOverride == null ? base : base.copyWith(accent: accentOverride);

    final ColorScheme scheme = ColorScheme(
      brightness: brightness,
      primary: t.accent,
      onPrimary: t.onAccent,
      secondary: t.accent,
      onSecondary: t.onAccent,
      error: t.danger,
      onError: t.onAccent,
      surface: t.surface,
      onSurface: t.textPrimary,
      surfaceContainerHighest: t.surfaceRaised,
      outline: t.border,
      outlineVariant: t.borderStrong,
      scrim: t.scrim,
    );

    final TextTheme text = _textTheme(t);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: <ThemeExtension<dynamic>>[t],
      scaffoldBackgroundColor: t.background,
      canvasColor: t.background,
      dividerColor: t.border,
      splashFactory: InkSparkle.splashFactory,
      // Compact: this UI is information-dense by design.
      visualDensity: VisualDensity.compact,
      textTheme: text,

      appBarTheme: AppBarTheme(
        backgroundColor: t.surface,
        foregroundColor: t.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleMedium,
        iconTheme: IconThemeData(color: t.textSecondary, size: 20),
        actionsIconTheme: IconThemeData(color: t.textSecondary, size: 20),
      ),

      dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),

      iconTheme: IconThemeData(color: t.textSecondary, size: 20),

      listTileTheme: ListTileThemeData(
        iconColor: t.textSecondary,
        textColor: t.textPrimary,
        selectedTileColor: t.sidebarActive,
        selectedColor: t.textPrimary,
        dense: true,
        visualDensity: VisualDensity.compact,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
      ),

      // No tonal tint: M3's default surface tinting makes every raised panel a
      // slightly different shade of the accent, which fights syntax colours.
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusLarge)),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLarge)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: t.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: text.bodyMedium,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: t.surfaceRaised,
        contentTextStyle: text.bodyMedium?.copyWith(color: t.textPrimary),
        actionTextColor: t.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.background,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        hintStyle: text.bodyMedium?.copyWith(color: t.textMuted),
        border: _inputBorder(t.border),
        enabledBorder: _inputBorder(t.border),
        focusedBorder: _inputBorder(t.accent, width: 1.5),
        errorBorder: _inputBorder(t.danger),
        focusedErrorBorder: _inputBorder(t.danger, width: 1.5),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: t.accent,
          foregroundColor: t.onAccent,
          minimumSize: const Size(0, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.accent,
          minimumSize: const Size(0, 40),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.border),
          minimumSize: const Size(0, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(radius)),
          ),
          textStyle: text.labelLarge,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: t.textSecondary,
          highlightColor: t.hover,
        ),
      ),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          border: Border.all(color: t.border),
          borderRadius: const BorderRadius.all(Radius.circular(radius)),
        ),
        textStyle: text.bodySmall?.copyWith(color: t.textPrimary),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.accent,
        linearTrackColor: t.border,
        circularTrackColor: t.border,
      ),

      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll<double>(6),
        radius: const Radius.circular(3),
        thumbColor: WidgetStatePropertyAll<Color>(t.borderStrong),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? t.onAccent : t.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (Set<WidgetState> s) =>
              s.contains(WidgetState.selected) ? t.accent : t.border,
        ),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(radius)),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Interface text. Sentence case, tight line heights, no heavy weights —
  /// the UI should recede so the code is what stands out.
  static TextTheme _textTheme(AppColorTokens t) {
    return TextTheme(
      titleLarge: TextStyle(
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.4, color: t.textPrimary),
      bodyMedium: TextStyle(fontSize: 13.5, height: 1.4, color: t.textPrimary),
      bodySmall: TextStyle(fontSize: 12, height: 1.35, color: t.textSecondary),
      labelLarge: TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: t.textPrimary,
      ),
      labelMedium: TextStyle(fontSize: 12, height: 1.2, color: t.textSecondary),
      labelSmall: TextStyle(fontSize: 11, height: 1.2, color: t.textMuted),
    );
  }
}
