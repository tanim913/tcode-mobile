/// Assembles the [FileMetadata] the Properties and Folder Details dialogs show.
///
/// Everything expensive is optional and guarded: a folder's size is a recursive
/// walk the provider runs off the UI isolate, and a file's encoding is only
/// known by decoding it, which is not worth doing for a 40 MB blob just to fill
/// in a label.
library;

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/language/language_service.dart';

/// Reads whatever can be known about [node] without blocking the UI.
Future<FileMetadata> describeNode({
  required FileSystemProvider provider,
  required FileSystemNode node,
  LanguageService languages = const LexicalLanguageService(),
  ProgressCallback? onProgress,
  CancellationToken? token,
}) async {
  final bool canResolvePath = provider.capabilities.canResolveAbsolutePath;

  if (node is FolderNode) {
    FolderStats? stats;
    try {
      stats = await provider.folderStats(
        node.id,
        onProgress: onProgress,
        token: token,
      );
    } on AppFailure {
      // A folder that cannot be walked still has a name, a path and a modified
      // time worth showing; the size line just says "unknown".
      stats = null;
    }
    return FileMetadata(
      node: node,
      absolutePath: canResolvePath ? node.displayPath : node.name,
      uri: canResolvePath ? null : node.id,
      sizeBytes: stats?.totalBytes,
      fileCount: stats?.fileCount,
      folderCount: stats?.folderCount,
    );
  }

  final FileNode file = node as FileNode;
  String? encodingLabel;
  String? lineEndingLabel;
  bool? isBinary;

  // Decoding is the only way to learn the encoding and the line ending, so it
  // is done only for files small enough that reading them is cheap.
  if (file.size <= AppLimits.maxSearchableFileBytes) {
    try {
      final TextFileContents contents = await provider.readText(file.id);
      encodingLabel = contents.format.encoding.label;
      lineEndingLabel = contents.format.hasMixedLineEndings
          ? '${contents.format.lineEnding.label} (mixed)'
          : contents.format.lineEnding.label;
      isBinary = false;
    } on EncodingFailure {
      isBinary = true;
    } on AppFailure {
      // Unreadable right now. The rest of the dialog is still useful.
    }
  }

  return FileMetadata(
    node: file,
    absolutePath: canResolvePath ? file.displayPath : file.name,
    uri: canResolvePath ? null : file.id,
    sizeBytes: file.size,
    languageId: languages.detect(file).label,
    encodingLabel: encodingLabel,
    lineEndingLabel: lineEndingLabel,
    isBinary: isBinary,
  );
}

/// Human-readable byte count, e.g. `1.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes bytes';
  }
  const List<String> units = <String>['KB', 'MB', 'GB', 'TB'];
  double value = bytes / 1024;
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} ${units[unit]}';
}
