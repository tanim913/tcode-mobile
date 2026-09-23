/// Reading and writing the snapshot store.
///
/// Layout, under the app's private support directory:
///
/// ```
/// .history/<hash of key>/meta.json
/// .history/<hash of key>/<microseconds>.snap
/// ```
///
/// A folder per file, so eviction for one file is a scoped delete and a rename
/// is a single folder move. `meta.json` carries the full key, which is what
/// turns a hash collision from a silent mixing of two files' history into a
/// handled case.
///
/// Snapshots are written as plain UTF-8 with `\n` endings, like the hot-exit
/// backups. This is a *content* archive, not a byte-for-byte one: restoring
/// puts text into the buffer and the next save reapplies the file's real
/// `TextFormat`, so a CRLF file stays CRLF.
library;

import 'dart:convert';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/file_version.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/features/history/application/history_key.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// A history folder, resolved and confirmed to belong to one key.
class HistoryFolder {
  const HistoryFolder({required this.id, required this.meta});

  final String id;
  final FileHistoryMeta meta;
}

class HistoryRepository {
  const HistoryRepository(this._storage);

  static const String folderName = '.history';
  static const String metaFile = 'meta.json';

  /// Suffixes tried when a folder's key does not match, before giving up.
  static const int _collisionAttempts = 4;

  final SupportStorage _storage;

  FileSystemProvider get _provider => _storage.provider;

  Future<String> _rootId() => _storage.ensureFolder(folderName);

  /// The folder for [key], creating it if [create] is set.
  ///
  /// Walks past a folder whose stored key is a different file — that is the
  /// hash collision case, and it costs one comparison to handle correctly.
  Future<HistoryFolder?> folderFor(
    String key, {
    required String name,
    required String displayPath,
    bool create = false,
  }) async {
    final String root = await _rootId();
    final String base = historyFolderFor(key);

    for (int attempt = 0; attempt < _collisionAttempts; attempt++) {
      final String folder = attempt == 0 ? base : '$base-$attempt';
      final String id = _provider.childId(root, folder);

      if (!await _provider.exists(id)) {
        if (!create) {
          return null;
        }
        await _provider.createFolder(root, folder);
        final FileHistoryMeta meta = FileHistoryMeta(
          key: key,
          name: name,
          displayPath: displayPath,
        );
        await _writeMeta(id, meta);
        return HistoryFolder(id: id, meta: meta);
      }

      final FileHistoryMeta? meta = await _readMeta(id);
      if (meta == null) {
        // Unreadable metadata: treat the folder as this file's and rebuild it
        // rather than orphaning the snapshots inside.
        if (!create) {
          return null;
        }
        final FileHistoryMeta fresh = FileHistoryMeta(
          key: key,
          name: name,
          displayPath: displayPath,
        );
        await _writeMeta(id, fresh);
        return HistoryFolder(id: id, meta: fresh);
      }
      if (meta.key == key) {
        return HistoryFolder(id: id, meta: meta);
      }
      // Someone else's folder. Try the next suffix.
    }
    return null;
  }

  Future<FileHistoryMeta?> _readMeta(String folderId) async {
    final String? text =
        await _storage.readTextFile(_provider.childId(folderId, metaFile));
    if (text == null) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(text) as Object?;
      return decoded is Map<String, Object?>
          ? FileHistoryMeta.fromJson(decoded)
          : null;
    } on Object {
      return null;
    }
  }


  Future<void> _writeMeta(String folderId, FileHistoryMeta meta) =>
      _storage.writeTextFile(
        _provider.childId(folderId, metaFile),
        const JsonEncoder.withIndent('  ').convert(meta.toJson()),
      );

  /// Records [text] as a version of the file at [key].
  Future<FileHistoryMeta> addVersion({
    required String key,
    required String name,
    required String displayPath,
    required String text,
    required String contentHash,
    required DateTime savedAt,
  }) async {
    final HistoryFolder? folder = await folderFor(
      key,
      name: name,
      displayPath: displayPath,
      create: true,
    );
    if (folder == null) {
      return FileHistoryMeta(key: key, name: name, displayPath: displayPath);
    }

    final FileVersion version = FileVersion(
      stamp: savedAt.microsecondsSinceEpoch,
      savedAt: savedAt,
      byteLength: text.length,
      contentHash: contentHash,
    );
    await _storage.writeTextFile(
      _provider.childId(folder.id, version.fileName),
      text,
    );

    final FileHistoryMeta updated = folder.meta.copyWith(
      name: name,
      displayPath: displayPath,
      versions: <FileVersion>[version, ...folder.meta.versions],
    );
    await _writeMeta(folder.id, updated);
    return updated;
  }

  /// The text of one version, or null if it is gone.
  Future<String?> contentOf(String folderId, FileVersion version) =>
      _storage.readTextFile(_provider.childId(folderId, version.fileName));

  /// Deletes [versions] and rewrites the index without them.
  Future<void> removeVersions(
    HistoryFolder folder,
    List<FileVersion> versions,
  ) async {
    if (versions.isEmpty) {
      return;
    }
    final Set<int> doomed = versions.map((FileVersion v) => v.stamp).toSet();
    for (final FileVersion version in versions) {
      await _storage.deleteQuietly(
        _provider.childId(folder.id, version.fileName),
      );
    }
    await _writeMeta(
      folder.id,
      folder.meta.copyWith(
        versions: folder.meta.versions
            .where((FileVersion v) => !doomed.contains(v.stamp))
            .toList(),
      ),
    );
  }

  /// Moves a file's history to a new key after a rename.
  ///
  /// A failure leaves the history orphaned rather than destroyed, which is the
  /// right way round: the space is reclaimed by the age limit, and nothing the
  /// user recorded is thrown away because a rename went wrong.
  Future<void> rename({
    required String oldKey,
    required String newKey,
    required String name,
    required String displayPath,
  }) async {
    if (oldKey == newKey) {
      return;
    }
    final HistoryFolder? folder =
        await folderFor(oldKey, name: name, displayPath: displayPath);
    if (folder == null) {
      return;
    }
    try {
      await _provider.rename(folder.id, historyFolderFor(newKey));
      final String root = await _rootId();
      await _writeMeta(
        _provider.childId(root, historyFolderFor(newKey)),
        folder.meta.copyWith(
          key: newKey,
          name: name,
          displayPath: displayPath,
        ),
      );
    } on AppFailure {
      // Orphaned, not lost. "Clear history" and the age limit both reclaim it.
    }
  }

  Future<void> deleteFolder(String folderId) =>
      _storage.deleteQuietly(folderId);

  /// Every history folder, for the sweep and for the settings total.
  Future<List<HistoryFolder>> allFolders() async {
    final String root = await _rootId();
    final List<HistoryFolder> folders = <HistoryFolder>[];
    try {
      for (final FileSystemNode node in await _provider.list(root)) {
        if (node is! FolderNode) {
          continue;
        }
        final FileHistoryMeta? meta = await _readMeta(node.id);
        if (meta != null) {
          folders.add(HistoryFolder(id: node.id, meta: meta));
        }
      }
    } on AppFailure {
      return folders;
    }
    return folders;
  }

  Future<void> clearAll() async {
    for (final HistoryFolder folder in await allFolders()) {
      await _storage.deleteQuietly(folder.id);
    }
  }
}
