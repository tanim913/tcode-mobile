/// The app bar and the status-bar wrapper.
///
/// Split out of `editor_shell.dart` to keep that file near the ~400 line
/// convention: the shell is about wiring, and these two are about chrome.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/features/shell/presentation/explorer_scaffold.dart';
import 'package:pocket_code/features/shell/presentation/status_bar.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:re_editor/re_editor.dart';

class StatusBarForTab extends ConsumerWidget {
  const StatusBarForTab({required this.tab, super.key});

  final OpenTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CodeLineEditingController controller = ref
        .read(tabsProvider.notifier)
        .controllerFor(tab);
    return StatusBar(
      controller: controller,
      languageLabel: tab.language.label,
      indent: tab.indent,
      format: tab.format,
      isDirty: tab.isDirty,
    );
  }
}

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({
    super.key,
    required this.panel,
    required this.onCommandPalette,
    required this.onQuickOpen,
    required this.hasWorkspace,
    required this.canToggleEditing,
    required this.isEditable,
    required this.onToggleEditing,
    required this.title,
    required this.isDirty,
    required this.anyDirty,
    required this.onSave,
    required this.onSaveAll,
    required this.onCloseWorkspace,
    required this.onSettings,
  });

  final ExplorerPanelController panel;

  /// The palette is the discoverable home of every action, so it sits at the
  /// top of this menu rather than behind a shortcut no phone has.
  final VoidCallback onCommandPalette;
  final VoidCallback onQuickOpen;

  /// Quick Open has nothing to search without a workspace.
  final bool hasWorkspace;

  /// False when the open document is read-only for a reason the toggle cannot
  /// override — too large, binary, an image — or when nothing is open.
  final bool canToggleEditing;

  /// Whether the open document accepts typing right now.
  final bool isEditable;

  final VoidCallback onToggleEditing;

  final String title;
  final bool isDirty;
  final bool anyDirty;
  final VoidCallback onSave;
  final VoidCallback onSaveAll;
  final VoidCallback onCloseWorkspace;
  final VoidCallback onSettings;

  @override
  Size get preferredSize => const Size.fromHeight(48);

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context)
        .extension<AppColorTokens>()!;
    return AppBar(
      toolbarHeight: 48,
      leading: IconButton(
        tooltip: 'Toggle explorer',
        icon: const Icon(Icons.menu),
        onPressed: panel.toggle,
      ),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (isDirty) ...<Widget>[
            const SizedBox(width: 6),
            // Shape plus a semantics label: never colour alone.
            Semantics(
              label: 'unsaved',
              child: Icon(
                Icons.circle,
                size: 7,
                color: tokens.unsavedIndicator,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        // Deliberately its own button rather than a menu entry: it is a mode,
        // and a mode needs to show its state without being opened.
        IconButton(
          tooltip: switch ((canToggleEditing, isEditable)) {
            (false, _) => 'This file cannot be edited',
            (true, true) => 'Editing on — tap to lock',
            (true, false) => 'Editing off — tap to unlock',
          },
          isSelected: isEditable,
          icon: Icon(
            isEditable ? Icons.edit_outlined : Icons.lock_outline,
            // Colour alone never carries the state: the icon changes shape too.
            color: canToggleEditing && !isEditable ? tokens.warning : null,
          ),
          onPressed: canToggleEditing ? onToggleEditing : null,
        ),
        IconButton(
          tooltip: isDirty ? 'Save' : 'Saved',
          icon: const Icon(Icons.save_outlined),
          onPressed: isDirty ? onSave : null,
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (String value) {
            switch (value) {
              case 'palette':
                onCommandPalette();
              case 'quickOpen':
                onQuickOpen();
              case 'saveAll':
                onSaveAll();
              case 'settings':
                onSettings();
              case 'close':
                onCloseWorkspace();
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'palette',
              child: Text('Command palette'),
            ),
            PopupMenuItem<String>(
              value: 'quickOpen',
              enabled: hasWorkspace,
              child: const Text('Go to file'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem<String>(
              value: 'saveAll',
              enabled: anyDirty,
              child: const Text('Save all'),
            ),
            const PopupMenuItem<String>(
              value: 'settings',
              child: Text('Settings'),
            ),
            const PopupMenuItem<String>(
              value: 'close',
              child: Text('Close folder'),
            ),
          ],
        ),
      ],
    );
  }
}

