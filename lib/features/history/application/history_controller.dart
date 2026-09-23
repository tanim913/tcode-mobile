/// Records a version of a file whenever it is about to be overwritten.
///
/// **Snapshots are taken before the write, of the content that is about to be
/// lost.** Two things follow, and both are improvements:
///
/// * The file on disk is always the newest state, so history never stores a
///   redundant copy of it. Storage roughly halves.
/// * Coalescing becomes "skip", not "replace". Skipping keeps the state from
///   before a burst of typing, which is exactly what anyone wants back; had the
///   newest content been stored, coalescing would have had to overwrite, and
///   the pre-burst state would be the thing lost.
///
/// A version's timestamp is therefore the moment it *stopped* being current,
/// which is why the UI reads "Before 14:32" rather than "14:32".
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/utils/stable_hash.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_version.dart';
import 'package:pocket_code/data/repositories/history_repository.dart';
import 'package:pocket_code/features/history/application/history_key.dart';
import 'package:pocket_code/features/history/application/history_policy.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

class FileHistory {
  FileHistory({
    required this._repository,
    required this._policy,
    required this._enabled,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now;


  final HistoryRepository? _repository;
  final HistoryPolicy _policy;
  final bool _enabled;

  /// Injected so the interval rule is testable without waiting.
  final DateTime Function() _now;

  bool get isAvailable => _repository != null;

  /// Records [previousText] as a version, if the policy says it is worth it.
  ///
  /// Never throws: history is a safety net, and a failure to record must not
  /// stop the save it was observing.
  Future<void> recordSave({
    required FileSystemProvider provider,
    required String rootId,
    required String fileId,
    required String name,
    required String displayPath,
    required String previousText,
    required String nextText,
    required bool explicit,
  }) async {
    final HistoryRepository? repository = _repository;
    if (repository == null || !_enabled) {
      return;
    }
    try {
      final String key = historyKeyFor(
        provider: provider,
        rootId: rootId,
        fileId: fileId,
        fallbackName: name,
      );
      final HistoryFolder? folder = await repository.folderFor(
        key,
        name: name,
        displayPath: displayPath,
      );
      final String hash = stableHash(previousText);
      if (!shouldSnapshot(
        now: _now(),
        newest: folder?.meta.newest,
        previousText: previousText,
        nextText: nextText,
        previousHash: hash,
        explicit: explicit,
        policy: _policy,
      )) {
        return;
      }

      final FileHistoryMeta updated = await repository.addVersion(
        key: key,
        name: name,
        displayPath: displayPath,
        text: previousText,
        contentHash: hash,
        savedAt: _now(),
      );
      await _prune(repository, key, name, displayPath, updated);
    } on Object {
      // Recording is best effort. The save itself already happened, or is
      // about to; nothing here is worth surfacing.
    }
  }

  Future<void> _prune(
    HistoryRepository repository,
    String key,
    String name,
    String displayPath,
    FileHistoryMeta meta,
  ) async {
    final List<FileVersion> doomed =
        evictVersions(meta.versions, now: _now(), policy: _policy);
    if (doomed.isEmpty) {
      return;
    }
    final HistoryFolder? folder =
        await repository.folderFor(key, name: name, displayPath: displayPath);
    if (folder != null) {
      await repository.removeVersions(folder, doomed);
    }
  }

  /// The recorded versions of a file, newest first.
  Future<HistoryFolder?> versionsFor({
    required FileSystemProvider provider,
    required String rootId,
    required String fileId,
    required String name,
    required String displayPath,
  }) async {
    final HistoryRepository? repository = _repository;
    if (repository == null) {
      return null;
    }
    return repository.folderFor(
      historyKeyFor(
        provider: provider,
        rootId: rootId,
        fileId: fileId,
        fallbackName: name,
      ),
      name: name,
      displayPath: displayPath,
    );
  }

  Future<String?> contentOf(HistoryFolder folder, FileVersion version) async =>
      _repository?.contentOf(folder.id, version);

  /// Follows a rename so the history stays attached to the file.
  Future<void> onPathChanged({
    required FileSystemProvider provider,
    required String rootId,
    required String oldRelative,
    required String newRelative,
    required String name,
    required String displayPath,
  }) async {
    final HistoryRepository? repository = _repository;
    if (repository == null || oldRelative == newRelative) {
      return;
    }
    final String scheme = provider.schemeId;
    await repository.rename(
      oldKey: '$scheme$kKeySeparator$oldRelative',
      newKey: '$scheme$kKeySeparator$newRelative',
      name: name,
      displayPath: displayPath,
    );
  }

  /// Total bytes held, for the settings screen.
  Future<int> totalBytes() async {
    final HistoryRepository? repository = _repository;
    if (repository == null) {
      return 0;
    }
    int total = 0;
    for (final HistoryFolder folder in await repository.allFolders()) {
      total += folder.meta.totalBytes;
    }
    return total;
  }

  /// Drops everything past the limits, across every tracked file.
  ///
  /// Run once, a few seconds after launch — never during startup. It cannot go
  /// to an isolate: every operation is an async `FileSystemProvider` call, and
  /// on SAF and on web there is no isolate to move it to. It yields between
  /// folders instead, the same cadence as the bulk worker.
  Future<void> sweep() async {
    final HistoryRepository? repository = _repository;
    if (repository == null) {
      return;
    }
    try {
      for (final HistoryFolder folder in await repository.allFolders()) {
        final List<FileVersion> doomed = evictVersions(
          folder.meta.versions,
          now: _now(),
          policy: _policy,
        );
        if (doomed.isNotEmpty) {
          await repository.removeVersions(folder, doomed);
        }
        if (folder.meta.versions.length == doomed.length) {
          // Nothing left worth keeping.
          await repository.deleteFolder(folder.id);
        }
        await Future<void>.delayed(Duration.zero);
      }
    } on Object {
      // Housekeeping.
    }
  }

  Future<void> clearAll() async => _repository?.clearAll();
}

/// The policy as configured in settings.
HistoryPolicy policyFrom(EditorSettings settings) => HistoryPolicy(
      maxVersionsPerFile: settings.historyMaxVersions,
      maxAge: Duration(days: settings.historyMaxAgeDays),
      maxBytesPerFile: settings.historyMaxBytesPerFile,
    );

final Provider<FileHistory> fileHistoryProvider = Provider<FileHistory>((
  Ref ref,
) {
  final EditorSettings editor = ref.watch(settingsProvider).editor;
  return FileHistory(
    repository: ref.watch(historyRepositoryProvider),
    policy: policyFrom(editor),
    enabled: editor.fileHistory,
  );
});
