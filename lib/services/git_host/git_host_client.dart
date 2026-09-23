/// Talking to GitHub or GitLab over their REST APIs, with an optional token.
///
/// This is still **not** a git client. There is no clone, fetch, merge or
/// push; there are HTTPS requests that download an archive at one commit, list
/// the files at that commit, and — to propose a change — upload the changed
/// files as a new commit on a new branch and open a pull or merge request from
/// it. The hosts do the git part on their side.
///
/// Everything goes through [HttpTransport] and `sendFollowingRedirects`, so a
/// token is only ever sent to the host it belongs to.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// What the user writes before proposing a change.
class ChangeRequestDraft {
  const ChangeRequestDraft({
    required this.title,
    required this.description,
    required this.commitMessage,
    required this.branch,
  });

  final String title;
  final String description;
  final String commitMessage;

  /// The new branch the commit goes on. Never the repository's own branch.
  final String branch;
}

/// One file to send: its bytes, unless it is being deleted.
class OutgoingFile {
  const OutgoingFile({
    required this.path,
    required this.kind,
    this.bytes,
    this.mode = '100644',
  });

  final String path;
  final ChangeKind kind;
  final Uint8List? bytes;
  final String mode;
}

enum SubmitStage {
  checkingAccess('Checking access'),
  forking('Making your copy of the repository'),
  uploading('Uploading files'),
  committing('Committing'),
  opening('Opening the request');

  const SubmitStage(this.label);

  final String label;
}

class SubmitProgress {
  const SubmitProgress(this.stage, {this.done = 0, this.total = 0});

  final SubmitStage stage;
  final int done;
  final int total;
}

typedef SubmitProgressCallback = void Function(SubmitProgress);

class ChangeRequestResult {
  const ChangeRequestResult({
    required this.url,
    required this.branch,
    required this.viaFork,
  });

  /// The pull or merge request's page.
  final String url;
  final String branch;

  /// True when the change went through the user's own fork because they
  /// cannot push to the repository itself.
  final bool viaFork;
}

/// Waits between polls. Injected so tests do not sleep.
typedef Pause = Future<void> Function(Duration);

Future<void> _realPause(Duration d) => Future<void>.delayed(d);

abstract class GitHostClient {
  GitHostClient({
    required this.transport,
    this.token,
    Pause? pause,
  }) : pause = pause ?? _realPause;

  final HttpTransport transport;

  /// Null for anonymous access, which reaches public repositories only.
  final String? token;

  final Pause pause;

  RepoHost get host;

  /// The request is called a pull request on GitHub and a merge request on
  /// GitLab, and the UI uses the host's own word.
  String get requestNoun;

  /// The permissions a token needs, in the host's own words, for error hints
  /// and for the Accounts screen.
  String get neededPermissions;

  /// Where the user makes a token.
  String get tokenPage;

  /// Validates the token and returns the account name.
  Future<String> whoAmI();

  /// The commit [repo]'s branch points at now.
  Future<String> resolveBranch(RepoSource repo);

  /// The archive of [repo] at exactly [sha].
  Future<Uint8List> downloadArchive(
    RepoSource repo,
    String sha, {
    DownloadProgressCallback? onProgress,
  });

  /// Every file in [repo] at [sha], by path.
  Future<Map<String, RemoteEntry>> remoteTree(RepoSource repo, String sha);

  /// One blob's bytes, for showing what a file looked like at the base.
  Future<Uint8List> readBlob(RepoSource repo, String blobSha);

  /// Commits [files] on a new branch based on [baseSha] and opens a request
  /// against [repo]'s branch. Forks first if the account cannot push.
  Future<ChangeRequestResult> submit({
    required RepoSource repo,
    required String baseSha,
    required ChangeRequestDraft draft,
    required List<OutgoingFile> files,
    SubmitProgressCallback? onProgress,
  });

  // --- Shared plumbing ------------------------------------------------------

  /// Headers every request carries, including the credential when there is one.
  Map<String, String> get baseHeaders;

  /// Sends a request and turns any error status into a typed failure.
  Future<TransportResponse> call(
    String method,
    Uri uri, {
    Object? json,
    Map<String, String> headers = const <String, String>{},
    int maxBytes = 8 * 1024 * 1024,
    DownloadProgressCallback? onProgress,
  }) async {
    final TransportResponse response = await sendFollowingRedirects(
      transport,
      TransportRequest(
        method: method,
        uri: uri,
        headers: <String, String>{
          ...baseHeaders,
          if (json != null) 'Content-Type': 'application/json',
          ...headers,
        },
        body: json == null
            ? null
            : Uint8List.fromList(utf8.encode(jsonEncode(json))),
      ),
      maxBytes: maxBytes,
      onProgress: onProgress,
    );
    if (response.status >= 400) {
      throw failureFor(response);
    }
    return response;
  }

  /// Sends a request and decodes a JSON object from the answer.
  Future<Map<String, Object?>> callJson(
    String method,
    Uri uri, {
    Object? json,
  }) async {
    final Object? decoded = decodeBody(await call(method, uri, json: json));
    if (decoded is! Map<String, Object?>) {
      throw UnknownFailure(
        detail: '${host.label} sent an answer this app did not expect.',
        path: uri.host,
      );
    }
    return decoded;
  }

  Object? decodeBody(TransportResponse response) {
    try {
      return jsonDecode(utf8.decode(response.body, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }

  /// The host's own explanation, when it sent one. Never includes a header,
  /// so it cannot carry the token.
  String? messageOf(TransportResponse response) {
    final Object? body = decodeBody(response);
    if (body is! Map<String, Object?>) {
      return null;
    }
    final List<String> parts = <String>[];
    void collect(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        parts.add(value.trim());
      } else if (value is List<Object?>) {
        value.forEach(collect);
      } else if (value is Map<String, Object?>) {
        if (value.containsKey('message')) {
          collect(value['message']);
        } else {
          value.values.forEach(collect);
        }
      }
    }

    collect(body['message']);
    collect(body['errors']);
    collect(body['error']);
    return parts.isEmpty ? null : parts.join(' — ');
  }

  /// Maps an error status to what the user is told.
  AppFailure failureFor(TransportResponse response) {
    final String? message = messageOf(response);
    final bool limited = response.header('x-ratelimit-remaining') == '0' ||
        response.status == 429 ||
        (message?.toLowerCase().contains('rate limit') ?? false);
    if (limited) {
      return RateLimitFailure(resetsAt: _resetTime(response));
    }
    return switch (response.status) {
      401 => AuthFailure(needs: neededPermissions),
      403 when token == null => const RepositoryPrivateFailure(),
      403 => AuthFailure(needs: neededPermissions),
      404 => RepositoryNotFoundFailure(signedIn: token != null),
      400 || 409 || 422 => RemoteConflictFailure(
          detail: message ?? '${host.label} refused the request.',
        ),
      _ => UnknownFailure(
          detail: '${host.label} answered ${response.status}'
              '${message == null ? '.' : ': $message'}',
        ),
    };
  }

  String? _resetTime(TransportResponse response) {
    final int? epoch = int.tryParse(response.header('x-ratelimit-reset') ?? '');
    if (epoch == null) {
      return null;
    }
    final DateTime at =
        DateTime.fromMillisecondsSinceEpoch(epoch * 1000).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}';
  }
}
