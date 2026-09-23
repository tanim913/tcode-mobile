/// The explorer's header, in its three forms: normal actions, the pending
/// clipboard chip, and the multi-select action bar.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/services/clipboard/file_clipboard.dart';

enum _HeaderAction { collapseAll, refresh, closeFolder }

class ExplorerHeader extends StatelessWidget {
  const ExplorerHeader({
    required this.title,
    required this.enabled,
    required this.onNewFile,
    required this.onNewFolder,
    required this.onRefresh,
    required this.onCollapseAll,
    required this.onCloseFolder,
    super.key,
  });

  final String title;
  final bool enabled;
  final VoidCallback onNewFile;
  final VoidCallback onNewFolder;
  final VoidCallback onRefresh;
  final VoidCallback onCollapseAll;

  /// Closes the whole workspace. It lives here as well as in the app bar
  /// because the workspace name is shown here, so this is where it is looked
  /// for. Both routes call the same handler, which prompts about unsaved work.
  final VoidCallback onCloseFolder;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Container(
      height: AppSizes.toolbarHeight,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          _Action(
            tooltip: 'New file',
            icon: Icons.note_add_outlined,
            onPressed: enabled ? onNewFile : null,
          ),
          _Action(
            tooltip: 'New folder',
            icon: Icons.create_new_folder_outlined,
            onPressed: enabled ? onNewFolder : null,
          ),
          // Only the two creation actions stay visible. On a phone the panel is
          // 50% of the screen — about 270dp — and four icons left the workspace
          // name ellipsised to "P…", which is worse than one extra tap.
          PopupMenuButton<_HeaderAction>(
            tooltip: 'More',
            enabled: enabled,
            icon: Icon(Icons.more_vert, size: 18, color: tokens.textSecondary),
            padding: EdgeInsets.zero,
            onSelected: (_HeaderAction action) => switch (action) {
              _HeaderAction.collapseAll => onCollapseAll(),
              _HeaderAction.refresh => onRefresh(),
              _HeaderAction.closeFolder => onCloseFolder(),
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<_HeaderAction>>[
              PopupMenuItem<_HeaderAction>(
                value: _HeaderAction.collapseAll,
                height: AppSizes.minTouchTarget,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.unfold_less, size: 16, color: tokens.textSecondary),
                    const SizedBox(width: 10),
                    const Text('Collapse all'),
                  ],
                ),
              ),
              PopupMenuItem<_HeaderAction>(
                value: _HeaderAction.refresh,
                height: AppSizes.minTouchTarget,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.refresh, size: 16, color: tokens.textSecondary),
                    const SizedBox(width: 10),
                    const Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<_HeaderAction>(
                value: _HeaderAction.closeFolder,
                height: AppSizes.minTouchTarget,
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.folder_off_outlined,
                      size: 16,
                      color: tokens.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    const Text('Close folder'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "2 items to paste", with a way out.
///
/// Without this, a cut made three screens ago is invisible state that quietly
/// changes what Paste does.
class ClipboardChip extends StatelessWidget {
  const ClipboardChip({
    required this.clipboard,
    required this.onClear,
    super.key,
  });

  final FileClipboard clipboard;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      color: tokens.accent.withValues(alpha: 0.12),
      child: Row(
        children: <Widget>[
          // The icon distinguishes a pending cut from a pending copy without
          // relying on the wording alone.
          Icon(
            clipboard.isCut ? Icons.content_cut : Icons.content_copy,
            size: 14,
            color: tokens.accent,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              clipboard.chipLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.accent),
            ),
          ),
          _Action(
            tooltip: 'Clear clipboard',
            icon: Icons.close,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

/// Header while multi-select is on: the count, then the actions that make
/// sense for a set of items.
class SelectionActionBar extends StatelessWidget {
  const SelectionActionBar({
    required this.count,
    required this.onCut,
    required this.onCopy,
    required this.onDelete,
    required this.onClose,
    super.key,
  });

  final int count;
  final VoidCallback onCut;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final bool any = count > 0;
    return Container(
      height: AppSizes.toolbarHeight,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: tokens.sidebarActive,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              count == 1 ? '1 selected' : '$count selected',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          _Action(
            tooltip: 'Cut',
            icon: Icons.content_cut,
            onPressed: any ? onCut : null,
          ),
          _Action(
            tooltip: 'Copy',
            icon: Icons.content_copy,
            onPressed: any ? onCopy : null,
          ),
          _Action(
            tooltip: 'Delete',
            icon: Icons.delete_outline,
            color: tokens.danger,
            onPressed: any ? onDelete : null,
          ),
          _Action(
            tooltip: 'Close selection',
            icon: Icons.close,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      // Tooltip doubles as the semantics label, so every icon button here is
      // announced without a second string to keep in sync.
      tooltip: tooltip,
      icon: Icon(icon, size: 18, color: onPressed == null ? null : color),
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }
}
