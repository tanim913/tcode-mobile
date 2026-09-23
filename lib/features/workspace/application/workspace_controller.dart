/// The currently open workspace.
///
/// Holds the [Workspace] model together with the live [FileSystemProvider] for
/// each root. A multi-root workspace can mix providers — one root in app
/// storage, another from a SAF grant — so the provider is per root, not global.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/features/workspace/application/recents_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';

/// A workspace root paired with the provider that can read it.
@immutable
class LiveRoot {
  const LiveRoot({required this.root, required this.provider});

  final WorkspaceRoot root;
  final FileSystemProvider provider;
}

@immutable
class OpenWorkspace {
  const OpenWorkspace({required this.workspace, required this.roots});

  final Workspace workspace;
  final List<LiveRoot> roots;

  String get displayName => workspace.displayName;

  bool get isMultiRoot => roots.length > 1;

  LiveRoot? rootAt(int index) =>
      index >= 0 && index < roots.length ? roots[index] : null;
}

class WorkspaceController extends Notifier<OpenWorkspace?> {
  @override
  OpenWorkspace? build() => null;

  /// Opens a folder the user picked, replacing any current workspace.
  ///
  /// Returns false when the picker was dismissed, which is not an error and
  /// should leave the current workspace untouched.
  Future<bool> openPickedFolder() async {
    final PickedRoot? picked = await pickFolder();
    if (picked == null) {
      return false;
    }
    _adopt(picked);
    return true;
  }

  /// Opens the app's own Projects folder.
  ///
  /// This is the one location guaranteed to work on every platform with no
  /// permission at all, which is why it is the default offer on the welcome
  /// screen rather than a fallback.
  Future<void> openProjects() async {
    _adopt(await openProjectsFolder());
  }

  /// Opens a folder the app itself produced, such as a downloaded repository.
  ///
  /// Separate from [openPickedFolder] because there is no picker involved: the
  /// caller already knows the folder it wants opened.
  void openFolder(PickedRoot picked) => _adopt(picked);

  /// Installs a workspace rebuilt from a saved session.
  ///
  /// Separate from [_adopt] because the roots already exist with their own
  /// providers — there is no picker result to derive them from.
  void adoptRestored(Workspace workspace, List<LiveRoot> roots) {
    state = OpenWorkspace(workspace: workspace, roots: roots);
    _remember(workspace);
  }

  void _adopt(PickedRoot picked) {
    final WorkspaceRoot root = WorkspaceRoot(
      providerScheme: picked.provider.schemeId,
      rootId: picked.rootId,
      name: picked.displayName,
      displayPath: picked.rootId,
    );
    final Workspace workspace = Workspace.singleRoot(root);
    state = OpenWorkspace(
      workspace: workspace,
      roots: <LiveRoot>[LiveRoot(root: root, provider: picked.provider)],
    );
    _remember(workspace);
  }

  /// Records the workspace in the recent list, best effort.
  ///
  /// Unawaited on purpose: opening a folder must not wait on a bookkeeping
  /// write, and a failure to remember is not worth telling the user about.
  void _remember(Workspace workspace) {
    unawaited(ref.read(recentsProvider.notifier).recordWorkspace(workspace));
  }

  /// Adds another folder alongside the current roots, making this a multi-root
  /// workspace. Re-adding a root already present is a no-op.
  Future<bool> addFolderToWorkspace() async {
    final OpenWorkspace? current = state;
    if (current == null) {
      return openPickedFolder();
    }
    final PickedRoot? picked = await pickFolder();
    if (picked == null) {
      return false;
    }
    final WorkspaceRoot root = WorkspaceRoot(
      providerScheme: picked.provider.schemeId,
      rootId: picked.rootId,
      name: picked.displayName,
      displayPath: picked.rootId,
    );
    if (current.workspace.roots.contains(root)) {
      return false;
    }
    state = OpenWorkspace(
      workspace: current.workspace.copyWith(
        roots: <WorkspaceRoot>[...current.workspace.roots, root],
      ),
      roots: <LiveRoot>[
        ...current.roots,
        LiveRoot(root: root, provider: picked.provider),
      ],
    );
    return true;
  }

  void removeRoot(int index) {
    final OpenWorkspace? current = state;
    if (current == null || index < 0 || index >= current.roots.length) {
      return;
    }
    final List<LiveRoot> roots = List<LiveRoot>.of(current.roots)..removeAt(index);
    if (roots.isEmpty) {
      state = null;
      return;
    }
    state = OpenWorkspace(
      workspace: current.workspace.copyWith(
        roots: roots.map((LiveRoot r) => r.root).toList(),
      ),
      roots: roots,
    );
  }

  void close() => state = null;
}

final NotifierProvider<WorkspaceController, OpenWorkspace?> workspaceProvider =
    NotifierProvider<WorkspaceController, OpenWorkspace?>(
  WorkspaceController.new,
);

/// Whether this platform can show a folder picker at all.
///
/// False on browsers without the File System Access API, where the welcome
/// screen says so instead of offering a button that cannot work.
final Provider<bool> canPickFolderProvider =
    Provider<bool>((Ref ref) => canPickFolder);

/// Whether a folder picked outside the app sandbox can actually be read and
/// written on this platform today. False on Android until the SAF provider
/// lands, so the welcome screen can explain rather than fail.
final Provider<bool> externalFoldersUsableProvider =
    Provider<bool>((Ref ref) => externalFoldersUsable);
