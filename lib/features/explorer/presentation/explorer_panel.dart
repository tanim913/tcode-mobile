/// The explorer panel: header, clipboard chip, and the virtualized tree.
///
/// This file is deliberately about wiring and layout. The behaviour behind each
/// menu action lives in [ExplorerActions], and the file-system work behind that
/// lives in `FileOperations`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/features/explorer/presentation/context_menu.dart';
import 'package:pocket_code/features/explorer/presentation/explorer_actions.dart';
import 'package:pocket_code/features/explorer/presentation/explorer_header.dart';
import 'package:pocket_code/features/explorer/presentation/explorer_menus.dart';
import 'package:pocket_code/features/explorer/presentation/file_icons.dart';
import 'package:pocket_code/features/explorer/presentation/inline_rename_field.dart';
import 'package:pocket_code/features/explorer/presentation/name_dialog.dart';
import 'package:pocket_code/features/explorer/presentation/tree_row_tile.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/clipboard/file_clipboard.dart';
import 'package:pocket_code/services/git_host/repo_link_store.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

class ExplorerPanel extends ConsumerStatefulWidget {
  const ExplorerPanel({
    required this.onOpenFile,
    required this.onCloseFolder,
    required this.onFindInFolder,
    this.onProposeChanges,
    super.key,
  });

  /// Called when the user taps a file. The shell decides what to do with it.
  final void Function(FileNode file, int rootIndex) onOpenFile;

  /// Closes the workspace. Owned by the shell, because closing has to prompt
  /// about unsaved tabs before the workspace goes away.
  final VoidCallback onCloseFolder;

  /// Opens the workspace search confined to [folder]. Owned by the shell,
  /// which pushes the search screen and knows how to index a subtree.
  final void Function(FolderNode folder, int rootIndex) onFindInFolder;

  /// Opens the pull request screen for a downloaded repository folder.
  final void Function(FolderNode folder, int rootIndex)? onProposeChanges;

  @override
  ConsumerState<ExplorerPanel> createState() => _ExplorerPanelState();
}

class _ExplorerPanelState extends ConsumerState<ExplorerPanel> {
  final ScrollController _scroll = ScrollController();

  /// The row last touched, which decides where a new item is created.
  TreeRow? _selected;

  /// The row currently being renamed in place, if any.
  String? _renamingKey;

  /// Multi-select mode and the rows ticked in it.
  bool _selectionMode = false;
  final Set<String> _checked = <String>{};

  /// The folder row a drag is hovering over, highlighted as the drop target.
  String? _dropTargetKey;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  ExplorerActions get _actions => ExplorerActions(ref: ref, context: context);

  // --- Helpers --------------------------------------------------------------

  /// Names already inside [folderId], so a dialog can reject a duplicate
  /// before the file system is asked.
  Set<String> _siblingNames(String folderId) {
    final LiveRoot? root =
        ref.read(workspaceProvider)?.rootAt(_selected?.rootIndex ?? 0);
    if (root == null) {
      return <String>{};
    }
    return ref
        .read(treeProvider)
        .rows
        .where((TreeRow r) => root.provider.parentOf(r.node.id) == folderId)
        .map((TreeRow r) => r.node.name)
        .toSet();
  }

  List<ClipboardItem> _targets(TreeRow row) {
    // In selection mode an action applies to every ticked row; otherwise to
    // the row that was long-pressed.
    if (_selectionMode && _checked.isNotEmpty) {
      return ref
          .read(treeProvider)
          .rows
          .where((TreeRow r) => _checked.contains(r.key))
          .map(itemOf)
          .toList();
    }
    return <ClipboardItem>[itemOf(row)];
  }

  // --- Create ---------------------------------------------------------------

  Future<void> _create({required bool folder, TreeRow? near}) async {
    if (ref.read(workspaceProvider) == null) {
      return;
    }
    final TreeRow? anchor = near ?? _selected;
    final int rootIndex = anchor?.rootIndex ?? 0;
    final String parentId =
        ref.read(treeProvider.notifier).targetFolderFor(anchor, rootIndex);

    final String? name = await promptForName(
      context,
      title: folder ? 'New folder' : 'New file',
      label: 'Name',
      existingNames: _siblingNames(parentId),
    );
    if (name == null || !mounted) {
      return;
    }
    final TreeController tree = ref.read(treeProvider.notifier);
    if (folder) {
      await tree.createFolder(rootIndex, parentId, name);
      return;
    }
    final String? id = await tree.createFile(rootIndex, parentId, name);
    if (id == null || !mounted) {
      return;
    }
    // Opening the file straight away is what the user wanted by creating it.
    final TreeRow? created = ref
        .read(treeProvider)
        .rows
        .where((TreeRow r) => r.node.id == id)
        .firstOrNull;
    if (created != null && created.node is FileNode) {
      widget.onOpenFile(created.node as FileNode, rootIndex);
    }
  }

