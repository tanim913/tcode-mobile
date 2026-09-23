/// Finding what changed in a downloaded folder, and proposing it back.
///
/// One session per visit to the pull request screen. It holds the scan's
/// results so the diff view and the submit step read exactly the list the
/// user looked at, rather than rescanning in between.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/local_snapshot.dart';
import 'package:pocket_code/services/git_host/repo_link_store.dart';

typedef ScanProgress = void Function(int done, int total);

class ChangeRequestSession {
  ChangeRequestSession({
    required this.provider,
    required this.folderId,
    required this.link,
    required this.client,
  }) : assert(link.baseSha != null, 'a link without a base cannot propose');

  final FileSystemProvider provider;
  final String folderId;
  final RepoLink link;
  final GitHostClient client;

  Map<String, LocalFile> _local = const <String, LocalFile>{};
  Map<String, RemoteEntry> _remote = const <String, RemoteEntry>{};
  List<FileChange> _changes = const <FileChange>[];

  List<FileChange> get changes => _changes;

  String get _base => link.baseSha!;

  /// Lists the base commit's files, hashes the local ones and compares.
  Future<List<FileChange>> scan({ScanProgress? onProgress}) async {
    _remote = await client.remoteTree(link.source, _base);
    final Set<String> downloaded =
        await RepoLinkStore(provider).downloadedFiles(folderId);
    _local = await hashLocalFiles(provider, folderId, onProgress: onProgress);
    _changes = computeChanges(
      local: <String, String>{
        for (final MapEntry<String, LocalFile> e in _local.entries)
          e.key: e.value.sha,
      },
      remote: _remote,
      downloaded: downloaded,
    );
    return _changes;
  }

  /// Both sides of one change as text, for the diff view. An added file has
  /// an empty "before", a deleted one an empty "after".
  Future<(String before, String after)> textsOf(FileChange change) async {
    final String? baseSha = change.baseSha;
    final Uint8List before = baseSha == null
        ? Uint8List(0)
        : await client.readBlob(link.source, baseSha);
    final LocalFile? local = _local[change.path];
    final Uint8List after = local == null || change.kind == ChangeKind.deleted
        ? Uint8List(0)
        : await provider.readBytes(local.id);
    return (
      utf8.decode(before, allowMalformed: true),
      utf8.decode(after, allowMalformed: true),
    );
  }

  /// Sends [selected] — a subset of [changes] the user kept ticked.
  Future<ChangeRequestResult> submit(
    ChangeRequestDraft draft,
    List<FileChange> selected, {
    SubmitProgressCallback? onProgress,
  }) async {
    final List<OutgoingFile> files = <OutgoingFile>[];
    for (final FileChange change in selected) {
      final LocalFile? local = _local[change.path];
      files.add(
        OutgoingFile(
          path: change.path,
          kind: change.kind,
          // Read again rather than cached from the scan: the user may have
          // kept editing while looking at the list.
          bytes: change.kind == ChangeKind.deleted || local == null
              ? null
              : await provider.readBytes(local.id),
          mode: _remote[change.path]?.mode ?? '100644',
        ),
      );
    }
    return client.submit(
      repo: link.source,
      baseSha: _base,
      draft: draft,
      files: files,
      onProgress: onProgress,
    );
  }
}

/// A branch name nobody else is likely to have picked, e.g.
/// `tcode/20260922-1432`.
String defaultBranchName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'tcode/${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}';
}

/// Why [name] cannot be a branch, or null when it can.
///
/// A subset of `git check-ref-format`, enough to catch what people type on a
/// phone keyboard before the host refuses it with a less readable message.
String? branchNameProblem(String name) {
  final String n = name.trim();
  if (n.isEmpty) {
    return 'Enter a branch name';
  }
  if (RegExp(r'[\s~^:?*\[\\]').hasMatch(n) ||
      n.contains('..') ||
      n.contains('@{') ||
      n.startsWith('/') ||
      n.endsWith('/') ||
      n.endsWith('.') ||
      n.endsWith('.lock') ||
      n.startsWith('-')) {
    return 'Letters, digits, "-", "_", "." and "/" only, with no spaces';
  }
  return null;
}
