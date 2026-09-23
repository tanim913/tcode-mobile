/// [FileSystemProvider] backed by the browser's File System Access API.
///
/// This reads and writes **real files on the user's disk** — the folder they
/// pick in `showDirectoryPicker()` is the same folder their other tools see. It
/// is not a simulation, which is what makes Chrome a legitimate development
/// target for an app whose whole point is real file access.
///
/// Ids are POSIX-style paths relative to the workspace root, with `''` meaning
/// the root itself. Handles are resolved by walking the tree from the root and
/// cached, because every resolution is an async round trip.
///
/// Known limitations, all reported honestly through [capabilities]:
///   * No file watching. The API has no change notification at all.
///   * No absolute path. The browser never reveals where the folder really is.
///   * No background isolate. Web workers cannot receive these handles, so
///     recursive work yields to the event loop instead of moving off-thread.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';
import 'package:pocket_code/services/filesystem/web/fs_interop.dart';
import 'package:web/web.dart' as web;

/// Entries processed between yields, mirroring the isolate worker's cadence.
const int _yieldEvery = 32;

class WebFileSystemProvider implements FileSystemProvider {
  /// Private positional constructor so the private fields can use
  /// initializing formals; Dart forbids named parameters starting with `_`.
  WebFileSystemProvider._(this._root, this._rootName);

  factory WebFileSystemProvider({
    required web.FileSystemDirectoryHandle root,
    required String rootName,
  }) =>
      WebFileSystemProvider._(root, rootName);

  final web.FileSystemDirectoryHandle _root;
  final String _rootName;

  /// Resolved directory handles, keyed by id. Bounded in practice by how many
  /// folders the user expands, and cleared when the workspace closes.
  final Map<String, web.FileSystemDirectoryHandle> _dirCache =
      <String, web.FileSystemDirectoryHandle>{};

