/// When a save is worth recording, and what to throw away.
///
/// Pure and I/O-free on purpose: this is where the feature's behaviour actually
/// lives, and all of it can be tested without a device or a filesystem.
library;

import 'package:pocket_code/data/models/file_version.dart';

/// The retention rules, seeded from settings.
class HistoryPolicy {
  const HistoryPolicy({
    this.maxVersionsPerFile = 50,
    this.maxAge = const Duration(days: 30),
    this.maxBytesPerFile = 5 * 1024 * 1024,
    this.minInterval = const Duration(minutes: 5),
    this.significantChars = 400,
    this.maxFileBytes = 1024 * 1024,
  });

  final int maxVersionsPerFile;
  final Duration maxAge;
  final int maxBytesPerFile;

  /// Two snapshots of the same file are never closer together than this,
  /// unless the change is large.
  final Duration minInterval;

  /// A change bigger than this overrides [minInterval]: pasting or deleting a
  /// block is worth keeping even a moment after the last snapshot.
  final int significantChars;

  /// Files larger than this are not recorded at all.
  final int maxFileBytes;
}

/// Whether the content about to be overwritten should be kept.
///
/// Auto-save fires on a one-second debounce by default, so recording every save
/// would produce a version per second of typing. The rules, in order:
///
/// 1. Nothing to keep if the content is empty of change.
/// 2. Never record content identical to the newest version.
/// 3. Respect [HistoryPolicy.minInterval] — unless the change is large.
/// 4. An explicit save always records, because "I pressed Save, is it in
///    history?" must be answerable with an unqualified yes.
bool shouldSnapshot({
  required DateTime now,
  required FileVersion? newest,
  required String previousText,
  required String nextText,
  required String previousHash,
  required bool explicit,
  required HistoryPolicy policy,
}) {
  if (previousText == nextText) {
    return false;
  }
  if (previousText.length > policy.maxFileBytes) {
    return false;
  }
  if (newest != null &&
      newest.contentHash == previousHash &&
      newest.byteLength == previousText.length) {
    return false;
  }
  if (explicit || newest == null) {
    return true;
  }
  if (now.difference(newest.savedAt) >= policy.minInterval) {
    return true;
  }
  // A burst of typing is coalesced, but a big edit is not.
  return (nextText.length - previousText.length).abs() >=
      policy.significantChars;
}

/// The versions to keep for one file, newest first.
///
/// Applies all three limits; whichever bites first wins.
List<FileVersion> keepVersions(
  List<FileVersion> versions, {
  required DateTime now,
  required HistoryPolicy policy,
}) {
  final List<FileVersion> sorted = List<FileVersion>.of(versions)
    ..sort((FileVersion a, FileVersion b) => b.stamp.compareTo(a.stamp));

  final List<FileVersion> kept = <FileVersion>[];
  int bytes = 0;
  for (final FileVersion version in sorted) {
    if (kept.length >= policy.maxVersionsPerFile) {
      break;
    }
    if (now.difference(version.savedAt) > policy.maxAge) {
      break;
    }
    if (bytes + version.byteLength > policy.maxBytesPerFile && kept.isNotEmpty) {
      break;
    }
    kept.add(version);
    bytes += version.byteLength;
  }
  return kept;
}

/// The versions to delete: everything [keepVersions] did not keep.
List<FileVersion> evictVersions(
  List<FileVersion> versions, {
  required DateTime now,
  required HistoryPolicy policy,
}) {
  final Set<int> kept = keepVersions(versions, now: now, policy: policy)
      .map((FileVersion v) => v.stamp)
      .toSet();
  return versions.where((FileVersion v) => !kept.contains(v.stamp)).toList();
}
