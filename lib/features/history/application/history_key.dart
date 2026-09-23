/// Naming a file's history folder.
///
/// The key has to survive things that routinely change about a file's id: a
/// workspace moving on disk, a SAF grant being re-issued with a different URI,
/// a root being removed so later roots shift index. What survives all three is
/// the provider scheme plus the path relative to the workspace root.
library;

import 'package:pocket_code/core/utils/relative_path.dart';
import 'package:pocket_code/core/utils/stable_hash.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

/// Separator between key parts. A character that cannot appear in a scheme or
/// a path segment, so the parts can never run together.
const String kKeySeparator = '|';

/// The history key for a file.
///
/// Deliberately **not** `tab.key`: that is `'$rootIndex:$id'`, and `rootIndex`
/// is positional — removing a root would rename every file's history.
String historyKeyFor({
  required FileSystemProvider provider,
  required String rootId,
  required String fileId,
  required String fallbackName,
}) {
  final String relative = relativePathIn(
    provider,
    rootId,
    fileId,
    fallback: fallbackName,
  );
  return '${provider.schemeId}$kKeySeparator$relative';
}

/// The folder name for [key].
String historyFolderFor(String key) => stableHash(key);

/// The relative-path part of [key], or null when it has none.
String? relativePathOf(String key) {
  final int split = key.indexOf(kKeySeparator);
  return split < 0 ? null : key.substring(split + 1);
}

/// Rewrites [key] for a file that moved from [oldRelative] to [newRelative].
///
/// Also handles files *inside* a renamed folder, which is why this compares a
/// prefix. That is string work on **our own** normalised forward-slash path,
/// not on a provider id — the "never split an id" rule is about opaque ids, and
/// this path is one we built ourselves with a known separator.
String? rebasedKey(String key, String oldRelative, String newRelative) {
  final String? relative = relativePathOf(key);
  if (relative == null) {
    return null;
  }
  final int split = key.indexOf(kKeySeparator);
  final String scheme = key.substring(0, split);

  if (relative == oldRelative) {
    return '$scheme$kKeySeparator$newRelative';
  }
  final String prefix = '$oldRelative/';
  if (relative.startsWith(prefix)) {
    final String rest = relative.substring(prefix.length);
    return '$scheme$kKeySeparator$newRelative/$rest';
  }
  return null;
}
