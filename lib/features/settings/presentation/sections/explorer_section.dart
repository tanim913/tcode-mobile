/// The Explorer group: what the file tree shows and how it is ordered.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/exclude_patterns_editor.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_entries.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_tiles.dart';

SettingsGroup buildExplorerGroup(WidgetRef ref, AppSettings settings) {
  void set(AppSettings Function(AppSettings) change) {
    unawaited(ref.read(settingsProvider.notifier).update(change));
  }

  return SettingsGroup(
    id: 'explorer',
    title: 'Explorer',
    description: 'The file tree: what it lists, how it sorts and when it '
        'closes.',
    onReset: () => ref.read(settingsProvider.notifier).update(
          (AppSettings s) => s.copyWith(
            showHiddenFiles: false,
            sortOrder: ExplorerSortOrder.name,
            showFileExtensions: true,
            excludePatterns: AppSettings.defaultExcludes,
            closeExplorerAfterOpen: true,
          ),
        ),
    entries: <SettingEntry>[
      toggleEntry(
        id: 'explorer.showHiddenFiles',
        title: 'Show hidden files',
        description: 'List files and folders whose name starts with a dot.',
        keywords: const <String>['dotfiles', 'invisible', 'gitignore'],
        value: settings.showHiddenFiles,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(showHiddenFiles: value)),
      ),
      choiceEntry<ExplorerSortOrder>(
        id: 'explorer.sortOrder',
        title: 'Sort order',
        description: 'How entries are ordered inside a folder. Folders always '
            'come first.',
        keywords: const <String>['order', 'alphabetical', 'date', 'extension'],
        value: settings.sortOrder,
        choices: <SettingChoice<ExplorerSortOrder>>[
          for (final ExplorerSortOrder order in ExplorerSortOrder.values)
            SettingChoice<ExplorerSortOrder>(order, order.label),
        ],
        onChanged: (ExplorerSortOrder value) =>
            set((AppSettings s) => s.copyWith(sortOrder: value)),
      ),
      toggleEntry(
        id: 'explorer.showFileExtensions',
        title: 'Show file extensions',
        description: 'Include the part after the dot in each file name.',
        keywords: const <String>['suffix', 'dart', 'names'],
        value: settings.showFileExtensions,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(showFileExtensions: value)),
      ),
      customEntry(
        id: 'explorer.excludePatterns',
        title: 'Exclude patterns',
        description: 'Folders and files hidden from the tree and skipped by '
            'search, such as build output and dependencies.',
        keywords: const <String>[
          'ignore',
          'hide',
          'node_modules',
          'build',
          'git',
        ],
        child: ExcludePatternsEditor(
          patterns: settings.excludePatterns,
          onChanged: (List<String> patterns) =>
              set((AppSettings s) => s.copyWith(excludePatterns: patterns)),
        ),
      ),
      toggleEntry(
        id: 'explorer.closeAfterOpen',
        title: 'Close explorer after opening a file',
        description: 'On a phone the tree covers the editor, so it gets out of '
            'the way once you have picked a file.',
        keywords: const <String>['panel', 'sidebar', 'dismiss', 'auto close'],
        value: settings.closeExplorerAfterOpen,
        onChanged: (bool value) =>
            set((AppSettings s) => s.copyWith(closeExplorerAfterOpen: value)),
      ),
    ],
  );
}
