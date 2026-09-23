/// Rebuilding a live provider for a saved workspace root.
///
/// Shared by session restore and the recent list, which both take a root that
/// was written to disk some time ago and have to decide whether it can still be
/// reached. Keeping one implementation means the two can never disagree about
/// whether a folder is available.
library;

import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';

/// A provider that can read [root], or null when it can no longer be reached.
Future<FileSystemProvider?> providerForRoot(WorkspaceRoot root) async {
  switch (root.providerScheme) {
    case 'io':
    case 'web-fsa':
      // Both are reachable without a new user gesture: `io` because the path is
      // inside app storage, `web-fsa` because the OPFS handle is ours.
      return (await openProjectsFolder()).provider;
    case 'saf':
      // The SAF grant was taken persistably, so it survives a reboot — but only
      // if it is still listed. A revoked or unmounted folder returns null, and
      // the caller treats the root as unavailable rather than half-restoring it.
      return safProviderForRestore(root.rootId);
    default:
      return null;
  }
}
