/// ZIP export and import.
///
/// Pure Dart (`archive`), so it runs unchanged on Android and in the browser
/// and reads and writes only through [FileSystemProvider] — no `dart:io`, no
/// real paths. That is what lets a SAF folder be zipped at all.
///
/// The walk yields to the event loop between entries for the same reason the
/// indexer does: this is the one operation that can touch every file in a
/// workspace, and it must not freeze the UI while it does.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// Refuses an archive that would expand to more than this.
///
/// A zip bomb is a few KB that becomes gigabytes; on a phone that is an
/// out-of-memory crash rather than a mistake the user can undo.
const int kMaxExtractedBytes = 256 * 1024 * 1024;

/// Refuses an archive with more entries than this, for the same reason.
const int kMaxEntries = 20000;

class ZipService {
  const ZipService();

  /// Zips [folderId] and returns the archive bytes.
  ///
  /// Folder entries are written explicitly so an empty folder survives the
  /// round trip; most tools drop them, and a project skeleton is mostly empty
  /// folders.
  Future<Uint8List> export({
    required FileSystemProvider provider,
    required String folderId,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final Archive archive = Archive();
    int done = 0;

    Future<void> walk(String id, String prefix) async {
      final List<FileSystemNode> children = await provider.list(id);
      for (final FileSystemNode node in children) {
        token?.throwIfCancelled();
        final String path = prefix.isEmpty ? node.name : '$prefix/${node.name}';

        if (node is FolderNode) {
          archive.addFile(ArchiveFile.directory('$path/'));
          await walk(node.id, path);
        } else {
          final Uint8List bytes = await provider.readBytes(node.id);
          archive.addFile(ArchiveFile.bytes(path, bytes));
        }
        done++;
        onProgress?.call(
          FileOperationProgress(completed: done, total: 0, currentPath: path),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }

    await walk(folderId, '');

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Extracts [bytes] into [folderId].
  ///
  /// Returns the number of files written. Existing files are **not** silently
  /// replaced: a clashing name throws [AlreadyExistsFailure] so the caller can
  /// ask, because overwriting is not undoable.
  Future<int> import({
    required FileSystemProvider provider,
    required String folderId,
    required Uint8List bytes,
    bool overwrite = false,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    // The signature is checked first because `ZipDecoder` does not throw on
    // arbitrary bytes — it returns an *empty* archive, which would look like a
    // successful import of nothing.
    if (!looksLikeZip(bytes)) {
      throw const UnknownFailure(detail: 'That is not a ZIP file.');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on Object catch (e) {
      throw UnknownFailure(detail: 'That ZIP file could not be read.', cause: e);
    }

    if (archive.files.length > kMaxEntries) {
      throw UnsupportedOperationFailure(
        what: 'That archive has ${archive.files.length} entries, more than '
            'this app will extract at once.',
      );
    }
    final int total = archive.files
        .fold(0, (int sum, ArchiveFile f) => sum + (f.isFile ? f.size : 0));
    if (total > kMaxExtractedBytes) {
      throw const UnsupportedOperationFailure(
        what: 'That archive expands to more than this app will extract at '
            'once. Extract it with a file manager instead.',
      );
    }

    int written = 0;
    for (final ArchiveFile entry in archive.files) {
      token?.throwIfCancelled();
      final String? safe = sanitiseEntryPath(entry.name);
      if (safe == null) {
        // Zip-slip: an entry naming `../` escapes the destination folder and
        // would write anywhere the app can reach. Skipped, never resolved.
        continue;
      }

      final List<String> parts = safe.split('/');
      final String fileName = parts.removeLast();
      String parent = folderId;
      for (final String segment in parts) {
        parent = await _ensureFolder(provider, parent, segment);
      }

      if (entry.isFile) {
        if (fileName.isEmpty) {
          continue;
        }
        final String id = provider.childId(parent, fileName);
        final bool exists = await provider.exists(id);
        if (exists && !overwrite) {
          throw AlreadyExistsFailure(path: safe);
        }
        if (!exists) {
          await provider.createFile(parent, fileName);
        }
        await provider.writeBytes(
          provider.childId(parent, fileName),
          Uint8List.fromList(entry.content as List<int>),
        );
        written++;
      } else if (fileName.isNotEmpty) {
        await _ensureFolder(provider, parent, fileName);
      }

      onProgress?.call(
        FileOperationProgress(
          completed: written,
          total: archive.files.length,
          currentPath: safe,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    return written;
  }

  Future<String> _ensureFolder(
    FileSystemProvider provider,
    String parentId,
    String name,
  ) async {
    final String id = provider.childId(parentId, name);
    if (await provider.exists(id)) {
      return id;
    }
    final FolderNode created = await provider.createFolder(parentId, name);
    return created.id;
  }
}

/// Normalises an archive entry path, or returns null if it escapes.
///
/// Rejects absolute paths, Windows drive letters and any `..` segment. This is
/// the zip-slip guard, and it refuses rather than resolving — an archive that
/// wants to write outside the folder is not one to be clever about.
String? sanitiseEntryPath(String raw) {
  final String normalised = raw.replaceAll('\\', '/');
  if (normalised.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(normalised)) {
    return null;
  }
  final List<String> parts = <String>[];
  for (final String segment in normalised.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      return null;
    }
    parts.add(segment);
  }
  return parts.isEmpty ? null : parts.join('/');
}

/// Whether [bytes] starts with a ZIP local-file or end-of-archive signature.
///
/// `PK\x03\x04` is a normal archive and `PK\x05\x06` an empty one. Checked
/// because the decoder treats unrecognised bytes as an archive with no entries
/// rather than as an error.
bool looksLikeZip(Uint8List bytes) {
  if (bytes.length < 4) {
    return false;
  }
  if (bytes[0] != 0x50 || bytes[1] != 0x4B) {
    return false;
  }
  final int c = bytes[2];
  final int d = bytes[3];
  return (c == 0x03 && d == 0x04) ||
      (c == 0x05 && d == 0x06) ||
      (c == 0x07 && d == 0x08);
}
