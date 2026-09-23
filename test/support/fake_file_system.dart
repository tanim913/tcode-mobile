/// An in-memory [FileSystemProvider] for widget tests.
///
/// Backed by the `file` package's [MemoryFileSystem], so the behaviour under
/// test is a real file system implementation rather than a hand-rolled stub
/// that quietly disagrees with the real one.
///
/// This is test-only. The app itself never uses a simulated file system.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file/file.dart' as f;
import 'package:file/memory.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';

class FakeFileSystemProvider implements FileSystemProvider {
  FakeFileSystemProvider() : fs = MemoryFileSystem();

  final MemoryFileSystem fs;

  /// Set to delay every listing, so tests can assert on the loading state.
  Duration listDelay = Duration.zero;

  /// How many listings have happened, for asserting that a burst of watcher
  /// events is coalesced into one re-read.
  int listCalls = 0;

  /// Folder ids that should fail with a permission error.
  final Set<String> denyList = <String>{};

  /// Whether this fake reports a working file watcher, so the tree's
  /// subscription wiring can be exercised. Off by default, matching SAF and
  /// the browser.
  bool canWatch = false;

  final Map<String, StreamController<FileChangeEvent>> _watchers =
      <String, StreamController<FileChangeEvent>>{};

  // ignore: close_sinks
  StreamController<FileChangeEvent> _newWatcher() =>
      StreamController<FileChangeEvent>.broadcast();

  /// Pushes a change event to whoever is watching [folderId].
  void emitChange(String folderId, FileChangeEvent event) {
    _watchers[folderId]?.add(event);
  }

  /// How many folders are currently being watched — the tree must not leak
  /// subscriptions when folders collapse.
  int get watcherCount =>
      _watchers.values.where((StreamController<FileChangeEvent> c) => c.hasListener).length;

  /// Creates a folder tree from `path: contents` pairs. A trailing `/` means a
  /// directory; everything else is a file with the given text.
  void seed(Map<String, String> entries) {
    entries.forEach((String path, String contents) {
      if (path.endsWith('/')) {
        fs.directory(path).createSync(recursive: true);
      } else {
        fs.directory(p.dirname(path)).createSync(recursive: true);
        fs.file(path).writeAsStringSync(contents);
      }
    });
  }

  @override
  String get schemeId => 'fake';

  @override
  ProviderCapabilities get capabilities => ProviderCapabilities(
        canWatch: canWatch,
        canResolveAbsolutePath: true,
        supportsAtomicWrite: true,
        canMoveAcrossFolders: true,
      );

  @override
  Future<List<FileSystemNode>> list(String folderId) async {
    listCalls++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (denyList.contains(folderId)) {
      throw PermissionDeniedFailure(path: folderId);
    }
    final f.Directory dir = fs.directory(folderId);
    if (!dir.existsSync()) {
      throw NotFoundFailure(path: folderId);
    }
    return dir.listSync().map(_toNode).toList();
  }

  FileSystemNode _toNode(f.FileSystemEntity entity) {
    final String path = entity.path;
    final f.FileStat stat = entity.statSync();
    if (stat.type == f.FileSystemEntityType.directory) {
      return FolderNode(
        id: path,
        name: p.basename(path),
        displayPath: path,
        parentId: p.dirname(path),
        modified: stat.modified,
      );
    }
    return FileNode(
      id: path,
      name: p.basename(path),
      displayPath: path,
      parentId: p.dirname(path),
      modified: stat.modified,
      size: stat.size,
    );
  }

  @override
  Future<FileSystemNode> stat(String id) async {
    final f.FileSystemEntityType type = fs.typeSync(id);
    if (type == f.FileSystemEntityType.notFound) {
      throw NotFoundFailure(path: id);
    }
    return _toNode(
      type == f.FileSystemEntityType.directory
          ? fs.directory(id)
          : fs.file(id),
    );
  }

  @override
  Future<bool> exists(String id) async =>
      fs.typeSync(id) != f.FileSystemEntityType.notFound;

  @override
  Future<Uint8List> readBytes(String id) async {
    final f.File file = fs.file(id);
    if (!file.existsSync()) {
      throw NotFoundFailure(path: id);
    }
    return Uint8List.fromList(file.readAsBytesSync());
  }

  @override
  Future<TextFileContents> readText(String id, {TextEncoding? encoding}) async =>
      TextCodec.decode(await readBytes(id), forced: encoding);

