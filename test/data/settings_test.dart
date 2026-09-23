import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/harness.dart';

void main() {
  group('serialisation round trip', () {
    test('every field survives a save and load', () async {
      final AppSettings original = const AppSettings().copyWith(
        themeVariant: AppThemeVariant.highContrast,
        editorThemeId: 'ember-dark',
        accentColorValue: 0xFF00FF00,
        showHiddenFiles: true,
        sortOrder: ExplorerSortOrder.modified,
        showFileExtensions: false,
        excludePatterns: <String>['.git', 'vendor'],
        closeExplorerAfterOpen: false,
        restoreSession: false,
        confirmDelete: false,
        onboardingComplete: true,
        editor: const EditorSettings().copyWith(
          fontSize: 18,
          fontFamily: EditorFontFamily.firaCode,
          ligatures: false,
          wordWrap: true,
          tabSize: 4,
          insertSpaces: false,
          autoSaveMode: AutoSaveMode.onFocusLost,
        ),
      );

      final SettingsRepository repo = await fakeSettingsRepository();
      await repo.save(original);
      final AppSettings loaded = repo.load();

      expect(loaded.themeVariant, AppThemeVariant.highContrast);
      expect(loaded.editorThemeId, 'ember-dark');
      expect(loaded.accentColorValue, 0xFF00FF00);
      expect(loaded.showHiddenFiles, isTrue);
      expect(loaded.sortOrder, ExplorerSortOrder.modified);
      expect(loaded.showFileExtensions, isFalse);
      expect(loaded.excludePatterns, <String>['.git', 'vendor']);
      expect(loaded.closeExplorerAfterOpen, isFalse);
      expect(loaded.restoreSession, isFalse);
      expect(loaded.confirmDelete, isFalse);
      expect(loaded.onboardingComplete, isTrue);
      expect(loaded.editor.fontSize, 18);
      expect(loaded.editor.fontFamily, EditorFontFamily.firaCode);
      expect(loaded.editor.ligatures, isFalse);
      expect(loaded.editor.wordWrap, isTrue);
      expect(loaded.editor.tabSize, 4);
      expect(loaded.editor.insertSpaces, isFalse);
      expect(loaded.editor.autoSaveMode, AutoSaveMode.onFocusLost);
    });

    test('a fresh install loads defaults', () async {
      final SettingsRepository repo = await fakeSettingsRepository();
      expect(repo.load().editor.fontSize, AppLimits.defaultFontSize);
      expect(repo.load().onboardingComplete, isFalse);
    });
  });

  group('resilience to bad data', () {
    test('corrupt JSON falls back to defaults instead of crashing', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_v1': 'this is not json {{{',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      expect(SettingsRepository(prefs).load(), isA<AppSettings>());
      expect(
        SettingsRepository(prefs).load().editor.fontSize,
        AppLimits.defaultFontSize,
      );
    });

    test('an unknown enum value falls back for that field only', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_v1':
            '{"themeVariant":"neon","editorThemeId":"ember-dark"}',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppSettings loaded = SettingsRepository(prefs).load();

      expect(loaded.themeVariant, AppThemeVariant.system,
          reason: 'the bad value falls back');
      expect(loaded.editorThemeId, 'ember-dark',
          reason: 'but the good value beside it is kept');
    });

    test('a wrongly typed value falls back', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_v1': '{"showHiddenFiles":"yes","editor":{"fontSize":"big"}}',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final AppSettings loaded = SettingsRepository(prefs).load();

      expect(loaded.showHiddenFiles, isFalse);
      expect(loaded.editor.fontSize, AppLimits.defaultFontSize);
    });

    test('an out-of-range font size is clamped, not rejected', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'app_settings_v1': '{"editor":{"fontSize":9999}}',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      expect(
        SettingsRepository(prefs).load().editor.fontSize,
        AppLimits.maxFontSize,
      );
    });
  });

  group('copyWith', () {
    test('clearing the accent colour is distinguishable from not setting it', () {
      const AppSettings withAccent = AppSettings(accentColorValue: 0xFF112233);

      expect(withAccent.copyWith().accentColorValue, 0xFF112233,
          reason: 'omitting the argument keeps the current value');
      expect(withAccent.copyWith(clearAccentColor: true).accentColorValue, isNull,
          reason: 'the explicit clear flag removes it');
    });

    test('changing one editor field leaves the others alone', () {
      const AppSettings before = AppSettings();
      final AppSettings after = before.copyWith(
        editor: before.editor.copyWith(fontSize: 20),
      );
      expect(after.editor.fontSize, 20);
      expect(after.editor.tabSize, before.editor.tabSize);
      expect(after.showHiddenFiles, before.showHiddenFiles);
    });
  });
}
