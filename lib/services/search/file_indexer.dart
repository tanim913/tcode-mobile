/// Walks a workspace to build the flat file list Quick Open searches.
///
/// Deliberately not an isolate. The work is almost entirely awaiting
/// [FileSystemProvider.list], which is already off the UI thread on every
/// provider; the walk yields to the event loop between folders so a large tree
/// cannot jank typing. That also keeps it working on web, where the browser
/// provider cannot be handed to an isolate at all.
///
/// It reuses the explorer's own [TreeOrdering.filter], so Quick Open hides
/// exactly what the tree hides — a file you cannot see in the explorer must not
/// appear here either.
library;

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// One file in the index.
class IndexedFile {
  const IndexedFile({
    required this.node,
    required this.rootIndex,
    required this.relativePath,
  });

  final FileNode node;
  final int rootIndex;

  /// Path below the workspace root, `/`-separated, used for display and as the
  /// fuzzy-match candidate. The basename carries most of the signal, which is
  /// why `FuzzyMatcher` scores it separately.
  final String relativePath;

  String get name => node.name;
}

/// The result of a walk, including whether it was cut short.
class FileIndex {
  const FileIndex({required this.files, required this.truncated});

  const FileIndex.empty() : files = const <IndexedFile>[], truncated = false;

  final List<IndexedFile> files;

  /// True when [FileIndexer.fileLimit] was reached. The UI must say so: a
  /// silently partial list is a list that lies about what the workspace holds.
  final bool truncated;
}

/// One root to walk.
class IndexRoot {
  const IndexRoot({
    required this.provider,
    required this.rootId,
    required this.rootIndex,
    String? startId,
    this.startPath = '',
  }) : startId = startId ?? rootId;

  final FileSystemProvider provider;
  final String rootId;
  final int rootIndex;

  /// Where the walk begins — the root itself, or a folder inside it for
  /// Find in Folder.
  ///
  /// Scoping at the walk rather than filtering the results afterwards is both
  /// exact and cheaper: only the chosen subtree is ever listed.
  final String startId;

  /// The `/`-separated path of [startId] below the root, `''` for the root.
  ///
  /// Seeded into the walk so every `IndexedFile.relativePath` stays relative
  /// to the **workspace root**, and a scoped result displays and opens exactly
  /// like an unscoped one.
  final String startPath;
}

class FileIndexer {
  const FileIndexer({
    this.fileLimit = 20000,
    this.folderDepthLimit = 24,
  });

  /// Stops the walk rather than letting a pathological tree exhaust memory.
  /// 20k files is far past what a phone workspace holds and still cheap.
  final int fileLimit;

  /// Guards against symlink loops, which `list` will happily follow forever.
  final int folderDepthLimit;

  /// Walks every root breadth-first and returns the files found.
  ///
  /// A folder that cannot be read is skipped rather than aborting the walk:
  /// one unreadable directory must not cost the user every other result.
  Future<FileIndex> build(
    List<IndexRoot> roots, {
    required bool showHidden,
    required List<String> excludePatterns,
  }) async {
    final List<IndexedFile> files = <IndexedFile>[];
    bool truncated = false;

    for (final IndexRoot root in roots) {
      if (truncated) {
        break;
      }
      // Breadth-first so the shallow files — the ones people actually open —
      // are indexed first if the limit cuts the walk short.
      final List<({String id, String path, int depth})> queue =
          <({String id, String path, int depth})>[
        (id: root.startId, path: root.startPath, depth: 0),
      ];

      while (queue.isNotEmpty) {
        final ({String id, String path, int depth}) folder = queue.removeAt(0);
        if (folder.depth > folderDepthLimit) {
          continue;
        }

        final List<FileSystemNode> children;
        try {
          children = await root.provider.list(folder.id);
        } on AppFailure {
          continue;
        }

        final List<FileSystemNode> visible = TreeOrdering.filter(
          children,
          showHidden: showHidden,
          excludePatterns: excludePatterns,
        );

        for (final FileSystemNode node in visible) {
          final String path =
              folder.path.isEmpty ? node.name : '${folder.path}/${node.name}';
          if (node is FolderNode) {
            queue.add((id: node.id, path: path, depth: folder.depth + 1));
          } else if (node is FileNode) {
            if (files.length >= fileLimit) {
              truncated = true;
              break;
            }
            files.add(
              IndexedFile(
                node: node,
                rootIndex: root.rootIndex,
                relativePath: path,
              ),
            );
          }
        }
        if (truncated) {
          break;
        }
        // One yield per folder: enough to keep the field responsive while
        // typing, cheap enough not to stretch the walk out.
        await Future<void>.delayed(Duration.zero);
      }
    }

    return FileIndex(files: files, truncated: truncated);
  }
}
