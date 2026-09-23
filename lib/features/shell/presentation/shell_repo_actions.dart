/// Opening the pull request screen, from the explorer or the palette.
///
/// Its own mixin for the same reason as `shell_editor_actions.dart`: it needs
/// `context`, `ref` and `mounted` together, and the shell is already past the
/// size convention.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/features/change_request/presentation/change_request_screen.dart';
import 'package:pocket_code/features/shell/presentation/explorer_scaffold.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

mixin ShellRepoActions<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  ExplorerPanelController get panel;

  /// For the palette: the root of the active file, or the first root.
  Future<void> proposeWorkspaceChanges() async {
    final OpenWorkspace? workspace = ref.read(workspaceProvider);
    if (workspace == null || workspace.roots.isEmpty) {
      return;
    }
    final int index = ref.read(tabsProvider).active?.rootIndex ?? 0;
    final LiveRoot root = workspace.rootAt(index) ?? workspace.roots.first;
    await proposeChanges(root.root.rootId, root.root.name, index);
  }

  /// Saves first, after asking, when anything is unsaved: the comparison reads
  /// files from disk, so an unsaved edit would silently be left out.
  Future<void> proposeChanges(
    String folderId,
    String folderName,
    int rootIndex,
  ) async {
    final LiveRoot? root = ref.read(workspaceProvider)?.rootAt(rootIndex);
    if (root == null) {
      return;
    }
    final TabsController tabs = ref.read(tabsProvider.notifier);
    if (ref.read(tabsProvider).anyDirty) {
      final bool save = await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Save your changes first?'),
              content: const Text(
                'Some files have unsaved changes. Only what is saved is '
                'compared and sent.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save all'),
                ),
              ],
            ),
          ) ??
          false;
      if (!save || !mounted) {
        return;
      }
      if (!await tabs.saveAll()) {
        return;
      }
    }
    if (!mounted) {
      return;
    }
    panel.close();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangeRequestScreen(
          provider: root.provider,
          folderId: folderId,
          folderName: folderName,
        ),
      ),
    );
  }
}
