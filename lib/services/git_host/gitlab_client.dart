/// GitLab (gitlab.com) over its REST API, v4.
///
/// Simpler than GitHub on the write side: one "create commit" call takes every
/// file as an action — create, update or delete — and makes the branch too.
///
/// Projects are addressed as the URL-encoded `owner/name`, which
/// `Uri.pathSegments` does for us: a `/` inside one segment becomes `%2F`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

class GitLabClient extends GitHostClient {
  GitLabClient({required super.transport, super.token, super.pause});

  static const String _host = 'gitlab.com';

  /// Stops paging a tree listing. Matches the explorer's own walk limit: a
  /// repository bigger than that cannot be compared on a phone anyway.
  static const int maxTreeEntries = 20000;

  static const int forkPolls = 20;
  static const Duration forkPollInterval = Duration(seconds: 3);

  /// GitLab's "Developer" role, the lowest that can push a branch.
  static const int developerAccess = 30;

  @override
  RepoHost get host => RepoHost.gitlab;

  @override
  String get requestNoun => 'merge request';

  @override
  String get neededPermissions => 'a personal access token with the "api" '
      'scope';

  @override
  String get tokenPage =>
      'https://gitlab.com/-/user_settings/personal_access_tokens';

  @override
  Map<String, String> get baseHeaders => <String, String>{
        'Accept': 'application/json',
        'PRIVATE-TOKEN': ?token,
      };

  Uri _uri(List<String> segments, [Map<String, String>? query]) => Uri(
        scheme: 'https',
        host: _host,
        pathSegments: <String>['api', 'v4', ...segments],
        queryParameters: query,
      );

  List<String> _project(String pathOrId) => <String>['projects', pathOrId];

  String _path(RepoSource repo) => '${repo.owner}/${repo.name}';

  @override
  Future<String> whoAmI() async {
    if (token == null) {
      throw AuthFailure(needs: neededPermissions);
    }
    final Map<String, Object?> user =
        await callJson('GET', _uri(<String>['user']));
    return _string(user, 'username');
  }

  @override
  Future<String> resolveBranch(RepoSource repo) async {
    final Map<String, Object?> branch = await callJson(
      'GET',
      _uri(<String>[
        ..._project(_path(repo)),
        'repository',
        'branches',
        repo.branch,
      ]),
    );
    final Object? commit = branch['commit'];
    if (commit is! Map<String, Object?>) {
      throw const UnknownFailure(detail: 'GitLab sent a branch with no commit.');
    }
    return _string(commit, 'id');
  }

