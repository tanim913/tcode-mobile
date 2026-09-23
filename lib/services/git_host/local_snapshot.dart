/// The blob id of every file in a downloaded folder, as it is now.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_blob_sha.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

/// One file on disk: where it is, and its git blob id.
class LocalFile {
  const LocalFile({required this.id, required this.sha});

  /// The provider's id. Opaque — never parsed.
  final String id;
  final String sha;
}

/// Walks [folderId] and hashes each file, by repository-relative path.
///
/// Walks with hidden files **shown** and **no** exclude patterns: the
/// explorer may hide `.github/` or `build/`, but a file hidden from view is
/// still a file in the repository, and silently leaving it out would make a
/// pull request delete it. Yields to the event loop between files, like the
/// indexer between folders.
Future<Map<String, LocalFile>> hashLocalFiles(
  FileSystemProvider provider,
  String folderId, {
  void Function(int done, int total)? onProgress,
}) async {
  final FileIndex index = await const FileIndexer().build(
    <IndexRoot>[IndexRoot(provider: provider, rootId: folderId, rootIndex: 0)],
    showHidden: true,
    excludePatterns: const <String>[],
  );
  if (index.truncated) {
    throw const UnsupportedOperationFailure(
      what: 'This folder has more files than this app can compare.',
    );
  }
  final List<IndexedFile> files = index.files
      .where((IndexedFile f) => !isRepoMetaPath(f.relativePath))
      .toList();
  final Map<String, LocalFile> hashes = <String, LocalFile>{};
  for (int i = 0; i < files.length; i++) {
    final Uint8List bytes = await provider.readBytes(files[i].node.id);
    hashes[files[i].relativePath] =
        LocalFile(id: files[i].node.id, sha: gitBlobSha(bytes));
    onProgress?.call(i + 1, files.length);
    await Future<void>.delayed(Duration.zero);
  }
  return hashes;
}