  // --- Context menu ---------------------------------------------------------

  Future<void> _showRowMenu(TreeRow row, Offset position) async {
    setState(() => _selected = row);
    final bool canPaste = ref.read(fileClipboardProvider).isNotEmpty;
    final String? proposeLabel =
        row.isFolder ? await _proposeLabelFor(row) : null;
    if (!mounted) {
      return;
    }
    final ExplorerAction? action = await showTreeContextMenu<ExplorerAction>(
      context: context,
      globalPosition: position,
      entries: row.isFolder
          ? ExplorerMenus.forFolder(
              canPaste: canPaste,
              proposeLabel: proposeLabel,
            )
          : ExplorerMenus.forFile(),
      semanticsLabel: 'Actions for ${row.node.name}',
    );
    if (action != null) {
      await _dispatch(action, row);
    }
  }

  /// "Create Pull Request…" for a folder downloaded from GitHub, the GitLab
  /// wording for GitLab, and null for anything else — or where there is no
  /// network, so the Play build never offers it.
  Future<String?> _proposeLabelFor(TreeRow row) async {
    if (widget.onProposeChanges == null ||
        !ref.read(httpTransportProvider).isAvailable) {
      return null;
    }
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(row.rootIndex);
    if (root == null) {
      return null;
    }
    final RepoLink? link = await RepoLinkStore(root.provider).read(row.node.id);
    return switch (link?.host) {
      null => null,
      RepoHost.github => 'Create Pull Request…',
      RepoHost.gitlab => 'Create Merge Request…',
    };
  }

  Future<void> _showEmptySpaceMenu(Offset position) async {
    if (ref.read(workspaceProvider) == null) {
      return;
    }
    final bool canPaste = ref.read(fileClipboardProvider).isNotEmpty;
    final ExplorerAction? action = await showTreeContextMenu<ExplorerAction>(
      context: context,
      globalPosition: position,
      entries: ExplorerMenus.forEmptySpace(canPaste: canPaste),
      semanticsLabel: 'Explorer actions',
    );
    if (action == null) {
      return;
    }
    final int rootIndex = _selected?.rootIndex ?? 0;
    final String rootId =
        ref.read(workspaceProvider)?.rootAt(rootIndex)?.root.rootId ?? '';
    switch (action) {
      case ExplorerAction.newFile:
        await _create(folder: false);
      case ExplorerAction.newFolder:
        await _create(folder: true);
      case ExplorerAction.paste:
        await _actions.paste(rootIndex, rootId);
      case ExplorerAction.refresh:
        await ref.read(treeProvider.notifier).refresh();
      // ignore: no_default_cases
      default:
        break;
    }
  }

  Future<void> _dispatch(ExplorerAction action, TreeRow row) async {
    final List<ClipboardItem> targets = _targets(row);
    final AppSettings settings = ref.read(settingsProvider);

    switch (action) {
      case ExplorerAction.open:
        if (row.node is FileNode) {
          widget.onOpenFile(row.node as FileNode, row.rootIndex);
        } else {
          await ref.read(treeProvider.notifier).toggle(row);
        }
      case ExplorerAction.newFile:
        await _create(folder: false, near: row);
      case ExplorerAction.newFolder:
        await _create(folder: true, near: row);
      case ExplorerAction.cut:
        _actions.cut(targets);
        _exitSelection();
      case ExplorerAction.copy:
        _actions.copy(targets);
        _exitSelection();
      case ExplorerAction.paste:
        await _actions.paste(
          row.rootIndex,
          ref.read(treeProvider.notifier).targetFolderFor(row, row.rootIndex),
        );
      case ExplorerAction.duplicate:
        await _actions.duplicate(targets);
      case ExplorerAction.rename:
        setState(() => _renamingKey = row.key);
      case ExplorerAction.delete:
        await _actions.delete(targets, confirm: settings.confirmDelete);
        _exitSelection();
      case ExplorerAction.copyPath:
        await _actions.copyPath(itemOf(row));
      case ExplorerAction.copyRelativePath:
        await _actions.copyRelativePath(itemOf(row));
      case ExplorerAction.properties:
        await _actions.showProperties(itemOf(row));
      case ExplorerAction.select:
        setState(() {
          _selectionMode = true;
          _checked
            ..clear()
            ..add(row.key);
        });
      case ExplorerAction.refresh:
        await ref.read(treeProvider.notifier).refresh(row);
      case ExplorerAction.share:
        await _actions.share(itemOf(row));
      case ExplorerAction.openWith:
        await _actions.openWith(itemOf(row));
      case ExplorerAction.exportZip:
        await _actions.exportZip(itemOf(row));
      case ExplorerAction.importZip:
        await _actions.importZip(itemOf(row));
      case ExplorerAction.findInFolder:
        if (row.node is FolderNode) {
          widget.onFindInFolder(row.node as FolderNode, row.rootIndex);
        }
      case ExplorerAction.proposeChanges:
        if (row.node is FolderNode) {
          widget.onProposeChanges?.call(row.node as FolderNode, row.rootIndex);
        }
    }
  }

