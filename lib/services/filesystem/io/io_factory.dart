/// Native implementation of the provider factory.
///
/// On Android the app-private Projects folder always works with no permission
/// prompt, which is why it is the default workspace location. Folders elsewhere
/// on the device come through the system picker.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pocket_code/core/constants/app_info.dart';
import 'package:pocket_code/core/errors/failures.dart';

import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/io/io_file_system_provider.dart';
import 'package:pocket_code/services/filesystem/io/saf_file_system_provider.dart';
import 'package:pocket_code/services/filesystem/provider_factory_stub.dart'
    show PickedRoot;

export 'package:pocket_code/services/filesystem/provider_factory_stub.dart'
    show PickedRoot;

const IoFileSystemProvider _provider = IoFileSystemProvider();

bool get canPickFolder => true;

/// External folders work on Android through the Storage Access Framework, and
/// on desktop through plain `dart:io`.
bool get externalFoldersUsable => true;

/// Opens the app's Projects folder. Always works, with no permission prompt,
/// because it lives inside the app's own sandbox.
Future<PickedRoot> openProjectsFolder() async {
  final String path = await appProjectsPath();
  return PickedRoot(
    provider: _provider,
    rootId: path,
    displayName: AppInfo.projectsFolderName,
  );
}

/// Absolute path of the app's Projects folder, created on first use.
Future<String> appProjectsPath() async {
  final Directory support = await getApplicationDocumentsDirectory();
  final Directory projects =
      Directory(p.join(support.path, AppInfo.projectsFolderName));
  if (!projects.existsSync()) {
    await projects.create(recursive: true);
  }
  return projects.path;
}

/// App-private support directory. On Android this is internal storage that the
/// user never sees and that no permission gates.
Future<PickedRoot> openSupportStorage() async {
  final Directory support = await getApplicationSupportDirectory();
  if (!support.existsSync()) {
    await support.create(recursive: true);
  }
  return PickedRoot(
    provider: _provider,
    rootId: support.path,
    displayName: 'support',
  );
}

Future<PickedRoot?> pickFolder() async {
  // Android goes through SAF: it is the only route that yields a folder this
  // app can actually read on Android 11+, and the grant survives a reboot.
  if (Platform.isAndroid) {
    final SafRoot? root = await const SafChannel().pickTree();
    if (root == null) {
      return null;
    }
    return PickedRoot(
      provider: SafFileSystemProvider(rootName: root.name),
      rootId: root.documentUri,
      displayName: root.name,
    );
  }

  final String? path = await FilePicker.getDirectoryPath(
    dialogTitle: 'Choose a project folder',
  );
  if (path == null) {
    // User dismissed the picker. Not an error.
    return null;
  }
  if (!Directory(path).existsSync()) {
    throw NotFoundFailure(path: path);
  }
  return PickedRoot(
    provider: _provider,
    rootId: path,
    displayName: p.basename(path),
  );
}

/// Rebuilds a SAF provider for a saved root, if the grant is still held.
///
/// Returns null when the permission was revoked, the storage was unmounted, or
/// the app was reinstalled — all of which must drop the workspace rather than
/// restore one whose every call would fail.
Future<FileSystemProvider?> safProviderForRestore(String rootId) async {
  if (!Platform.isAndroid) {
    return null;
  }
  final List<SafRoot> roots = await const SafChannel().persistedRoots();
  for (final SafRoot root in roots) {
    if (root.documentUri == rootId) {
      return SafFileSystemProvider(rootName: root.name);
    }
  }
  return null;
}
