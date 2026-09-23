/// Where a search looks: one folder, instead of the whole workspace.
///
/// This is VS Code's "Find in Folder": the same search, confined to a subtree.
/// It is applied at the file walk (`IndexRoot.startId`) rather than by filtering
/// results afterwards, so it is exact and only the chosen folder is listed.
library;

import 'package:flutter/foundation.dart';

@immutable
class SearchScope {
  const SearchScope({
    required this.rootIndex,
    required this.folderId,
    required this.relativePath,
    required this.name,
  });

  /// Which workspace root the folder belongs to.
  final int rootIndex;

  /// The provider's own id for the folder. Opaque — never parsed.
  final String folderId;

  /// The folder's `/`-separated path below its root, `''` for the root itself.
  ///
  /// Built by walking `parentOf`/`nameOf`, never by splitting [folderId]: a SAF
  /// id is a percent-encoded `content://` URI.
  final String relativePath;

  final String name;

  /// Shown on the chip, e.g. `DMND/music/`.
  ///
  /// The trailing slash is what makes it read as a folder rather than a file
  /// name, which matters because the two share a font and a line.
  String get label => '${relativePath.isEmpty ? name : relativePath}/';

  @override
  bool operator ==(Object other) =>
      other is SearchScope &&
      other.rootIndex == rootIndex &&
      other.folderId == folderId;

  @override
  int get hashCode => Object.hash(rootIndex, folderId);

  @override
  String toString() => 'SearchScope($label)';
}
