/// The three short groups: Keyboard, Behaviour and Performance.
///
/// They live in one file because each is only a handful of settings; splitting
/// them into three files would be three imports for no extra clarity.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_entries.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_tiles.dart';

const int _bytesPerMb = 1024 * 1024;

const List<int> _searchLimits = <int>[500, 1000, 2000, 5000, 10000];

SettingsGroup buildKeyboardGroup(WidgetRef ref, AppSettings settings) {
  return SettingsGroup(
    id: 'keyboard',
    title: 'Keyboard',
    description: 'The row of coding keys above the software keyboard.',
    onReset: () => ref
        .read(settingsProvider.notifier)
        .update((AppSettings s) => s.copyWith(showAccessoryBar: true)),
    entries: <SettingEntry>[
      toggleEntry(
        id: 'keyboard.accessoryBar',
        title: 'Accessory bar',
        description: 'Show a row of tab, bracket, arrow and symbol keys above '
            'the software keyboard while editing.',
        keywords: const <String>[
          'toolbar',
          'symbols',
          'brackets',
          'arrows',
          'shortcuts',
        ],
        value: settings.showAccessoryBar,
        onChanged: (bool value) => unawaited(
          ref
              .read(settingsProvider.notifier)
              .update((AppSettings s) => s.copyWith(showAccessoryBar: value)),
        ),
      ),
    ],
  );
}

SettingsGroup buildBehaviourGroup(WidgetRef ref, AppSettings settings) {
  void set(AppSettings Function(AppSettings) change) {
    unawaited(ref.read(settingsProvider.notifier).update(change));
  }

  return SettingsGroup(
    id: 'behaviour',
    title: 'Behaviour',
    description: 'What happens on launch, and which actions ask first.',
    onReset: () => ref.read(settingsProvider.notifier).update(
          (AppSettings s) => s.copyWith(
            restoreSession: true,
            confirmDelete: true,
            confirmCloseUnsaved: true,
          ),
        ),
    entries: <SettingEntry>[
      toggleEntry(
        id: 'behaviour.restoreSession',
        title: 'Restore previous session',
        description: 'Reopen the workspace, tabs and cursor positions you had '
            'when the app last closed.',
        keywords: const <String>['startup', 'launch', 'reopen', 'tabs'],
        value: settings.restoreSession,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(restoreSession: value)),
      ),
      toggleEntry(
        id: 'behaviour.confirmDelete',
        title: 'Confirm deletion',
        description: 'Ask before deleting a file or folder.',
        keywords: const <String>['remove', 'trash', 'prompt', 'warning'],
        value: settings.confirmDelete,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(confirmDelete: value)),
      ),
      toggleEntry(
        id: 'behaviour.confirmCloseUnsaved',
        title: 'Confirm closing unsaved files',
        description: 'Ask before closing a tab that still has unsaved changes.',
        keywords: const <String>['dirty', 'discard', 'prompt', 'tabs'],
        value: settings.confirmCloseUnsaved,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(confirmCloseUnsaved: value)),
      ),
    ],
  );
}

SettingsGroup buildPerformanceGroup(WidgetRef ref, AppSettings settings) {
  void set(AppSettings Function(AppSettings) change) {
    unawaited(ref.read(settingsProvider.notifier).update(change));
  }

  return SettingsGroup(
    id: 'performance',
    title: 'Performance',
    description: 'Limits that keep large files and wide searches responsive.',
    onReset: () => ref.read(settingsProvider.notifier).update(
          (AppSettings s) => s.copyWith(
            warnFileSizeBytes: AppLimits.warnFileSizeBytes,
            readOnlyFileSizeBytes: AppLimits.readOnlyFileSizeBytes,
            searchResultLimit: AppLimits.searchResultLimit,
          ),
        ),
    entries: <SettingEntry>[
      sliderEntry(
        id: 'performance.warnFileSize',
        title: 'Warn above this file size',
        description: 'Opening a file larger than this asks for confirmation '
            'first, because it may take a moment.',
        keywords: const <String>['large file', 'megabytes', 'threshold', 'big'],
        value: settings.warnFileSizeBytes / _bytesPerMb,
        min: 1,
        max: 20,
        divisions: 19,
        valueLabel: _mbLabel(settings.warnFileSizeBytes),
        onChanged: (double mb) {
          final int bytes = (mb.roundToDouble() * _bytesPerMb).round();
          set(
            (AppSettings s) => s.copyWith(
              warnFileSizeBytes: bytes,
              // Warning after the file has already gone read-only would be
              // nonsense, so the upper threshold is pushed along with it.
              readOnlyFileSizeBytes: bytes > s.readOnlyFileSizeBytes
                  ? bytes
                  : s.readOnlyFileSizeBytes,
            ),
          );
        },
      ),
      sliderEntry(
        id: 'performance.readOnlyFileSize',
        title: 'Read only above this file size',
        description: 'A file larger than this opens without editing or syntax '
            'highlighting, so it still scrolls smoothly.',
        keywords: const <String>[
          'large file',
          'megabytes',
          'threshold',
          'highlighting',
        ],
        value: settings.readOnlyFileSizeBytes / _bytesPerMb,
        min: 2,
        max: 50,
        divisions: 48,
        valueLabel: _mbLabel(settings.readOnlyFileSizeBytes),
        onChanged: (double mb) {
          final int bytes = (mb.roundToDouble() * _bytesPerMb).round();
          set(
            (AppSettings s) => s.copyWith(
              readOnlyFileSizeBytes: bytes,
              warnFileSizeBytes:
                  bytes < s.warnFileSizeBytes ? bytes : s.warnFileSizeBytes,
            ),
          );
        },
      ),
      choiceEntry<int>(
        id: 'performance.searchResultLimit',
        title: 'Search result limit',
        description: 'How many matches a workspace search collects before it '
            'stops and offers to show more.',
        keywords: const <String>['find', 'matches', 'cap', 'results'],
        value: settings.searchResultLimit,
        choices: <SettingChoice<int>>[
          for (final int limit in _searchLimits)
            SettingChoice<int>(limit, '$limit'),
        ],
        onChanged: (int value) =>
            set((AppSettings s) => s.copyWith(searchResultLimit: value)),
      ),
    ],
  );
}

String _mbLabel(int bytes) => '${(bytes / _bytesPerMb).round()} MB';