  @override
  String get schemeId => 'web-fsa';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        // The API offers no change events of any kind.
        canWatch: false,
        // The browser deliberately hides the real location of the folder.
        canResolveAbsolutePath: false,
        // createWritable() buffers to a swap file and commits on close(), so an
        // interrupted write leaves the original intact.
        supportsAtomicWrite: true,
        // There is no standard rename or move; both are copy-then-delete.
        canMoveAcrossFolders: false,
      );

  // --- Reading -------------------------------------------------------------

  @override
  Future<List<FileSystemNode>> list(String folderId) async {
    return _guard(folderId, () async {
      final web.FileSystemDirectoryHandle dir = await _resolveDir(folderId);
      final List<web.FileSystemHandle> handles = await listDirectory(dir);
      return handles
          .map((web.FileSystemHandle h) => _nodeFor(folderId, h))
          .toList();
    });
  }

  @override
  Future<FileSystemNode> stat(String id) async {
    return _guard(id, () async {
      if (id.isEmpty) {
        return FolderNode(id: '', name: _rootName, displayPath: _rootName);
      }
      final String parent = parentOf(id) ?? '';
      final String name = nameOf(id);
      final web.FileSystemDirectoryHandle dir = await _resolveDir(parent);

      // There is no stat(). Ask for it as a file; if that fails with a type
      // mismatch it is a directory.
      try {
        final web.FileSystemFileHandle handle =
            await dir.getFileHandle(name).toDart;
        final web.File file = await handle.getFile().toDart;
        return FileNode(
          id: id,
          name: name,
          displayPath: _display(id),
          parentId: parent,
          size: file.size,
          modified: DateTime.fromMillisecondsSinceEpoch(file.lastModified),
        );
      } on Object {
        await dir.getDirectoryHandle(name).toDart;
        return FolderNode(
          id: id,
          name: name,
          displayPath: _display(id),
          parentId: parent,
        );
      }
    });
  }

  @override
  Future<bool> exists(String id) async {
    try {
      await stat(id);
      return true;
    } on AppFailure {
      return false;
    }
  }

  @override
  Future<Uint8List> readBytes(String id) async {
    return _guard(id, () async {
      final web.FileSystemFileHandle handle = await _resolveFile(id);
      final web.File file = await handle.getFile().toDart;
      final JSArrayBuffer buffer = await file.arrayBuffer().toDart;
      return buffer.toDart.asUint8List();
    });
  }

  @override
  Future<TextFileContents> readText(String id, {TextEncoding? encoding}) async {
    final Uint8List bytes = await readBytes(id);
    return TextCodec.decode(bytes, forced: encoding);
  }

  // --- Writing -------------------------------------------------------------

  @override
  Future<void> writeBytes(String id, Uint8List bytes) async {
    return _guard(id, () async {
      final web.FileSystemFileHandle handle =
          await _resolveFile(id, create: true);
      final web.FileSystemWritableFileStream stream =
          await handle.createWritable().toDart;
      await stream.write(bytes.toJS).toDart;
      // Shrink first: without this, writing a shorter file leaves the old tail.
      await truncateWritable(stream, bytes.length);
      await closeWritable(stream);
    });
  }

  @override
  Future<void> writeText(String id, String text, TextFormat format) {
    return writeBytes(id, TextCodec.encodeText(text, format));
  }

  // --- Structure -----------------------------------------------------------

  @override
  Future<FileNode> createFile(String parentId, String name) async {
    final String id = childId(parentId, name);
    return _guard(id, () async {
      if (await exists(id)) {
        throw AlreadyExistsFailure(path: _display(id));
      }
      final web.FileSystemDirectoryHandle dir = await _resolveDir(parentId);
      await dir.getFileHandle(name, web.FileSystemGetFileOptions(create: true)).toDart;
      return FileNode(
        id: id,
        name: name,
        displayPath: _display(id),
        parentId: parentId,
      );
    });
  }

  @override
  Future<FolderNode> createFolder(String parentId, String name) async {
    final String id = childId(parentId, name);
    return _guard(id, () async {
      if (await exists(id)) {
        throw AlreadyExistsFailure(path: _display(id));
      }
      final web.FileSystemDirectoryHandle dir = await _resolveDir(parentId);
      await dir
          .getDirectoryHandle(name, web.FileSystemGetDirectoryOptions(create: true))
          .toDart;
      return FolderNode(
        id: id,
        name: name,
        displayPath: _display(id),
        parentId: parentId,
      );
    });
  }

  @override
  Future<FileSystemNode> rename(String id, String newName) async {
    // The API has no rename, so this is a copy followed by a delete. Callers
    // see the same result; it is just slower for large folders.
    final String parent = parentOf(id) ?? '';
    final FileSystemNode created = await copy(id, parent, newName: newName);
    await delete(id);
    return created;
  }

  @override
  Future<FileSystemNode> move(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final FileSystemNode created = await copy(
      id,
      newParentId,
      newName: newName,
      onProgress: onProgress,
      token: token,
    );
    await delete(id);
    return created;
  }

  @override
  Future<FileSystemNode> copy(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final String name = newName ?? nameOf(id);
    final String target = childId(newParentId, name);
    _assertNotIntoOwnDescendant(id, newParentId);

    return _guard(id, () async {
      if (await exists(target)) {
        throw AlreadyExistsFailure(path: _display(target));
      }
      final FileSystemNode source = await stat(id);
      if (source is FileNode) {
        await writeBytes(target, await readBytes(id));
        return stat(target);
      }
      await _copyTreeInto(id, target, onProgress, token, _Counter());
      return stat(target);
    });
  }

  @override
  Future<void> delete(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    return _guard(id, () async {
      final String parent = parentOf(id) ?? '';
      final web.FileSystemDirectoryHandle dir = await _resolveDir(parent);
      if (!await exists(id)) {
        throw NotFoundFailure(path: _display(id));
      }
      // recursive: true handles folders in one call, on the browser's side.
      await dir
          .removeEntry(nameOf(id), web.FileSystemRemoveOptions(recursive: true))
          .toDart;
      _invalidate(id);
    });
  }

  @override
  Future<FolderStats> folderStats(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    return _guard(id, () async {
      final FileSystemNode node = await stat(id);
      if (node is FileNode) {
        return FolderStats(fileCount: 1, folderCount: 0, totalBytes: node.size);
      }
      final _Counter counter = _Counter();
      await _walk(id, onProgress, token, counter);
      return FolderStats(
        fileCount: counter.files,
        folderCount: counter.folders,
        totalBytes: counter.bytes,
      );
    });
  }

  // --- Watching ------------------------------------------------------------

  @override
  Stream<FileChangeEvent> watch(String folderId) {
    // No change notification exists in this API. An empty stream is the honest
    // answer; the explorer refreshes on resume and pull-to-refresh instead.
    return const Stream<FileChangeEvent>.empty();
  }

  // --- Identity ------------------------------------------------------------

  @override
  String childId(String parentId, String name) =>
      parentId.isEmpty ? name : '$parentId/$name';

  @override
  String? parentOf(String id) {
    if (id.isEmpty) {
      return null;
    }
    final int slash = id.lastIndexOf('/');
    return slash < 0 ? '' : id.substring(0, slash);
  }

  @override
  String nameOf(String id) {
    if (id.isEmpty) {
      return _rootName;
    }
    final int slash = id.lastIndexOf('/');
    return slash < 0 ? id : id.substring(slash + 1);
  }

  // --- internals -----------------------------------------------------------

  String _display(String id) => id.isEmpty ? _rootName : '$_rootName/$id';

  FileSystemNode _nodeFor(String parentId, web.FileSystemHandle handle) {
    final String name = handle.name;
    final String id = childId(parentId, name);
    if (handle.kind == 'directory') {
      return FolderNode(
        id: id,
        name: name,
        displayPath: _display(id),
        parentId: parentId,
      );
    }
    // Size is deliberately not fetched here: it costs one extra async call per
    // entry, which on a 10,000-entry folder is 10,000 round trips. stat() and
    // the Properties dialog fetch it on demand instead.
    return FileNode(
      id: id,
      name: name,
      displayPath: _display(id),
      parentId: parentId,
    );
  }

  Future<web.FileSystemDirectoryHandle> _resolveDir(String id) async {
    if (id.isEmpty) {
      return _root;
    }
    final web.FileSystemDirectoryHandle? cached = _dirCache[id];
    if (cached != null) {
      return cached;
    }
    web.FileSystemDirectoryHandle current = _root;
    final List<String> segments = id.split('/');
    String walked = '';
    for (final String segment in segments) {
      current = await current.getDirectoryHandle(segment).toDart;
      walked = walked.isEmpty ? segment : '$walked/$segment';
      _dirCache[walked] = current;
    }
    return current;
  }

  Future<web.FileSystemFileHandle> _resolveFile(
    String id, {
    bool create = false,
  }) async {
    final web.FileSystemDirectoryHandle dir = await _resolveDir(parentOf(id) ?? '');
    return dir
        .getFileHandle(nameOf(id), web.FileSystemGetFileOptions(create: create))
        .toDart;
  }

  /// Drops cached handles for [id] and anything beneath it.
  void _invalidate(String id) {
    _dirCache.remove(id);
    _dirCache.removeWhere((String key, _) => key.startsWith('$id/'));
  }

  void _assertNotIntoOwnDescendant(String sourceId, String destinationParentId) {
    if (destinationParentId == sourceId ||
        destinationParentId.startsWith('$sourceId/')) {
      throw const UnsupportedOperationFailure(
        what: 'A folder cannot be moved or copied into itself.',
      );
    }
  }

  Future<void> _copyTreeInto(
    String sourceId,
    String targetId,
    ProgressCallback? onProgress,
    CancellationToken? token,
    _Counter counter,
  ) async {
    await createFolder(parentOf(targetId) ?? '', nameOf(targetId));
    for (final FileSystemNode child in await list(sourceId)) {
      token?.throwIfCancelled(path: child.displayPath);
      final String childTarget = childId(targetId, child.name);
      if (child is FileNode) {
        await writeBytes(childTarget, await readBytes(child.id));
      } else {
        await _copyTreeInto(child.id, childTarget, onProgress, token, counter);
      }
      if (++counter.seen % _yieldEvery == 0) {
        onProgress?.call(
          FileOperationProgress(
            completed: counter.seen,
            total: 0,
            currentPath: child.displayPath,
          ),
        );
        // Hand a frame back to the browser so the progress dialog can paint.
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  Future<void> _walk(
    String id,
    ProgressCallback? onProgress,
    CancellationToken? token,
    _Counter counter,
  ) async {
    for (final FileSystemNode child in await list(id)) {
      token?.throwIfCancelled(path: child.displayPath);
      if (child is FolderNode) {
        counter.folders++;
        await _walk(child.id, onProgress, token, counter);
      } else {
        counter.files++;
        final FileSystemNode full = await stat(child.id);
        if (full is FileNode) {
          counter.bytes += full.size;
        }
      }
      if (++counter.seen % _yieldEvery == 0) {
        onProgress?.call(
          FileOperationProgress(
            completed: counter.seen,
            total: 0,
            currentPath: child.displayPath,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// Converts a browser DOMException into a typed failure.
  ///
  /// The API signals everything through exception *names*, so this reads the
  /// name off the JS error rather than matching on message text.
  Future<T> _guard<T>(String id, Future<T> Function() body) async {
    try {
      return await body();
    } on AppFailure {
      rethrow;
    } on Object catch (e) {
      final String name = _errorName(e);
      final String shown = _display(id);
      throw switch (name) {
        'NotFoundError' => NotFoundFailure(path: shown, cause: e),
        'NotAllowedError' ||
        'SecurityError' =>
          PermissionDeniedFailure(path: shown, cause: e),
        'QuotaExceededError' => StorageFullFailure(path: shown, cause: e),
        'TypeMismatchError' => NotFoundFailure(path: shown, cause: e),
        'InvalidModificationError' =>
          AlreadyExistsFailure(path: shown, cause: e),
        'AbortError' => CancelledFailure(path: shown),
        _ => UnknownFailure(detail: e.toString(), path: shown, cause: e),
      };
    }
  }

  String _errorName(Object error) {
    // The lint below warns that `is JSObject` may behave differently across
    // compilers. This file only ever compiles for web, where the check is
    // well-defined, and reading DOMException.name is the only reliable way to
    // tell "file missing" from "permission refused" in this API.
    // ignore: invalid_runtime_check_with_js_interop_types
    if (error is! JSObject) {
      return '';
    }
    final JSObject js = error;
    if (!js.has('name')) {
      return '';
    }
    return js.getProperty<JSString>('name'.toJS).toDart;
  }
}

/// Mutable counters threaded through the recursive walks.
class _Counter {
  int seen = 0;
  int files = 0;
  int folders = 0;
  int bytes = 0;
}
