/// State for the explorer tree.
///
/// The performance requirement shapes the whole design: a folder with 10,000
/// entries must expand without a visible pause. That rules out nesting widgets
/// inside widgets, because Flutter would build every level. Instead the tree is
/// **flattened** into a single list of [TreeRow]s, rendered by a
/// `ListView.builder` with a fixed `itemExtent` — so only the ~20 rows on
/// screen ever exist as widgets, no matter how large the folder.
///
/// Children are loaded lazily, once, on first expand and cached until a
/// refresh.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';

/// One visible line in the flattened tree.
@immutable
class TreeRow {
  const TreeRow({
    required this.node,
    required this.depth,
    required this.rootIndex,
    this.isExpanded = false,
    this.isLoading = false,
    this.isRootHeader = false,
  });

  final FileSystemNode node;

  /// Nesting level, used for the indent and the indent guides. Roots are 0.
  final int depth;

  /// Which workspace root this row belongs to, so a multi-root workspace can
  /// address the right provider.
  final int rootIndex;

  final bool isExpanded;

  /// True while this folder's children are being fetched and the fetch has
  /// already taken longer than the spinner threshold.
  final bool isLoading;

  /// A top-level collapsible section header in a multi-root workspace.
  final bool isRootHeader;

  bool get isFolder => node is FolderNode;

  /// Stable key for widget identity and for the expanded set.
  String get key => '$rootIndex:${node.id}';
}

/// Immutable snapshot the tree widget renders.
@immutable
class TreeState {
  const TreeState({
    this.rows = const <TreeRow>[],
    this.expanded = const <String>{},
    this.loading = const <String>{},
    this.activeFileId,
    this.error,
  });

  final List<TreeRow> rows;

  /// Keys (`rootIndex:nodeId`) of folders the user has opened.
  final Set<String> expanded;

  final Set<String> loading;

  /// The file currently open in the editor, highlighted in the tree.
  final String? activeFileId;

  /// Set when the last operation failed, so the panel can show it inline
  /// instead of a snackbar that scrolls away.
  final String? error;

  TreeState copyWith({
    List<TreeRow>? rows,
    Set<String>? expanded,
    Set<String>? loading,
    String? activeFileId,
    String? error,
    bool clearError = false,
  }) {
    return TreeState(
      rows: rows ?? this.rows,
      expanded: expanded ?? this.expanded,
      loading: loading ?? this.loading,
      activeFileId: activeFileId ?? this.activeFileId,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Sorting and filtering rules applied to a folder's children.
///
/// Pure functions, kept apart from the async loading so they can be unit
/// tested without any file system at all.
abstract final class TreeOrdering {
  /// Folders always come first, then the chosen sort, then a natural,
  /// case-insensitive name comparison as the tie-breaker.
  static List<FileSystemNode> sort(
    List<FileSystemNode> nodes,
    ExplorerSortOrder order,
  ) {
    final List<FileSystemNode> copy = List<FileSystemNode>.of(nodes);
    copy.sort((FileSystemNode a, FileSystemNode b) {
      final bool aFolder = a is FolderNode;
      final bool bFolder = b is FolderNode;
      if (aFolder != bFolder) {
        return aFolder ? -1 : 1;
      }
      switch (order) {
        case ExplorerSortOrder.name:
          break;
        case ExplorerSortOrder.type:
          final int byType = a.extension.compareTo(b.extension);
          if (byType != 0) {
            return byType;
          }
        case ExplorerSortOrder.modified:
          final DateTime? am = a.modified;
          final DateTime? bm = b.modified;
          if (am != null && bm != null) {
            // Most recent first: that is what "sort by modified" means to a
            // user looking for what they were last working on.
            final int byDate = bm.compareTo(am);
            if (byDate != 0) {
              return byDate;
            }
          }
      }
      return compareNatural(a.name, b.name);
    });
    return copy;
  }

  /// Case-insensitive comparison that orders embedded numbers numerically, so
  /// `item2` sorts before `item10` rather than after it.
  static int compareNatural(String a, String b) {
    final String x = a.toLowerCase();
    final String y = b.toLowerCase();
    int i = 0;
    int j = 0;
    while (i < x.length && j < y.length) {
      final int cx = x.codeUnitAt(i);
      final int cy = y.codeUnitAt(j);
      final bool xDigit = cx >= 0x30 && cx <= 0x39;
      final bool yDigit = cy >= 0x30 && cy <= 0x39;

      if (xDigit && yDigit) {
        int xEnd = i;
        while (xEnd < x.length &&
            x.codeUnitAt(xEnd) >= 0x30 &&
            x.codeUnitAt(xEnd) <= 0x39) {
          xEnd++;
        }
        int yEnd = j;
        while (yEnd < y.length &&
            y.codeUnitAt(yEnd) >= 0x30 &&
            y.codeUnitAt(yEnd) <= 0x39) {
          yEnd++;
        }
        // Compare as numbers, ignoring leading zeros.
        final int xNum = int.parse(x.substring(i, xEnd));
        final int yNum = int.parse(y.substring(j, yEnd));
        if (xNum != yNum) {
          return xNum.compareTo(yNum);
        }
        i = xEnd;
        j = yEnd;
        continue;
      }

      if (cx != cy) {
        return cx.compareTo(cy);
      }
      i++;
      j++;
    }
    return (x.length - i).compareTo(y.length - j);
  }

  /// Applies the hidden-files toggle and the exclude list.
  static List<FileSystemNode> filter(
    List<FileSystemNode> nodes, {
    required bool showHidden,
    required List<String> excludePatterns,
  }) {
    return nodes.where((FileSystemNode node) {
      if (!showHidden && node.isHidden) {
        return false;
      }
      return !isExcluded(node.name, excludePatterns);
    }).toList();
  }

  /// Matches a name against the exclude list.
  ///
  /// Supports plain names (`node_modules`) and simple `*` globs (`*.log`),
  /// which covers what the settings screen offers without pulling in a full
  /// glob engine.
  static bool isExcluded(String name, List<String> patterns) {
    for (final String pattern in patterns) {
      if (pattern.isEmpty) {
        continue;
      }
      if (!pattern.contains('*')) {
        if (name == pattern) {
          return true;
        }
        continue;
      }
      final String regex = pattern
          .split('*')
          .map(RegExp.escape)
          .join('.*');
      if (RegExp('^$regex\$', caseSensitive: false).hasMatch(name)) {
        return true;
      }
    }
    return false;
  }
}
