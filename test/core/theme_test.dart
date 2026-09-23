import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_registry.dart';

void main() {
  group('theme tokens', () {
    testWidgets('every theme exposes AppColorTokens to widgets', (
      WidgetTester tester,
    ) async {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
        AppTheme.highContrast(),
      ]) {
        AppColorTokens? seen;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Builder(
              builder: (BuildContext context) {
                seen = Theme.of(context).extension<AppColorTokens>();
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        expect(
          seen,
          isNotNull,
          reason: 'widgets read every colour through this extension, so a '
              'theme without it would crash at the first token lookup',
        );
      }
    });

    test('an accent override reaches the tokens', () {
      const Color pink = Color(0xFFFF00AA);
      final ThemeData theme = AppTheme.dark(accentOverride: pink);
      expect(theme.extension<AppColorTokens>()!.accent, pink);
      expect(theme.colorScheme.primary, pink);
    });

    test('high contrast really is higher contrast than the default dark', () {
      final AppColorTokens normal =
          AppTheme.dark().extension<AppColorTokens>()!;
      final AppColorTokens high =
          AppTheme.highContrast().extension<AppColorTokens>()!;

      double contrast(Color fg, Color bg) {
        double luminance(Color c) => c.computeLuminance();
        final double a = luminance(fg) + 0.05;
        final double b = luminance(bg) + 0.05;
        return a > b ? a / b : b / a;
      }

      expect(
        contrast(high.textPrimary, high.background),
        greaterThan(contrast(normal.textPrimary, normal.background)),
      );
    });

    test('body text meets the WCAG AA 4.5:1 ratio in every theme', () {
      for (final ThemeData theme in <ThemeData>[
        AppTheme.dark(),
        AppTheme.light(),
        AppTheme.highContrast(),
      ]) {
        final AppColorTokens t = theme.extension<AppColorTokens>()!;
        final double a = t.textPrimary.computeLuminance() + 0.05;
        final double b = t.background.computeLuminance() + 0.05;
        final double ratio = a > b ? a / b : b / a;
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'primary text must be readable without straining',
        );
      }
    });
  });

  group('editor theme registry', () {
    test('ships at least two dark themes and one light', () {
      expect(EditorThemeRegistry.matching(isDark: true).length,
          greaterThanOrEqualTo(2));
      expect(EditorThemeRegistry.matching(isDark: false).length,
          greaterThanOrEqualTo(1));
    });

    test('an unknown id falls back instead of throwing', () {
      // A settings file naming a theme removed in a later version must not
      // stop the app from starting.
      final EditorColorTheme dark =
          EditorThemeRegistry.byId('deleted-theme', preferDark: true);
      expect(dark.isDark, isTrue);
      final EditorColorTheme light =
          EditorThemeRegistry.byId('deleted-theme', preferDark: false);
      expect(light.isDark, isFalse);
    });

    test('every theme defines the syntax scopes the app relies on', () {
      // A theme missing these would render code in undifferentiated grey.
      const List<String> required = <String>[
        'keyword',
        'string',
        'comment',
        'number',
        'type',
        'title',
        'variable',
      ];
      for (final EditorColorTheme theme in EditorThemeRegistry.all) {
        for (final String scope in required) {
          expect(
            theme.syntax.containsKey(scope),
            isTrue,
            reason: '${theme.id} is missing the "$scope" scope',
          );
        }
      }
    });

    test('theme ids are unique', () {
      final Set<String> ids =
          EditorThemeRegistry.all.map((EditorColorTheme t) => t.id).toSet();
      expect(ids.length, EditorThemeRegistry.all.length);
    });
  });
}