  void _exitSelection() {
    if (!_selectionMode) {
      return;
    }
    setState(() {
      _selectionMode = false;
      _checked.clear();
    });
  }

  // --- Drag and drop --------------------------------------------------------

  /// Moves [dragged] into [target], reusing the same machinery as cut+paste so
  /// conflicts, progress and the move-into-itself guard behave identically.
  Future<void> _dropOnto(TreeRow dragged, TreeRow target) async {
    setState(() => _dropTargetKey = null);
    final LiveRoot? root =
        ref.read(workspaceProvider)?.rootAt(dragged.rootIndex);
    if (root == null) {
      return;
    }
    // Dropping back into the folder it already lives in is a no-op, not an
    // error — silently doing nothing is the least surprising outcome.
    if (root.provider.parentOf(dragged.node.id) == target.node.id) {
      return;
    }
    ref.read(fileClipboardProvider.notifier).cut(<ClipboardItem>[itemOf(dragged)]);
    await _actions.paste(target.rootIndex, target.node.id);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final TreeState tree = ref.watch(treeProvider);
    final OpenWorkspace? workspace = ref.watch(workspaceProvider);
    final AppSettings settings = ref.watch(settingsProvider);
    final FileClipboard clipboard = ref.watch(fileClipboardProvider);

    return ColoredBox(
      color: tokens.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_selectionMode)
            SelectionActionBar(
              count: _checked.length,
              onCut: () => _withChecked(_actions.cut),
              onCopy: () => _withChecked(_actions.copy),
              onDelete: () => _withChecked(
                (List<ClipboardItem> items) => _actions.delete(
                  items,
                  confirm: settings.confirmDelete,
                ),
              ),
              onClose: _exitSelection,
            )
          else
            ExplorerHeader(
              title: workspace?.displayName ?? 'No folder open',
              enabled: workspace != null,
              onNewFile: () => _create(folder: false),
              onNewFolder: () => _create(folder: true),
              onRefresh: () => ref.read(treeProvider.notifier).refresh(),
              onCollapseAll: ref.read(treeProvider.notifier).collapseAll,
              onCloseFolder: widget.onCloseFolder,
            ),
          if (clipboard.isNotEmpty)
            ClipboardChip(
              clipboard: clipboard,
              onClear: ref.read(fileClipboardProvider.notifier).clear,
            ),
          if (tree.error != null)
            _InlineError(message: tree.error!, tokens: tokens),
          Expanded(
            child: workspace == null
                ? _Empty(
                    message: 'No folder is open.',
                    hint: 'Open a folder to see its files here.',
                    tokens: tokens,
                  )
                : _tree(tree, settings, tokens),
          ),
        ],
      ),
    );
  }

  void _withChecked(void Function(List<ClipboardItem>) action) {
    final List<ClipboardItem> items = ref
        .read(treeProvider)
        .rows
        .where((TreeRow r) => _checked.contains(r.key))
        .map(itemOf)
        .toList();
    if (items.isEmpty) {
      return;
    }
    action(items);
  }

  Widget _tree(TreeState tree, AppSettings settings, AppColorTokens tokens) {
    if (tree.rows.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => ref.read(treeProvider.notifier).refresh(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPressStart: (LongPressStartDetails d) =>
              _showEmptySpaceMenu(d.globalPosition),
          child: ListView(
            // An empty folder still has to be refreshable, and a RefreshIndicator
            // needs a scrollable to attach to.
            physics: const AlwaysScrollableScrollPhysics(),
            children: <Widget>[
              SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.6,
                child: _Empty(
                  message: 'This folder is empty.',
                  hint: settings.showHiddenFiles
                      ? 'Long press here to create a file.'
                      : 'Hidden files are off, so some items may be filtered out.',
                  tokens: tokens,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      // Pull-to-refresh is not a convenience here, it is the fallback: SAF has
      // no file watcher, so on an external folder this is the only way to pick
      // up a change made by another app.
      onRefresh: () => ref.read(treeProvider.notifier).refresh(),
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          // Closing the panel unmounts it — the scaffold returns an empty box
          // when fully closed — which destroys the scroll position with it.
          // A PageStorageKey makes Flutter save the offset on dispose and
          // restore it on the next mount, so reopening the explorer returns to
          // where you were rather than jumping to the top.
          key: const PageStorageKey<String>('explorer.tree'),
          controller: _scroll,
          // Always scrollable, or a folder with three rows has nothing to pull.
          physics: const AlwaysScrollableScrollPhysics(),
          // A fixed extent lets the list skip measuring rows, which is what
          // keeps a 10,000-entry folder fast.
          itemExtent: AppSizes.treeRowHeight,
          itemCount: tree.rows.length,
          itemBuilder: (BuildContext context, int index) =>
              _row(tree.rows[index], tree, settings),
        ),
      ),
    );
  }

  Widget _row(TreeRow row, TreeState tree, AppSettings settings) {
    if (_renamingKey == row.key) {
      final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(row.rootIndex);
      final String parentId =
          root?.provider.parentOf(row.node.id) ?? root?.root.rootId ?? '';
      final FileIcon icon = FileIcons.forNode(row.node);
      return InlineRenameField(
        initialName: row.node.name,
        existingNames: _siblingNames(parentId)..remove(row.node.name),
        icon: Icon(icon.icon, size: 16, color: icon.color),
        indent: 6 + row.depth * AppSizes.treeIndentPerLevel,
        onCommit: (String newName) async {
          setState(() => _renamingKey = null);
          await ref.read(treeProvider.notifier).rename(row, newName);
        },
        onCancel: () => setState(() => _renamingKey = null),
      );
    }

    final Widget tile = TreeRowTile(
      key: ValueKey<String>(row.key),
      row: row,
      isActive: tree.activeFileId == row.node.id,
      showExtensions: settings.showFileExtensions,
      selectionMode: _selectionMode,
      isChecked: _checked.contains(row.key),
      isDropTarget: _dropTargetKey == row.key,
      onCheckChanged: (bool? checked) => setState(() {
        if (checked ?? false) {
          _checked.add(row.key);
        } else {
          _checked.remove(row.key);
        }
      }),
      onTap: () {
        if (_selectionMode) {
          setState(() {
            if (_checked.contains(row.key)) {
              _checked.remove(row.key);
            } else {
              _checked.add(row.key);
            }
          });
          return;
        }
        setState(() => _selected = row);
        if (row.isFolder) {
          ref.read(treeProvider.notifier).toggle(row);
        } else {
          widget.onOpenFile(row.node as FileNode, row.rootIndex);
        }
      },
      onLongPress: _selectionMode
          ? null
          : (Offset position) => _showRowMenu(row, position),
    );

    // Folders accept drops; every row can be dragged. Selection mode disables
    // dragging so ticking checkboxes does not start a move.
    final Widget draggable = _selectionMode
        ? tile
        : LongPressDraggable<TreeRow>(
            data: row,
            // Long press already opens the context menu, so the drag has to
            // win only once movement starts — Flutter resolves that in the
            // gesture arena, and the menu is dismissed by the drag.
            feedback: _DragFeedback(row: row),
            childWhenDragging: Opacity(opacity: 0.4, child: tile),
            child: tile,
          );

    if (!row.isFolder) {
      return draggable;
    }
    return DragTarget<TreeRow>(
      onWillAcceptWithDetails: (DragTargetDetails<TreeRow> details) {
        if (details.data.key == row.key) {
          return false;
        }
        setState(() => _dropTargetKey = row.key);
        return true;
      },
      onLeave: (_) => setState(() => _dropTargetKey = null),
      onAcceptWithDetails: (DragTargetDetails<TreeRow> details) =>
          _dropOnto(details.data, row),
      builder: (BuildContext context, _, _) => draggable,
    );
  }
}

/// What follows the finger during a drag.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.row});

  final TreeRow row;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final FileIcon icon = FileIcons.forNode(row.node);
    return Material(
      elevation: 6,
      color: tokens.surfaceRaised,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon.icon, size: 14, color: icon.color),
            const SizedBox(width: 6),
            Text(row.node.name, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Errors show inline rather than as a snackbar, because a folder that failed
/// to open is a persistent condition the user needs to keep seeing.
class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.tokens});

  final String message;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: tokens.danger.withValues(alpha: 0.12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.error_outline, size: 14, color: tokens.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.message,
    required this.hint,
    required this.tokens,
  });

  final String message;
  final String hint;
  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_off_outlined, size: 28, color: tokens.textMuted),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
