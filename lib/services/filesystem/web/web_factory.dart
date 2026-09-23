/// Browser implementation of the provider factory.
///
/// App-private storage maps to the Origin Private File System, which is real,
/// persistent, per-origin storage — the browser's equivalent of Android's app
/// sandbox. User-chosen folders come from `showDirectoryPicker()` and are
/// genuinely the folders on their disk.
library;

import 'dart:js_interop';

import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/provider_factory_stub.dart'
    show PickedRoot;
import 'package:pocket_code/services/filesystem/web/fs_interop.dart';
import 'package:pocket_code/services/filesystem/web/web_file_system_provider.dart';
import 'package:web/web.dart' as web;

export 'package:pocket_code/services/filesystem/provider_factory_stub.dart'
    show PickedRoot;

/// The browser's Origin Private File System: real, persistent, per-origin
/// storage that no permission prompt gates. The direct analogue of Android's
/// app-private directory.
Future<PickedRoot> openProjectsFolder() async {
  final web.FileSystemDirectoryHandle root = await getOriginPrivateDirectory();
  return PickedRoot(
    provider: WebFileSystemProvider(
      root: root,
      rootName: AppInfo.projectsFolderName,
    ),
    rootId: '',
    displayName: AppInfo.projectsFolderName,
  );
}

/// Support storage lives in a reserved folder inside the Origin Private File
/// System, so it cannot collide with the user's own project files there.
///
/// The folder name deliberately does NOT follow the app's display name. It is a
/// storage key: renaming it would orphan every existing session and hot-exit
/// backup, since the old folder would simply stop being read. Storage keys are
/// changed only with a migration, never for cosmetics.
Future<PickedRoot> openSupportStorage() async {
  final web.FileSystemDirectoryHandle root = await getOriginPrivateDirectory();
  final web.FileSystemDirectoryHandle support = await root
      .getDirectoryHandle(
        '.pocketcode',
        web.FileSystemGetDirectoryOptions(create: true),
      )
      .toDart;
  return PickedRoot(
    provider: WebFileSystemProvider(root: support, rootName: 'support'),
    rootId: '',
    displayName: 'support',
  );
}

/// The File System Access API grants genuine read/write access to the chosen
/// folder, so external folders work properly here.
bool get externalFoldersUsable => isFileSystemAccessSupported;

/// False on Firefox and Safari, which have not shipped this API. The welcome
/// screen reads this and says so plainly rather than showing a dead button.
bool get canPickFolder => isFileSystemAccessSupported;

Future<PickedRoot?> pickFolder() async {
  if (!isFileSystemAccessSupported) {
    throw const UnsupportedOperationFailure(
      what: 'This browser cannot open local folders. '
          'Chrome or Edge on desktop supports it.',
    );
  }
  final web.FileSystemDirectoryHandle handle;
  try {
    handle = await showDirectoryPicker();
  } on Object {
    // The picker rejects with AbortError when dismissed. Treat as cancelled.
    return null;
  }
  return PickedRoot(
    provider: WebFileSystemProvider(root: handle, rootName: handle.name),
    rootId: '',
    displayName: handle.name,
  );
}

/// Rebuilds a provider for a saved Storage Access Framework root.
///
/// Android-only; every other platform has no SAF grants to restore, so this
/// returns null and the session drops that root rather than half-restoring it.
Future<FileSystemProvider?> safProviderForRestore(String rootId) async => null;
