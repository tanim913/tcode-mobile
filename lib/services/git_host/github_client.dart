/// GitHub over its REST API.
///
/// A pull request is built from GitHub's low-level "Git data" endpoints,
/// which is how a client with no git binary can still make a real commit:
/// upload each changed file as a blob, build a tree on top of the base
/// commit's tree, make a commit with the base as its parent, point a new
/// branch at it, and open the pull request from that branch.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

class GitHubClient extends GitHostClient {
  GitHubClient({required super.transport, super.token, super.pause});

  static const String _api = 'api.github.com';

  /// How long to wait for a new fork to become usable. GitHub creates forks
  /// asynchronously, usually in seconds.
  static const int forkPolls = 20;
  static const Duration forkPollInterval = Duration(seconds: 3);

  /// GitHub's own limit on one blob.
  static const int maxBlobBytes = 50 * 1024 * 1024;

  @override
  RepoHost get host => RepoHost.github;

  @override
  String get requestNoun => 'pull request';

  @override
  String get neededPermissions =>
      'a fine-grained token with "Contents" and "Pull requests" set to Read '
      'and write, or a classic token with the "repo" scope';

  @override
  String get tokenPage => 'https://github.com/settings/personal-access-tokens';

  @override
  Map<String, String> get baseHeaders => <String, String>{
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Uri _uri(List<String> segments, [Map<String, String>? query]) => Uri(
        scheme: 'https',
        host: _api,
        pathSegments: segments,
        queryParameters: query,
      );

  List<String> _repo(RepoSource repo) =>
      <String>['repos', repo.owner, repo.name];

  @override
  Future<String> whoAmI() async {
    if (token == null) {
      throw AuthFailure(needs: neededPermissions);
    }
    final Map<String, Object?> user =
        await callJson('GET', _uri(<String>['user']));
    return _string(user, 'login');
  }

  @override
  Future<String> resolveBranch(RepoSource repo) async {
    try {
      final Map<String, Object?> commit = await callJson(
        'GET',
        _uri(<String>[..._repo(repo), 'commits', repo.branch]),
      );
      return _string(commit, 'sha');
    } on RemoteConflictFailure {
      // GitHub answers 422 "No commit found" for a branch that does not
      // exist, which is the wrong-branch case, not a conflict.
      throw RepositoryNotFoundFailure(signedIn: token != null);
    }
  }

  @override
  Future<Uint8List> downloadArchive(
    RepoSource repo,
    String sha, {
    DownloadProgressCallback? onProgress,
  }) async {
    // Answered with a redirect to codeload.github.com, which
    // `sendFollowingRedirects` follows without the Authorization header: the
    // redirect URL carries its own short-lived access token.
    final TransportResponse response = await call(
      'GET',
      _uri(<String>[..._repo(repo), 'zipball', sha]),
      maxBytes: kMaxArchiveBytes,
      onProgress: onProgress,
    );
    return response.body;
  }

  @override
  Future<Map<String, RemoteEntry>> remoteTree(
    RepoSource repo,
    String sha,
  ) async {
    final Map<String, Object?> tree = await callJson(
      'GET',
      _uri(
        <String>[..._repo(repo), 'git', 'trees', sha],
        <String, String>{'recursive': '1'},
      ),
    );
    if (tree['truncated'] == true) {
      // GitHub cuts the listing off for very large repositories. A partial
      // listing would make every unlisted file look added, so refuse instead.
      throw const UnsupportedOperationFailure(
        what: 'This repository is too large for GitHub to list in one go, '
            'so this app cannot tell what changed.',
      );
    }
    final Map<String, RemoteEntry> entries = <String, RemoteEntry>{};
    final Object? items = tree['tree'];
    if (items is List<Object?>) {
      for (final Object? item in items) {
        if (item is Map<String, Object?> &&
            item['type'] == 'blob' &&
            item['path'] is String &&
            item['sha'] is String) {
          entries[item['path']! as String] = RemoteEntry(
            sha: item['sha']! as String,
            mode: item['mode'] is String ? item['mode']! as String : '100644',
          );
        }
      }
    }
    return entries;
  }

  @override
  Future<Uint8List> readBlob(RepoSource repo, String blobSha) async {
    final Map<String, Object?> blob = await callJson(
      'GET',
      _uri(<String>[..._repo(repo), 'git', 'blobs', blobSha]),
    );
    final String content = _string(blob, 'content');
    return base64.decode(content.replaceAll(RegExp(r'\s'), ''));
  }

  @override
  Future<ChangeRequestResult> submit({
    required RepoSource repo,
    required String baseSha,
    required ChangeRequestDraft draft,
    required List<OutgoingFile> files,
    SubmitProgressCallback? onProgress,
  }) async {
    for (final OutgoingFile file in files) {
      if ((file.bytes?.length ?? 0) > maxBlobBytes) {
        throw UnsupportedOperationFailure(
          what: '${file.path} is larger than the 50 MB GitHub accepts for one '
              'file.',
        );
      }
    }

    onProgress?.call(const SubmitProgress(SubmitStage.checkingAccess));
    // Confirms the token before anything is written.
    await whoAmI();
    final Map<String, Object?> info =
        await callJson('GET', _uri(_repo(repo)));
    final Object? permissions = info['permissions'];
    final bool canPush =
        permissions is Map<String, Object?> && permissions['push'] == true;

    RepoSource target = repo;
    if (!canPush) {
      onProgress?.call(const SubmitProgress(SubmitStage.forking));
      target = await _fork(repo, baseSha);
    }

    final Map<String, Object?> baseCommit = await callJson(
      'GET',
      _uri(<String>[..._repo(target), 'git', 'commits', baseSha]),
    );
    final Object? baseTree = baseCommit['tree'];
    final String baseTreeSha = baseTree is Map<String, Object?>
        ? _string(baseTree, 'sha')
        : throw const UnknownFailure(detail: 'GitHub sent a commit with no tree.');

    final List<Map<String, Object?>> entries = <Map<String, Object?>>[];
    final int uploads =
        files.where((OutgoingFile f) => f.kind != ChangeKind.deleted).length;
    int uploaded = 0;
    onProgress?.call(
      SubmitProgress(SubmitStage.uploading, total: uploads),
    );
    for (final OutgoingFile file in files) {
      if (file.kind == ChangeKind.deleted) {
        // A null sha removes the path from the tree built on `base_tree`.
        entries.add(<String, Object?>{
          'path': file.path,
          'mode': file.mode,
          'type': 'blob',
          'sha': null,
        });
        continue;
      }
      final Map<String, Object?> blob = await callJson(
        'POST',
        _uri(<String>[..._repo(target), 'git', 'blobs']),
        json: <String, Object?>{
          'content': base64.encode(file.bytes ?? Uint8List(0)),
          'encoding': 'base64',
        },
      );
      entries.add(<String, Object?>{
        'path': file.path,
        'mode': file.mode,
        'type': 'blob',
        'sha': _string(blob, 'sha'),
      });
      uploaded++;
      onProgress?.call(
        SubmitProgress(SubmitStage.uploading, done: uploaded, total: uploads),
      );
    }

    onProgress?.call(const SubmitProgress(SubmitStage.committing));
    final Map<String, Object?> tree = await callJson(
      'POST',
      _uri(<String>[..._repo(target), 'git', 'trees']),
      json: <String, Object?>{'base_tree': baseTreeSha, 'tree': entries},
    );
    final Map<String, Object?> commit = await callJson(
      'POST',
      _uri(<String>[..._repo(target), 'git', 'commits']),
      json: <String, Object?>{
        'message': draft.commitMessage,
        'tree': _string(tree, 'sha'),
        'parents': <String>[baseSha],
      },
    );
    try {
      await callJson(
        'POST',
        _uri(<String>[..._repo(target), 'git', 'refs']),
        json: <String, Object?>{
          'ref': 'refs/heads/${draft.branch}',
          'sha': _string(commit, 'sha'),
        },
      );
    } on RemoteConflictFailure {
      throw RemoteConflictFailure(
        detail: 'A branch called "${draft.branch}" already exists there. '
            'Pick another branch name.',
      );
    }

    onProgress?.call(const SubmitProgress(SubmitStage.opening));
    final Map<String, Object?> pull = await callJson(
      'POST',
      _uri(<String>[..._repo(repo), 'pulls']),
      json: <String, Object?>{
        'title': draft.title,
        'body': draft.description,
        'head': canPush ? draft.branch : '${target.owner}:${draft.branch}',
        'base': repo.branch,
      },
    );
    return ChangeRequestResult(
      url: _string(pull, 'html_url'),
      branch: draft.branch,
      viaFork: !canPush,
    );
  }

  /// Forks [repo] (or finds the existing fork — GitHub returns it) and waits
  /// until [baseSha] can be read from it.
  Future<RepoSource> _fork(RepoSource repo, String baseSha) async {
    final Map<String, Object?> fork = await callJson(
      'POST',
      _uri(<String>[..._repo(repo), 'forks']),
      json: const <String, Object?>{},
    );
    final Object? owner = fork['owner'];
    final RepoSource target = RepoSource(
      host: RepoHost.github,
      owner: owner is Map<String, Object?> ? _string(owner, 'login') : '',
      name: _string(fork, 'name'),
      branch: repo.branch,
    );
    for (int attempt = 0; attempt < forkPolls; attempt++) {
      try {
        await call(
          'GET',
          _uri(<String>[..._repo(target), 'git', 'commits', baseSha]),
        );
        return target;
      } on AppFailure catch (failure) {
        if (failure is! RepositoryNotFoundFailure &&
            failure is! RemoteConflictFailure) {
          rethrow;
        }
      }
      await pause(forkPollInterval);
    }
    throw const UnknownFailure(
      detail: 'GitHub is still preparing your fork. Try again in a minute.',
    );
  }

  String _string(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is String) {
      return value;
    }
    throw UnknownFailure(
      detail: 'GitHub sent an answer without "$key".',
      path: _api,
    );
  }
}
