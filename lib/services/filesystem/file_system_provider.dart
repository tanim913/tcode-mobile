/// The single abstraction over every way this app can reach a file.
///
/// Nothing in `features/` imports `dart:io`, a `MethodChannel`, or
/// `dart:js_interop`. They all talk to this interface, which is what makes the
/// same explorer and editor work against app-private storage, an Android SAF
/// tree, and a browser directory handle without knowing the difference.
///
/// Implementations throw [AppFailure] subtypes and nothing else. Every caller
/// can therefore render an error without a `catch (e)` that guesses.
library;

import 'dart:typed_data';

import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';

/// What a given provider can actually do.
///
/// The UI reads these to disable or hide actions honestly, rather than offering
/// a button that fails. SAF, for example, has no usable file watcher.
class ProviderCapabilities {
  const ProviderCapabilities({
    required this.canWatch,
    required this.canResolveAbsolutePath,
    required this.supportsAtomicWrite,
    required this.canMoveAcrossFolders,
  });

  /// Whether [FileSystemProvider.watch] emits anything.
  final bool canWatch;

  /// Whether Copy Path can produce a real filesystem path rather than a URI.
  final bool canResolveAbsolutePath;

  /// Whether writes go via a temp file and rename. When false, a write is
  /// in-place and an interrupted save can truncate the file — the UI keeps the
  /// hot-exit backup around longer in that case.
  final bool supportsAtomicWrite;

  /// Whether a move can be done as a rename rather than copy-then-delete.
  final bool canMoveAcrossFolders;
}

/// Emitted by [FileSystemProvider.watch].
enum FileChangeKind { created, modified, deleted, moved }

class FileChangeEvent {
  const FileChangeEvent({required this.kind, required this.id, this.newId});

  final FileChangeKind kind;
  final String id;

  /// Set only for [FileChangeKind.moved].
  final String? newId;
}

/// Result of reading a text file: the content plus the physical format it was
/// stored in, so a later write can reproduce it byte-for-byte.
class TextFileContents {
  const TextFileContents({required this.text, required this.format});

  final String text;
  final TextFormat format;
}

abstract interface class FileSystemProvider {
  /// Stable identifier for this provider kind, persisted with workspace roots
  /// so a session restore knows which provider to ask.
  String get schemeId;

  ProviderCapabilities get capabilities;

  // --- Reading -------------------------------------------------------------

  /// Direct children only. Never recursive — the tree loads lazily on expand.
  Future<List<FileSystemNode>> list(String folderId);

  /// Metadata for a single entry, or throws [NotFoundFailure].
  Future<FileSystemNode> stat(String id);

  Future<bool> exists(String id);

  Future<Uint8List> readBytes(String id);

  /// Reads and decodes. When [encoding] is null the implementation detects it
  /// from the byte-order mark and content, and reports what it found in the
  /// returned [TextFormat].
  Future<TextFileContents> readText(String id, {TextEncoding? encoding});

  // --- Writing -------------------------------------------------------------

  /// Writes bytes, atomically where [ProviderCapabilities.supportsAtomicWrite].
  Future<void> writeBytes(String id, Uint8List bytes);

  /// Encodes [text] using [format] — reapplying the original encoding, BOM,
  /// line endings and final-newline state — then writes it.
  Future<void> writeText(String id, String text, TextFormat format);

  // --- Structure -----------------------------------------------------------

  /// Creates an empty file and returns it. Throws [AlreadyExistsFailure]
  /// rather than truncating, which would destroy data.
  Future<FileNode> createFile(String parentId, String name);

  Future<FolderNode> createFolder(String parentId, String name);

  /// Renames in place. [newName] is a base name, not a path.
  Future<FileSystemNode> rename(String id, String newName);

  /// Moves into [newParentId], keeping the name unless [newName] is given.
  Future<FileSystemNode> move(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  /// Recursive for folders. Runs off the UI isolate in implementations where
  /// the work is Dart-side.
  Future<FileSystemNode> copy(
    String id,
    String newParentId, {
    String? newName,
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  /// Recursive for folders. Callers that want undo move to trash instead.
  Future<void> delete(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  // --- Bulk queries --------------------------------------------------------

  /// Recursive size and entry count, for the delete confirmation and the
  /// Properties dialog. Cancellable because a deep tree can take seconds.
  Future<FolderStats> folderStats(
    String id, {
    ProgressCallback? onProgress,
    CancellationToken? token,
  });

  // --- Change notification -------------------------------------------------

  /// Emits nothing when [ProviderCapabilities.canWatch] is false. Callers must
  /// still refresh on resume and pull-to-refresh regardless.
  Stream<FileChangeEvent> watch(String folderId);

  // --- Identity helpers ----------------------------------------------------

  /// Joins a child name onto a folder id, in whatever form this provider uses.
  String childId(String parentId, String name);

  /// The id of the containing folder, or null for a root.
  String? parentOf(String id);

  /// Display name of an entry without listing its parent.
  String nameOf(String id);
}

class FolderStats {
  const FolderStats({
    required this.fileCount,
    required this.folderCount,
    required this.totalBytes,
  });

  final int fileCount;
  final int folderCount;
  final int totalBytes;
}
