/// Typed representation of an entry in a file system.
///
/// The important design decision here is [id]. Different platforms identify a
/// file differently: a `dart:io` path, an Android SAF `content://` URI, or a
/// key into a table of browser directory handles. Features must never assume
/// which. They pass [id] back to the provider that produced it, and only ever
/// show [displayPath] to the user.
library;

import 'package:flutter/foundation.dart';

/// What kind of entry this is. Kept as an enum rather than a bool so the
/// "unknown" case that some providers report is representable.
enum NodeKind { file, folder, link }

@immutable
sealed class FileSystemNode {
  const FileSystemNode({
    required this.id,
    required this.name,
    required this.displayPath,
    this.parentId,
    this.modified,
  });

  /// Opaque, provider-specific. Stable for the lifetime of a workspace session.
  final String id;

  /// Base name including extension, e.g. `main.dart`.
  final String name;

  /// Human-readable location, shown in breadcrumbs and Properties. May be an
  /// absolute path or a URI depending on the provider.
  final String displayPath;

  final String? parentId;
  final DateTime? modified;

  NodeKind get kind;

  /// Lowercase extension without the dot, or empty for files like `Dockerfile`.
  String get extension {
    final int dot = name.lastIndexOf('.');
    // A leading dot means a dotfile (.gitignore), not an extension.
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  /// Name without its extension. `main.dart` -> `main`, `.gitignore` -> `.gitignore`.
  String get baseName {
    final int dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }

  bool get isHidden => name.startsWith('.');

  @override
  bool operator ==(Object other) =>
      other is FileSystemNode && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);

  @override
  String toString() => '$runtimeType($displayPath)';
}

@immutable
class FileNode extends FileSystemNode {
  const FileNode({
    required super.id,
    required super.name,
    required super.displayPath,
    super.parentId,
    super.modified,
    this.size = 0,
  });

  /// Size in bytes. Used for the large-file thresholds and Properties.
  final int size;

  @override
  NodeKind get kind => NodeKind.file;

  FileNode copyWith({String? id, String? name, String? displayPath, String? parentId}) {
    return FileNode(
      id: id ?? this.id,
      name: name ?? this.name,
      displayPath: displayPath ?? this.displayPath,
      parentId: parentId ?? this.parentId,
      modified: modified,
      size: size,
    );
  }
}

@immutable
class FolderNode extends FileSystemNode {
  const FolderNode({
    required super.id,
    required super.name,
    required super.displayPath,
    super.parentId,
    super.modified,
    this.hasChildren,
  });

  /// Whether the folder contains anything. Null when the provider cannot say
  /// cheaply — the tree then shows a chevron optimistically and corrects itself
  /// on expand, which is better than listing 10,000 entries to draw an arrow.
  final bool? hasChildren;

  @override
  NodeKind get kind => NodeKind.folder;

  FolderNode copyWith({String? id, String? name, String? displayPath, String? parentId}) {
    return FolderNode(
      id: id ?? this.id,
      name: name ?? this.name,
      displayPath: displayPath ?? this.displayPath,
      parentId: parentId ?? this.parentId,
      modified: modified,
      hasChildren: hasChildren,
    );
  }
}

/// Everything the Properties dialog shows. Assembled on demand — the expensive
/// parts (folder size, recursive file count) are computed off the UI isolate.
@immutable
class FileMetadata {
  const FileMetadata({
    required this.node,
    required this.absolutePath,
    this.uri,
    this.sizeBytes,
    this.fileCount,
    this.folderCount,
    this.languageId,
    this.encodingLabel,
    this.lineEndingLabel,
    this.isBinary,
  });

  final FileSystemNode node;

  /// Best available absolute path. For SAF entries outside primary storage this
  /// may be unresolvable, in which case [uri] carries the content URI instead.
  final String absolutePath;

  final String? uri;
  final int? sizeBytes;
  final int? fileCount;
  final int? folderCount;
  final String? languageId;
  final String? encodingLabel;
  final String? lineEndingLabel;
  final bool? isBinary;
}
