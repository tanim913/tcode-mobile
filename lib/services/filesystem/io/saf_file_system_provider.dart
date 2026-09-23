/// Android external folders, through the Storage Access Framework.
///
/// Ids are `content://` document URIs. They are opaque: nothing outside this
/// file may parse one, which is why [childId] and [parentOf] are the only way
/// to navigate and why [ProviderCapabilities.canResolveAbsolutePath] is false —
/// a SAF document has no path a `dart:io` call could use.
///
/// All of the real work happens in Kotlin, on a background thread. This class
/// is the translation layer: channel maps in, app models out, platform errors
/// turned into the app's own [AppFailure] types so the UI never sees a
/// `PlatformException`.
library;

import 'package:flutter/services.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';

/// A folder the user granted access to, as reported by the platform.
class SafRoot {
  const SafRoot({
    required this.treeUri,
    required this.documentUri,
    required this.name,
  });

  /// Identifies the *grant*. Needed to release it later.
  final String treeUri;

  /// Identifies the folder itself. This is the workspace root id.
  final String documentUri;

  final String name;

  static SafRoot fromMap(Map<Object?, Object?> map) => SafRoot(
        treeUri: map['treeUri']! as String,
        documentUri: map['uri']! as String,
        name: map['name']! as String,
      );
}

class SafChannel {
  const SafChannel([this.channel = const MethodChannel('dev.tcode.mobile/saf')]);

  final MethodChannel channel;

  /// Shows the system folder picker. Null means the user dismissed it, which
  /// is not an error.
  Future<SafRoot?> pickTree() async {
    final Map<Object?, Object?>? result =
        await _invoke<Map<Object?, Object?>>('pickTree');
    return result == null ? null : SafRoot.fromMap(result);
  }

  /// Folders still granted to this app — how a saved session is restored.
  Future<List<SafRoot>> persistedRoots() async {
    final List<Object?> result =
        await _invoke<List<Object?>>('persistedRoots') ?? <Object?>[];
    return result
        .cast<Map<Object?, Object?>>()
        .map(SafRoot.fromMap)
        .toList(growable: false);
  }

  Future<void> releaseRoot(String treeUri) =>
      _invoke<void>('releaseRoot', <String, Object?>{'uri': treeUri});

  Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw _mapError(e, args?['uri'] as String?);
    } on MissingPluginException {
      throw const UnsupportedOperationFailure(
        what: 'This build cannot open folders outside its own storage.',
      );
    }
  }
}

/// Translates a platform error code into the app's sealed failure hierarchy.
///
/// The codes are the ones `SafPlugin` emits; anything unexpected becomes an
/// [UnknownFailure] carrying the original message rather than being swallowed.
AppFailure _mapError(PlatformException e, String? path) {
  return switch (e.code) {
    'permission' => PermissionDeniedFailure(path: path, cause: e),
    'not_found' => NotFoundFailure(path: path, cause: e),
    'busy' => const UnsupportedOperationFailure(
        what: 'A folder picker is already open.',
      ),
    _ => UnknownFailure(
        detail: e.message ?? 'The system storage provider refused.',
        path: path,
        cause: e,
      ),
  };
}

class SafFileSystemProvider implements FileSystemProvider {
  const SafFileSystemProvider({
    this.rootName = 'Folder',
    this.channel = const MethodChannel('dev.tcode.mobile/saf'),
  });

  final String rootName;
  final MethodChannel channel;

  /// Document URIs are `…/tree/<treeId>/document/<documentId>`. Everything
  /// before this marker is the grant and must survive untouched: round-tripping
  /// the whole URI through `Uri.replace` silently rewrites `primary%3ACode` to
  /// `primary:Code`, which is a different document as far as Android cares.
  static const String _documentMarker = '/document/';

