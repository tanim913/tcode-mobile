/// Root widget.
///
/// Deliberately thin: it wires themes and chooses between the welcome screen
/// and the editor shell. Adding a feature should never mean editing this file.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/shell/presentation/editor_shell.dart';
import 'package:pocket_code/features/workspace/application/session_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/features/workspace/presentation/welcome_screen.dart';

class TcodeApp extends ConsumerWidget {
  const TcodeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final ThemeMode mode = ref.watch(themeModeProvider);

    final Color? accent = settings.accentColorValue == null
        ? null
        : Color(settings.accentColorValue!);

    // High contrast replaces the dark theme rather than being a fourth mode,
    // because ThemeMode has no slot for it.
    final ThemeData darkTheme =
        settings.themeVariant == AppThemeVariant.highContrast
            ? AppTheme.highContrast(accentOverride: accent)
            : AppTheme.dark(accentOverride: accent);

    return MaterialApp(
      title: AppInfo.name,
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: AppTheme.light(accentOverride: accent),
      darkTheme: darkTheme,
      home: const _Home(),
    );
  }
}

/// Chooses between the welcome screen and the editor, after giving the saved
/// session one chance to reopen itself.
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  /// Null while the restore attempt is still in flight, so the app shows a
  /// brief loader rather than flashing the welcome screen and then replacing
  /// it with the restored workspace.
  bool? _restoreFinished;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final SessionController session = ref.read(sessionControllerProvider);
    try {
      await session.restore();
    } on Object {
      // A session that cannot be restored must never block startup; the
      // welcome screen is always a valid place to land.
    } finally {
      // Backups have either been applied or are stale; either way they must
      // not be reapplied on a later launch over newer edits.
      await session.purgeBackups();
      if (mounted) {
        setState(() => _restoreFinished = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final OpenWorkspace? workspace = ref.watch(workspaceProvider);

    if (_restoreFinished == null && workspace == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return workspace == null ? const WelcomeScreen() : const EditorShell();
  }
}
