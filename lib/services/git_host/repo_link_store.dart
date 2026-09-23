/// Reading and writing `.tcode/repo.json` and `.tcode/files` in a folder.
///
/// Every read is null-tolerant: a missing, unreadable or hand-edited link just
/// means the folder is not a downloaded repository as far as the app knows.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

class RepoLinkStore {
  const RepoLinkStore(this.provider);

  final FileSystemProvider provider;

  String _meta(String folderId) => provider.childId(folderId, kRepoMetaFolder);

  /// Cheap enough to call when a context menu opens: one existence check.
  Future<bool> hasLink(String folderId) async {
    try {
      return await provider
          .exists(provider.childId(_meta(folderId), kRepoLinkFile));
    } on AppFailure {
      return false;
    }
  }

  Future<RepoLink?> read(String folderId) async {
    try {
      final Uint8List bytes = await provider
          .readBytes(provider.childId(_meta(folderId), kRepoLinkFile));
      return RepoLink.decode(utf8.decode(bytes, allowMalformed: true));
    } on AppFailure {
      return null;
    }
  }

  /// The files the download unpacked, or an empty set when the list is
  /// missing — then nothing is ever reported deleted, which is the safe way
  /// to be wrong.
  Future<Set<String>> downloadedFiles(String folderId) async {
    try {
      final Uint8List bytes = await provider
          .readBytes(provider.childId(_meta(folderId), kRepoFilesList));
      return const LineSplitter()
          .convert(utf8.decode(bytes, allowMalformed: true))
          .where((String line) => line.isNotEmpty)
          .toSet();
    } on AppFailure {
      return <String>{};
    }
  }

  /// Records [link] and the current file list of [folderId].
  Future<void> write(String folderId, RepoLink link) async {
    final String meta = _meta(folderId);
    if (!await provider.exists(meta)) {
      await provider.createFolder(folderId, kRepoMetaFolder);
    }
    final FileIndex index = await const FileIndexer().build(
      <IndexRoot>[
        IndexRoot(provider: provider, rootId: folderId, rootIndex: 0),
      ],
      showHidden: true,
      excludePatterns: const <String>[],
    );
    final String files = index.files
        .map((IndexedFile f) => f.relativePath)
        .where((String path) => !path.startsWith('$kRepoMetaFolder/'))
        .join('\n');
    await _put(meta, kRepoLinkFile, link.encode());
    await _put(meta, kRepoFilesList, files);
  }

  Future<void> _put(String folderId, String name, String text) async {
    final String id = provider.childId(folderId, name);
    if (!await provider.exists(id)) {
      final FileNode created = await provider.createFile(folderId, name);
      await provider.writeBytes(
        created.id,
        Uint8List.fromList(utf8.encode(text)),
      );
      return;
    }
    await provider.writeBytes(id, Uint8List.fromList(utf8.encode(text)));
  }
}