  @override
  Future<Uint8List> downloadArchive(
    RepoSource repo,
    String sha, {
    DownloadProgressCallback? onProgress,
  }) async {
    final TransportResponse response = await call(
      'GET',
      _uri(
        <String>[..._project(_path(repo)), 'repository', 'archive.zip'],
        <String, String>{'sha': sha},
      ),
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
    final Map<String, RemoteEntry> entries = <String, RemoteEntry>{};
    String? page = '1';
    int seen = 0;
    while (page != null && page.isNotEmpty) {
      final TransportResponse response = await call(
        'GET',
        _uri(
          <String>[..._project(_path(repo)), 'repository', 'tree'],
          <String, String>{
            'ref': sha,
            'recursive': 'true',
            'per_page': '100',
            'page': page,
          },
        ),
      );
      final Object? items = decodeBody(response);
      if (items is List<Object?>) {
        for (final Object? item in items) {
          seen++;
          if (item is Map<String, Object?> &&
              item['type'] == 'blob' &&
              item['path'] is String &&
              item['id'] is String) {
            entries[item['path']! as String] = RemoteEntry(
              sha: item['id']! as String,
              mode:
                  item['mode'] is String ? item['mode']! as String : '100644',
            );
          }
        }
      }
      if (seen > maxTreeEntries) {
        throw const UnsupportedOperationFailure(
          what: 'This repository has too many files for this app to tell '
              'what changed.',
        );
      }
      page = response.header('x-next-page');
    }
    return entries;
  }

  @override
  Future<Uint8List> readBlob(RepoSource repo, String blobSha) async {
    final TransportResponse response = await call(
      'GET',
      _uri(<String>[
        ..._project(_path(repo)),
        'repository',
        'blobs',
        blobSha,
        'raw',
      ]),
    );
    return response.body;
  }

  @override
  Future<ChangeRequestResult> submit({
    required RepoSource repo,
    required String baseSha,
    required ChangeRequestDraft draft,
    required List<OutgoingFile> files,
    SubmitProgressCallback? onProgress,
  }) async {
    onProgress?.call(const SubmitProgress(SubmitStage.checkingAccess));
    await whoAmI();
    final Map<String, Object?> project =
        await callJson('GET', _uri(_project(_path(repo))));
    final int upstreamId = _int(project, 'id');
    final bool canPush = _accessLevel(project) >= developerAccess;

    int targetId = upstreamId;
    if (!canPush) {
      onProgress?.call(const SubmitProgress(SubmitStage.forking));
      targetId = await _fork(repo, upstreamId);
    }

    onProgress?.call(
      SubmitProgress(SubmitStage.uploading, total: files.length),
    );
    final List<Map<String, Object?>> actions = <Map<String, Object?>>[
      for (final OutgoingFile file in files)
        <String, Object?>{
          'action': switch (file.kind) {
            ChangeKind.added => 'create',
            ChangeKind.modified => 'update',
            ChangeKind.deleted => 'delete',
          },
          'file_path': file.path,
          if (file.kind != ChangeKind.deleted) ...<String, Object?>{
            'content': base64.encode(file.bytes ?? Uint8List(0)),
            'encoding': 'base64',
          },
          if (file.mode == '100755') 'execute_filemode': true,
        },
    ];

    onProgress?.call(const SubmitProgress(SubmitStage.committing));
    try {
      // One call: GitLab creates `branch` from `start_sha` and commits every
      // action on it.
      await callJson(
        'POST',
        _uri(<String>[..._project('$targetId'), 'repository', 'commits']),
        json: <String, Object?>{
          'branch': draft.branch,
          'start_sha': baseSha,
          'commit_message': draft.commitMessage,
          'actions': actions,
        },
      );
    } on RemoteConflictFailure catch (failure) {
      if (failure.hint.toLowerCase().contains('already exists')) {
        throw RemoteConflictFailure(
          detail: 'A branch called "${draft.branch}" already exists there. '
              'Pick another branch name.',
        );
      }
      rethrow;
    }

    onProgress?.call(const SubmitProgress(SubmitStage.opening));
    final Map<String, Object?> request = await callJson(
      'POST',
      _uri(<String>[..._project('$targetId'), 'merge_requests']),
      json: <String, Object?>{
        'source_branch': draft.branch,
        'target_branch': repo.branch,
        'title': draft.title,
        'description': draft.description,
        if (!canPush) 'target_project_id': upstreamId,
      },
    );
    return ChangeRequestResult(
      url: _string(request, 'web_url'),
      branch: draft.branch,
      viaFork: !canPush,
    );
  }

  /// The higher of the user's project and group access levels.
  int _accessLevel(Map<String, Object?> project) {
    final Object? permissions = project['permissions'];
    if (permissions is! Map<String, Object?>) {
      return 0;
    }
    int level = 0;
    for (final String key in <String>['project_access', 'group_access']) {
      final Object? access = permissions[key];
      if (access is Map<String, Object?> && access['access_level'] is int) {
        final int value = access['access_level']! as int;
        if (value > level) {
          level = value;
        }
      }
    }
    return level;
  }

  /// Forks [repo], or finds the user's existing fork, and waits until GitLab
  /// has finished copying it.
  Future<int> _fork(RepoSource repo, int upstreamId) async {
    int forkId;
    try {
      final Map<String, Object?> fork = await callJson(
        'POST',
        _uri(<String>[..._project('$upstreamId'), 'fork']),
        json: const <String, Object?>{},
      );
      forkId = _int(fork, 'id');
    } on RemoteConflictFailure {
      // Already forked: GitLab refuses a second fork into the same namespace.
      final TransportResponse response = await call(
        'GET',
        _uri(
          <String>[..._project('$upstreamId'), 'forks'],
          <String, String>{'owned': 'true'},
        ),
      );
      final Object? forks = decodeBody(response);
      if (forks is! List<Object?> ||
          forks.isEmpty ||
          forks.first is! Map<String, Object?>) {
        rethrow;
      }
      forkId = _int(forks.first! as Map<String, Object?>, 'id');
    }

    for (int attempt = 0; attempt < forkPolls; attempt++) {
      final Map<String, Object?> state =
          await callJson('GET', _uri(_project('$forkId')));
      final Object? status = state['import_status'];
      if (status == null || status == 'finished' || status == 'none') {
        return forkId;
      }
      if (status == 'failed') {
        throw const UnknownFailure(detail: 'GitLab could not create your fork.');
      }
      await pause(forkPollInterval);
    }
    throw const UnknownFailure(
      detail: 'GitLab is still preparing your fork. Try again in a minute.',
    );
  }

  String _string(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is String) {
      return value;
    }
    throw UnknownFailure(
      detail: 'GitLab sent an answer without "$key".',
      path: _host,
    );
  }

  int _int(Map<String, Object?> json, String key) {
    final Object? value = json[key];
    if (value is int) {
      return value;
    }
    throw UnknownFailure(
      detail: 'GitLab sent an answer without "$key".',
      path: _host,
    );
  }
}