  @override
  Future<void> writeBytes(String id, Uint8List bytes) async {
    fs.file(id).writeAsBytesSync(bytes);
  }

  @override
  Future<void> writeText(String id, String text, TextFormat format) async =>
      writeBytes(id, TextCodec.encodeText(text, format));

  @override
  Future<FileNode> createFile(String parentId, String name) async {
    final String path = childId(parentId, name);
    if (await exists(path)) {
      throw AlreadyExistsFailure(path: path);
    }
    fs.file(path).createSync(recursive: true);
    return _toNode(fs.file(path)) as FileNode;
  }

  @override
  Future<FolderNode> createFolder(String parentId, String name) async {
    final String path = childId(parentId, name);
    if (await exists(path)) {
      throw AlreadyExistsFailure(path: path);
    }
    fs.directory(path).createSync(recursive: true);
    return _toNode(fs.directory(path)) as FolderNode;
  }

  @override
  Future<FileSystemNode> rename(String id, String newName) async {
    final String target = childId(p.dirname(id), newName);
    if (await exists(target)) {
      throw AlreadyExistsFailure(path: target);
    }
    if (fs.typeSync(id) == f.FileSystemEntityType.directory) {
      fs.directory(id).renameSync(target);
    } else {
      fs.file(id).renameSync(target);
    }
    return stat(target);
  }

  @override
  Future<FileSystemNode> move(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final String target = childId(newParentId, newName ?? p.basename(id));
    // The real providers report a typed failure here. The fake must too, or
    // tests would pass against behaviour the app never sees.
    if (!await exists(id)) {
      throw NotFoundFailure(path: id);
    }
    if (await exists(target)) {
      throw AlreadyExistsFailure(path: target);
    }
    fs.directory(p.dirname(target)).createSync(recursive: true);
    if (fs.typeSync(id) == f.FileSystemEntityType.directory) {
      fs.directory(id).renameSync(target);
    } else {
      fs.file(id).renameSync(target);
    }
    return stat(target);
  }

  @override
  Future<FileSystemNode> copy(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    final String target = childId(newParentId, newName ?? p.basename(id));
    if (!await exists(id)) {
      throw NotFoundFailure(path: id);
    }
    if (fs.typeSync(id) == f.FileSystemEntityType.directory) {
      fs.directory(target).createSync(recursive: true);
      for (final f.FileSystemEntity entity
          in fs.directory(id).listSync(recursive: true)) {
        final String rel = p.relative(entity.path, from: id);
        final String dest = p.join(target, rel);
        if (entity is f.Directory) {
          fs.directory(dest).createSync(recursive: true);
        } else if (entity is f.File) {
          fs.directory(p.dirname(dest)).createSync(recursive: true);
          fs.file(dest).writeAsBytesSync(entity.readAsBytesSync());
        }
      }
    } else {
      fs.file(id).copySync(target);
    }
    return stat(target);
  }

  @override
  Future<void> delete(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    if (!await exists(id)) {
      throw NotFoundFailure(path: id);
    }
    if (fs.typeSync(id) == f.FileSystemEntityType.directory) {
      fs.directory(id).deleteSync(recursive: true);
    } else {
      fs.file(id).deleteSync();
    }
  }

  @override
  Future<FolderStats> folderStats(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  }) async {
    int files = 0;
    int folders = 0;
    int bytes = 0;
    for (final f.FileSystemEntity entity
        in fs.directory(id).listSync(recursive: true)) {
      if (entity is f.File) {
        files++;
        bytes += entity.lengthSync();
      } else if (entity is f.Directory) {
        folders++;
      }
    }
    return FolderStats(fileCount: files, folderCount: folders, totalBytes: bytes);
  }

  @override
  Stream<FileChangeEvent> watch(String folderId) {
    if (!canWatch) {
      // Matches SAF and the browser: no watcher, and an empty stream rather
      // than a polling loop pretending to be one.
      return const Stream<FileChangeEvent>.empty();
    }
    // The controller is owned by the fake for the life of the test. The tree
    // cancels its *subscription*, which is what `watcherCount` reports and
    // what these tests actually assert on.
    return (_watchers[folderId] ??= _newWatcher()).stream;
  }

  @override
  String childId(String parentId, String name) => p.join(parentId, name);

  @override
  String? parentOf(String id) {
    final String parent = p.dirname(id);
    return parent == id ? null : parent;
  }

  @override
  String nameOf(String id) => p.basename(id);
}
