/// The Appearance group: app theme, editor colour themes and the accent.
///
/// Dark and light editor themes are chosen separately rather than as one
/// setting, because "follow system" means both are in use and picking one
/// would silently override the other every time the phone flipped.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_registry.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/accent_color_picker.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_entries.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_tiles.dart';

SettingsGroup buildAppearanceGroup(WidgetRef ref, AppSettings settings) {
  void set(AppSettings Function(AppSettings) change) {
    unawaited(ref.read(settingsProvider.notifier).update(change));
  }

  List<SettingChoice<String>> themeChoices({required bool isDark}) {
    return <SettingChoice<String>>[
      for (final EditorColorTheme theme
          in EditorThemeRegistry.matching(isDark: isDark))
        SettingChoice<String>(theme.id, theme.name),
    ];
  }

  return SettingsGroup(
    id: 'appearance',
    title: 'Appearance',
    description: 'App theme, editor colours and the accent colour.',
    onReset: () => ref.read(settingsProvider.notifier).update(
          (AppSettings s) => s.copyWith(
            themeVariant: AppThemeVariant.system,
            editorThemeId: EditorThemeRegistry.defaultDarkId,
            lightEditorThemeId: EditorThemeRegistry.defaultLightId,
            clearAccentColor: true,
          ),
        ),
    entries: <SettingEntry>[
      choiceEntry<AppThemeVariant>(
        id: 'appearance.themeVariant',
        title: 'App theme',
        description: 'Light, dark, high contrast, or whatever the system is '
            'set to right now.',
        keywords: const <String>[
          'dark mode',
          'light mode',
          'night',
          'contrast',
          'accessibility',
        ],
        value: settings.themeVariant,
        choices: <SettingChoice<AppThemeVariant>>[
          for (final AppThemeVariant variant in AppThemeVariant.values)
            SettingChoice<AppThemeVariant>(variant, variant.label),
        ],
        onChanged: (AppThemeVariant value) =>
            set((AppSettings s) => s.copyWith(themeVariant: value)),
      ),
      choiceEntry<String>(
        id: 'appearance.editorThemeDark',
        title: 'Editor colours when dark',
        description: 'Syntax colour scheme used while the app is in a dark '
            'theme.',
        keywords: const <String>['syntax', 'highlighting', 'colour scheme'],
        value: settings.editorThemeId,
        choices: themeChoices(isDark: true),
        onChanged: (String value) =>
            set((AppSettings s) => s.copyWith(editorThemeId: value)),
      ),
      choiceEntry<String>(
        id: 'appearance.editorThemeLight',
        title: 'Editor colours when light',
        description: 'Syntax colour scheme used while the app is in a light '
            'theme.',
        keywords: const <String>['syntax', 'highlighting', 'colour scheme'],
        value: settings.lightEditorThemeId,
        choices: themeChoices(isDark: false),
        onChanged: (String value) =>
            set((AppSettings s) => s.copyWith(lightEditorThemeId: value)),
      ),
      customEntry(
        id: 'appearance.accent',
        title: 'Accent colour',
        description:
            'Colour used for selection, links and primary buttons. Currently '
            '${accentLabel(settings.accentColorValue)}.',
        keywords: const <String>['highlight', 'primary', 'tint', 'brand'],
        child: AccentColorPicker(
          selectedValue: settings.accentColorValue,
          onSelected: (Color color) => set(
            (AppSettings s) => s.copyWith(accentColorValue: color.toARGB32()),
          ),
          onCleared: () =>
              set((AppSettings s) => s.copyWith(clearAccentColor: true)),
        ),
      ),
    ],
  );
}
