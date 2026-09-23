/// Application-wide dependency injection.
///
/// Riverpod is doing two jobs here: holding state that the UI rebuilds from,
/// and wiring dependencies. The second job is why tests can replace the real
/// file system with a fake by overriding one provider, with no change to any
/// widget.
///
/// Providers that need async setup are overridden in `bootstrap.dart` rather
/// than being async themselves, so the widget tree never renders a loading
/// state for something that was ready before the first frame.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/core/theme/editor_color_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_registry.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/history_repository.dart';
import 'package:pocket_code/data/repositories/recents_repository.dart';
import 'package:pocket_code/data/repositories/session_repository.dart';
import 'package:pocket_code/data/repositories/settings_repository.dart';
import 'package:pocket_code/data/repositories/snippets_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/services/commands/command_registry.dart';

/// Overridden in `bootstrap.dart`. Reading it without that override is a bug,
/// and the thrown error says so rather than silently using a stub.
final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>(
  (Ref ref) => throw UnimplementedError(
    'settingsRepositoryProvider must be overridden in bootstrap()',
  ),
);

/// Seeded with the settings loaded before the first frame.
final Provider<AppSettings> initialSettingsProvider = Provider<AppSettings>(
  (Ref ref) => throw UnimplementedError(
    'initialSettingsProvider must be overridden in bootstrap()',
  ),
);

/// Live settings. Every write persists immediately — there is no Save button in
/// a settings screen, so a change the user makes must survive being killed.
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final AppSettings next = change(state);
    state = next;
    await ref.read(settingsRepositoryProvider).save(next);
  }

  /// Convenience for the common case of changing one editor field.
  Future<void> updateEditor(EditorSettings Function(EditorSettings) change) {
    return update((AppSettings s) => s.copyWith(editor: change(s.editor)));
  }
}

final NotifierProvider<SettingsNotifier, AppSettings> settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Session storage. Overridden in `bootstrap.dart` once app-private support
/// storage has been opened; null means session persistence is unavailable,
/// which the app must survive rather than crash on.
final Provider<SessionRepository?> sessionRepositoryProvider =
    Provider<SessionRepository?>((Ref ref) => null);

/// App-private storage for the app's own state files. Overridden in
/// `bootstrap.dart`; null means every feature that keeps its own file is
/// unavailable, which each of them must survive rather than crash on.
final Provider<SupportStorage?> supportStorageProvider =
    Provider<SupportStorage?>((Ref ref) => null);

/// Snippet storage, null when [supportStorageProvider] is.
final Provider<SnippetsRepository?> snippetsRepositoryProvider =
    Provider<SnippetsRepository?>((Ref ref) {
  final SupportStorage? storage = ref.watch(supportStorageProvider);
  return storage == null ? null : SnippetsRepository(storage);
});

/// Recent-items storage, null when [supportStorageProvider] is.
final Provider<RecentsRepository?> recentsRepositoryProvider =
    Provider<RecentsRepository?>((Ref ref) {
  final SupportStorage? storage = ref.watch(supportStorageProvider);
  return storage == null ? null : RecentsRepository(storage);
});

/// File-history storage, null when [supportStorageProvider] is.
final Provider<HistoryRepository?> historyRepositoryProvider =
    Provider<HistoryRepository?>((Ref ref) {
  final SupportStorage? storage = ref.watch(supportStorageProvider);
  return storage == null ? null : HistoryRepository(storage);
});

/// Recent items as loaded at startup. Overridden in `main.dart`.
final Provider<RecentItems> initialRecentsProvider =
    Provider<RecentItems>((Ref ref) => const RecentItems());

/// Snippets as loaded at startup. Overridden in `main.dart`.
final Provider<List<Snippet>> initialSnippetsProvider =
    Provider<List<Snippet>>((Ref ref) => const <Snippet>[]);

/// The command catalogue. Long-lived, mutated as features register actions.
final Provider<CommandRegistry> commandRegistryProvider =
    Provider<CommandRegistry>((Ref ref) {
  final CommandRegistry registry = CommandRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});

/// Resolves the app theme mode from settings.
final Provider<ThemeMode> themeModeProvider = Provider<ThemeMode>((Ref ref) {
  return switch (ref.watch(settingsProvider).themeVariant) {
    AppThemeVariant.system => ThemeMode.system,
    AppThemeVariant.light => ThemeMode.light,
    // High contrast is a dark-based theme, so it maps to dark mode and swaps
    // the palette underneath.
    AppThemeVariant.dark || AppThemeVariant.highContrast => ThemeMode.dark,
  };
});

/// Editor colours for the current brightness.
///
/// A function of brightness rather than a plain provider because the widget
/// tree knows the resolved brightness and this file does not.
EditorColorTheme editorThemeFor(AppSettings settings, Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  return EditorThemeRegistry.byId(
    dark ? settings.editorThemeId : settings.lightEditorThemeId,
    preferDark: dark,
  );
}
