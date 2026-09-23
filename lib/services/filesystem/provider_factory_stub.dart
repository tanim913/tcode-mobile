/// Fallback used when neither `dart:io` nor `dart:js_interop` is available.
///
/// Reached only on an unsupported compilation target. It exists so the
/// conditional export in [provider_factory.dart] always has a default branch.
library;

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// Opens the app's own Projects folder, in private storage.
Future<PickedRoot> openProjectsFolder() async {
  throw const UnsupportedOperationFailure(
    what: 'This platform has no supported file system.',
  );
}

/// Prompts the user to choose a folder, returning a provider rooted at it.
///
/// Returns null when the user dismisses the picker.
Future<PickedRoot?> pickFolder() async {
  throw const UnsupportedOperationFailure(
    what: 'Choosing a folder is not supported on this platform.',
  );
}

/// Opens app-private support storage, where the session index, hot-exit
/// backups and the trash live. Never shown to the user.
Future<PickedRoot> openSupportStorage() async {
  throw const UnsupportedOperationFailure(
    what: 'This platform has no supported file system.',
  );
}

/// Whether [pickFolder] can work at all here.
bool get canPickFolder => false;

/// Whether picking a folder outside the app sandbox actually works on this
/// platform right now, as opposed to merely showing a picker.
///
/// False in the stub, which is the platform nobody actually runs on. The io
/// and web factories both override it.
bool get externalFoldersUsable => false;

/// A folder the user chose, plus the provider that can read it.
class PickedRoot {
  const PickedRoot({
    required this.provider,
    required this.rootId,
    required this.displayName,
  });

  final FileSystemProvider provider;

  /// Id of the root within [provider].
  final String rootId;

  /// Folder name shown as the workspace title.
  final String displayName;
}

/// Rebuilds a provider for a saved Storage Access Framework root.
///
/// Android-only; every other platform has no SAF grants to restore, so this
/// returns null and the session drops that root rather than half-restoring it.
Future<FileSystemProvider?> safProviderForRestore(String rootId) async => null;