  @override
  String get schemeId => 'saf';

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities(
        // SAF has no file-watching API. The explorer must refresh on resume
        // and on pull-to-refresh instead, which is why this is declared rather
        // than faked with polling.
        canWatch: false,
        // A document URI is not a path. Copy Path has nothing honest to copy.
        canResolveAbsolutePath: false,
        // `DocumentsContract` writes in place; there is no rename-into-place
        // trick available, so a failed write can leave a partial file.
        supportsAtomicWrite: false,
        canMoveAcrossFolders: true,
      );

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      throw _mapError(e, (args['uri'] ?? args['parent']) as String?);
    } on MissingPluginException {
      throw const UnsupportedOperationFailure(
        what: 'This build cannot open folders outside its own storage.',
      );
    }
  }

  // --- Reading --------------------------------------------------------------

  @override
  Future<List<FileSystemNode>> list(String folderId) async {
    final List<Object?> rows =
        await _invoke<List<Object?>>('list', <String, Object?>{'uri': folderId}) ??
            <Object?>[];
    return rows
        .cast<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> row) => _node(row, parentId: folderId))
        .toList(growable: false);
  }

  @override
  Future<FileSystemNode> stat(String id) async {
    final Map<Object?, Object?>? row =
        await _invoke<Map<Object?, Object?>>('stat', <String, Object?>{'uri': id});
    if (row == null) {
      throw NotFoundFailure(path: id);
    }
    return _node(row);
  }

  @override
  Future<bool> exists(String id) async =>
      await _invoke<bool>('exists', <String, Object?>{'uri': id}) ?? false;

  @override
  Future<Uint8List> readBytes(String id) async {
    final Uint8List? bytes =
        await _invoke<Uint8List>('readBytes', <String, Object?>{'uri': id});
    if (bytes == null) {
      throw NotFoundFailure(path: id);
    }
    return bytes;
  }

  @override
  Future<TextFileContents> readText(String id, {TextEncoding? encoding}) async {
    final Uint8List bytes = await readBytes(id);
    return TextCodec.decode(bytes, forced: encoding);
  }

  // --- Writing --------------------------------------------------------------

  @override
  Future<void> writeBytes(String id, Uint8List bytes) async {
    await _invoke<void>('writeBytes', <String, Object?>{
      'uri': id,
      'bytes': bytes,
    });
  }

  @override
  Future<void> writeText(String id, String text, TextFormat format) =>
      writeBytes(id, TextCodec.encodeText(text, format));

  // --- Structure ------------------------------------------------------------

  @override
  Future<FileNode> createFile(String parentId, String name) async {
    if (await exists(childId(parentId, name))) {
      throw AlreadyExistsFailure(path: name);
    }
    final String uri = await _invoke<String>('createFile', <String, Object?>{
          'parent': parentId,
          'name': name,
        }) ??
        (throw UnknownFailure(detail: 'Could not create $name', path: name));
    // The provider may have renamed to avoid a clash, so the real name comes
    // back from a stat rather than being assumed.
    final FileSystemNode created = await stat(uri);
    return created as FileNode;
  }

  @override
  Future<FolderNode> createFolder(String parentId, String name) async {
    final String uri = await _invoke<String>('createFolder', <String, Object?>{
          'parent': parentId,
          'name': name,
        }) ??
        (throw UnknownFailure(detail: 'Could not create $name', path: name));
    return await stat(uri) as FolderNode;
  }

  @override
  Future<FileSystemNode> rename(String id, String newName) async {
    final String uri = await _invoke<String>('rename', <String, Object?>{
          'uri': id,
          'name': newName,
        }) ??
        (throw NotFoundFailure(path: id));
    return stat(uri);
  }

  @override
  Future<FileSystemNode> move(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    // `DocumentsContract.moveDocument` exists but is optional: many providers,
    // including several cloud ones, do not implement it. Copy-then-delete is
    // the only move that works everywhere, so it is what this does.
    final FileSystemNode copied = await copy(
      id,
      newParentId,
      newName: newName,
      onProgress: onProgress,
      token: token,
    );
    await delete(id);
    return copied;
  }

  @override
  Future<FileSystemNode> copy(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final FileSystemNode source = await stat(id);
    final String name = newName ?? source.name;

    if (source is FolderNode) {
      final FolderNode folder = await createFolder(newParentId, name);
      for (final FileSystemNode child in await list(id)) {
        token?.throwIfCancelled();
        await copy(child.id, folder.id, onProgress: onProgress, token: token);
      }
      return folder;
    }

    final FileNode created = await createFile(newParentId, name);
    await writeBytes(created.id, await readBytes(id));
    onProgress?.call(
      FileOperationProgress(completed: 1, total: 1, currentPath: name),
    );
    return stat(created.id);
  }

  @override
  Future<void> delete(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    // `deleteDocument` is recursive on the provider side, so no manual walk.
    await _invoke<void>('delete', <String, Object?>{'uri': id});
  }

  // --- Bulk queries ---------------------------------------------------------

  @override
  Future<FolderStats> folderStats(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    int files = 0;
    int folders = 0;
    int bytes = 0;

    Future<void> walk(String folderId) async {
      for (final FileSystemNode node in await list(folderId)) {
        token?.throwIfCancelled();
        if (node is FolderNode) {
          folders++;
          await walk(node.id);
        } else if (node is FileNode) {
          files++;
          bytes += node.size;
        }
        onProgress?.call(
          FileOperationProgress(
            completed: files + folders,
            total: 0,
            currentPath: node.name,
          ),
        );
      }
    }

    await walk(id);
    return FolderStats(
      fileCount: files,
      folderCount: folders,
      totalBytes: bytes,
    );
  }

  // --- Change notification --------------------------------------------------

  @override
  Stream<FileChangeEvent> watch(String folderId) =>
      const Stream<FileChangeEvent>.empty();

  // --- Identity helpers -----------------------------------------------------

  @override
  String childId(String parentId, String name) {
    final int cut = parentId.lastIndexOf(_documentMarker);
    if (cut < 0) {
      return parentId;
    }
    final String prefix = parentId.substring(0, cut + _documentMarker.length);
    final String documentId =
        Uri.decodeComponent(parentId.substring(cut + _documentMarker.length));
    return prefix + Uri.encodeComponent('$documentId/$name');
  }

  @override
  String? parentOf(String id) {
    final int cut = id.lastIndexOf(_documentMarker);
    if (cut < 0) {
      return null;
    }
    final String prefix = id.substring(0, cut + _documentMarker.length);
    final String documentId =
        Uri.decodeComponent(id.substring(cut + _documentMarker.length));
    final int slash = documentId.lastIndexOf('/');
    if (slash <= 0) {
      // Already the granted folder: there is no parent inside the grant, and
      // walking outside it would be a permission the app does not hold.
      return null;
    }
    return prefix + Uri.encodeComponent(documentId.substring(0, slash));
  }

  @override
  String nameOf(String id) {
    final int cut = id.lastIndexOf(_documentMarker);
    if (cut < 0) {
      return rootName;
    }
    final String documentId =
        Uri.decodeComponent(id.substring(cut + _documentMarker.length));
    final int slash = documentId.lastIndexOf('/');
    return slash < 0 ? documentId : documentId.substring(slash + 1);
  }

  FileSystemNode _node(Map<Object?, Object?> row, {String? parentId}) {
    final String uri = row['uri']! as String;
    final String name = row['name']! as String;
    final bool isDirectory = row['isDirectory']! as bool;
    final int modifiedMs = (row['modified'] as int?) ?? 0;
    final DateTime? modified = modifiedMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(modifiedMs)
        : null;

    if (isDirectory) {
      return FolderNode(
        id: uri,
        name: name,
        // SAF has no path to show, so the display path is the name. Saying
        // "content://com.android.externalstorage…" to the user helps nobody.
        displayPath: name,
        parentId: parentId,
        modified: modified,
      );
    }
    return FileNode(
      id: uri,
      name: name,
      displayPath: name,
      parentId: parentId,
      modified: modified,
      size: (row['size'] as int?) ?? 0,
    );
  }
}
