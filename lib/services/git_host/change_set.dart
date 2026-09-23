/// What changed in a downloaded folder since it was downloaded. Pure.
///
/// Compares git blob ids: the local file's, computed by `gitBlobSha`, against
/// the one in the host's tree at the base commit.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/data/models/repo_link.dart';

enum ChangeKind {
  added('A', 'Added'),
  modified('M', 'Modified'),
  deleted('D', 'Deleted');

  const ChangeKind(this.letter, this.label);

  final String letter;
  final String label;
}

/// One file in the remote tree at the base commit.
@immutable
class RemoteEntry {
  const RemoteEntry({required this.sha, required this.mode});

  final String sha;

  /// `100644`, or `100755` for an executable. Kept so a modified script stays
  /// executable after the commit.
  final String mode;

  /// A symbolic link. The archive unpacks one as a plain file (or not at all),
  /// so its local form can never be compared, and it is left alone.
  bool get isSymlink => mode == '120000';
}

@immutable
class FileChange {
  const FileChange({required this.path, required this.kind, this.baseSha});

  /// `/`-separated, relative to the repository root.
  final String path;
  final ChangeKind kind;

  /// The blob at the base commit, for showing a diff. Null for an added file.
  final String? baseSha;

  @override
  bool operator ==(Object other) =>
      other is FileChange && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);

  @override
  String toString() => '${kind.letter} $path';
}

/// True for anything this app keeps inside the repository for itself.
bool isRepoMetaPath(String path) =>
    path == kRepoMetaFolder || path.startsWith('$kRepoMetaFolder/');

/// Compares local files against the remote tree.
///
/// * [local] maps each file on disk now to its blob id.
/// * [remote] is the tree at the base commit, files only.
/// * [downloaded] is what the download actually unpacked. A remote file that
///   was never downloaded is not "deleted" just because it is absent here.
///
/// Sorted by path, so the list is stable between runs.
List<FileChange> computeChanges({
  required Map<String, String> local,
  required Map<String, RemoteEntry> remote,
  required Set<String> downloaded,
}) {
  final List<FileChange> changes = <FileChange>[];
  local.forEach((String path, String sha) {
    if (isRepoMetaPath(path)) {
      return;
    }
    final RemoteEntry? base = remote[path];
    if (base != null && base.isSymlink) {
      return;
    }
    if (base == null) {
      changes.add(FileChange(path: path, kind: ChangeKind.added));
    } else if (base.sha != sha) {
      changes.add(
        FileChange(path: path, kind: ChangeKind.modified, baseSha: base.sha),
      );
    }
  });
  remote.forEach((String path, RemoteEntry base) {
    if (!local.containsKey(path) &&
        downloaded.contains(path) &&
        !base.isSymlink &&
        !isRepoMetaPath(path)) {
      changes.add(
        FileChange(path: path, kind: ChangeKind.deleted, baseSha: base.sha),
      );
    }
  });
  changes.sort((FileChange a, FileChange b) => a.path.compareTo(b.path));
  return changes;
}
