/// The contents of the explorer's three context menus.
///
/// Kept apart from the panel so "what is on the menu" is one readable list
/// rather than something assembled inside a build method, and so a test can
/// assert the menus without driving the whole panel.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/features/explorer/presentation/context_menu.dart';

/// Every action reachable from an explorer context menu.
enum ExplorerAction {
  open,
  newFile,
  newFolder,
  cut,
  copy,
  paste,
  duplicate,
  rename,
  delete,
  copyPath,
  copyRelativePath,
  select,
  refresh,
  properties,
  share,
  openWith,
  exportZip,
  importZip,
  findInFolder,
  proposeChanges,
}

abstract final class ExplorerMenus {
  static ContextMenuEntry<ExplorerAction> _paste({required bool enabled}) =>
      ContextMenuEntry<ExplorerAction>(
        value: ExplorerAction.paste,
        label: 'Paste',
        icon: Icons.content_paste,
        enabled: enabled,
      );

  /// Menu for a file row.
  static List<ContextMenuEntry<ExplorerAction>> forFile() =>
      const <ContextMenuEntry<ExplorerAction>>[
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.open,
          label: 'Open',
          icon: Icons.open_in_new,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.cut,
          label: 'Cut',
          icon: Icons.content_cut,
          dividerBefore: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copy,
          label: 'Copy',
          icon: Icons.content_copy,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.duplicate,
          label: 'Duplicate',
          icon: Icons.file_copy_outlined,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.rename,
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
          dividerBefore: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.delete,
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.share,
          label: 'Share',
          icon: Icons.share_outlined,
          dividerBefore: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.openWith,
          label: 'Open With',
          icon: Icons.open_in_browser,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copyPath,
          label: 'Copy Path',
          icon: Icons.link,
          dividerBefore: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copyRelativePath,
          label: 'Copy Relative Path',
          icon: Icons.subdirectory_arrow_right,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.select,
          label: 'Select',
          icon: Icons.checklist,
          dividerBefore: true,
        ),
        ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.properties,
          label: 'Properties',
          icon: Icons.info_outline,
        ),
      ];

  /// Menu for a folder row. Paste stays visible but inert with an empty
  /// clipboard: hiding it would make the menu change shape and leave the user
  /// wondering whether the app supports pasting at all.
  ///
  /// [proposeLabel] adds "Create Pull Request…" (or the GitLab wording) for a
  /// folder that was downloaded from a repository. Null hides it, because a
  /// folder the app cannot propose from should not offer to.
  static List<ContextMenuEntry<ExplorerAction>> forFolder({
    required bool canPaste,
    String? proposeLabel,
  }) =>
      <ContextMenuEntry<ExplorerAction>>[
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.newFile,
          label: 'New File',
          icon: Icons.note_add_outlined,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.newFolder,
          label: 'New Folder',
          icon: Icons.create_new_folder_outlined,
        ),
        // VS Code's "Find in Folder": the workspace search, confined to this
        // folder. Folders only — a file has its own in-editor find.
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.findInFolder,
          label: 'Find in Folder…',
          icon: Icons.manage_search,
          dividerBefore: true,
        ),
        if (proposeLabel != null)
          ContextMenuEntry<ExplorerAction>(
            value: ExplorerAction.proposeChanges,
            label: proposeLabel,
            icon: Icons.call_split,
          ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.cut,
          label: 'Cut',
          icon: Icons.content_cut,
          dividerBefore: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copy,
          label: 'Copy',
          icon: Icons.content_copy,
        ),
        _paste(enabled: canPaste),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.duplicate,
          label: 'Duplicate',
          icon: Icons.file_copy_outlined,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.rename,
          label: 'Rename',
          icon: Icons.drive_file_rename_outline,
          dividerBefore: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.delete,
          label: 'Delete',
          icon: Icons.delete_outline,
          destructive: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copyPath,
          label: 'Copy Path',
          icon: Icons.link,
          dividerBefore: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.copyRelativePath,
          label: 'Copy Relative Path',
          icon: Icons.subdirectory_arrow_right,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.select,
          label: 'Select',
          icon: Icons.checklist,
          dividerBefore: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.exportZip,
          label: 'Export as ZIP',
          icon: Icons.folder_zip_outlined,
          dividerBefore: true,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.importZip,
          label: 'Import from ZIP',
          icon: Icons.unarchive_outlined,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.properties,
          label: 'Folder Details',
          icon: Icons.info_outline,
        ),
      ];

  /// Menu for a long press on empty space below the tree.
  static List<ContextMenuEntry<ExplorerAction>> forEmptySpace({
    required bool canPaste,
  }) =>
      <ContextMenuEntry<ExplorerAction>>[
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.newFile,
          label: 'New File',
          icon: Icons.note_add_outlined,
        ),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.newFolder,
          label: 'New Folder',
          icon: Icons.create_new_folder_outlined,
        ),
        _paste(enabled: canPaste),
        const ContextMenuEntry<ExplorerAction>(
          value: ExplorerAction.refresh,
          label: 'Refresh',
          icon: Icons.refresh,
          dividerBefore: true,
        ),
      ];
}
