/// The exact request sequence behind a GitHub pull request, and how each
/// refusal is reported. Against a fake transport: nothing leaves the machine.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/github_client.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

import '../../support/fake_transport.dart';

const RepoSource repo = RepoSource(
  host: RepoHost.github,
  owner: 'up',
  name: 'proj',
  branch: 'main',
);
final String base = 'b' * 40;

const ChangeRequestDraft draft = ChangeRequestDraft(
  title: 'Fix typo',
  description: 'From my phone',
  commitMessage: 'Fix typo in README',
  branch: 'tcode/fix',
);

List<OutgoingFile> files() => <OutgoingFile>[
      OutgoingFile(
        path: 'README.md',
        kind: ChangeKind.modified,
        bytes: Uint8List.fromList(utf8.encode('# fixed\n')),
      ),
      OutgoingFile(
        path: 'run.sh',
        kind: ChangeKind.modified,
        bytes: Uint8List.fromList(utf8.encode('echo hi\n')),
        mode: '100755',
      ),
      const OutgoingFile(path: 'old.txt', kind: ChangeKind.deleted),
    ];

/// A GitHub that accepts everything. [push] decides whether the user can
/// push to `up/proj` directly.
FakeTransport github({required bool push}) {
  int blobs = 0;
  return FakeTransport()
    ..onJson('GET', 'api.github.com/user', <String, Object?>{'login': 'me'})
    ..onJson('GET', 'api.github.com/repos/up/proj', <String, Object?>{
      'permissions': <String, Object?>{'push': push},
    })
    ..onJson('POST', 'api.github.com/repos/up/proj/forks', <String, Object?>{
      'name': 'proj-fork',
      'owner': <String, Object?>{'login': 'me'},
    }, status: 202)
    ..onJson('GET', 'api.github.com/repos/[^/]+/[^/]+/git/commits/b+',
        <String, Object?>{
      'sha': base,
      'tree': <String, Object?>{'sha': 'basetree'},
    })
    ..on('POST', 'api.github.com/repos/[^/]+/[^/]+/git/blobs',
        (_) => jsonResponse(<String, Object?>{'sha': 'blob${++blobs}'},
            status: 201))
    ..onJson('POST', 'api.github.com/repos/[^/]+/[^/]+/git/trees',
        <String, Object?>{'sha': 'newtree'}, status: 201)
    ..onJson('POST', 'api.github.com/repos/[^/]+/[^/]+/git/commits',
        <String, Object?>{'sha': 'newcommit'}, status: 201)
    ..onJson('POST', 'api.github.com/repos/[^/]+/[^/]+/git/refs',
        <String, Object?>{'ref': 'refs/heads/tcode/fix'}, status: 201)
    ..onJson('POST', 'api.github.com/repos/up/proj/pulls', <String, Object?>{
      'html_url': 'https://github.com/up/proj/pull/7',
    }, status: 201);
}

GitHubClient client(FakeTransport net, {String? token = 'sekrit-123'}) =>
    GitHubClient(
      transport: net,
      token: token,
      pause: (_) async {},
    );

void main() {
  test('with push access: blobs, tree, commit, branch, pull request', () async {
    final FakeTransport net = github(push: true);
    final ChangeRequestResult result = await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );

    expect(result.url, 'https://github.com/up/proj/pull/7');
    expect(result.viaFork, isFalse);
    expect(net.log, <String>[
      'GET api.github.com/user',
      'GET api.github.com/repos/up/proj',
      'GET api.github.com/repos/up/proj/git/commits/$base',
      'POST api.github.com/repos/up/proj/git/blobs',
      'POST api.github.com/repos/up/proj/git/blobs',
      'POST api.github.com/repos/up/proj/git/trees',
      'POST api.github.com/repos/up/proj/git/commits',
      'POST api.github.com/repos/up/proj/git/refs',
      'POST api.github.com/repos/up/proj/pulls',
    ], reason: 'a deleted file uploads no blob');

    final Map<String, Object?> tree = net.bodyOf(5)! as Map<String, Object?>;
    expect(tree['base_tree'], 'basetree');
    expect(tree['tree'], <Object?>[
      <String, Object?>{
        'path': 'README.md',
        'mode': '100644',
        'type': 'blob',
        'sha': 'blob1',
      },
      <String, Object?>{
        'path': 'run.sh',
        'mode': '100755',
        'type': 'blob',
        'sha': 'blob2',
      },
      <String, Object?>{
        'path': 'old.txt',
        'mode': '100644',
        'type': 'blob',
        'sha': null,
      },
    ], reason: 'the executable bit survives and a null sha deletes');

    final Map<String, Object?> commit = net.bodyOf(6)! as Map<String, Object?>;
    expect(commit['parents'], <String>[base],
        reason: 'the commit sits on the downloaded version, not on the tip');
    expect(commit['message'], 'Fix typo in README');
    expect((net.bodyOf(7)! as Map<String, Object?>)['ref'],
        'refs/heads/tcode/fix');
    final Map<String, Object?> pull = net.bodyOf(8)! as Map<String, Object?>;
    expect(pull['head'], 'tcode/fix');
    expect(pull['base'], 'main');
    expect(pull['title'], 'Fix typo');

    final Map<String, Object?> blob = net.bodyOf(3)! as Map<String, Object?>;
    expect(blob['encoding'], 'base64');
    expect(utf8.decode(base64.decode(blob['content']! as String)), '# fixed\n');
  });

  test('without push access it forks, commits there, and opens from fork',
      () async {
    final FakeTransport net = github(push: false);
    final ChangeRequestResult result = await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );
    expect(result.viaFork, isTrue);
    expect(net.log, contains('POST api.github.com/repos/up/proj/forks'));
    expect(net.log, contains('POST api.github.com/repos/me/proj-fork/git/refs'));
    final Map<String, Object?> pull =
        net.bodyOf(net.requests.length - 1)! as Map<String, Object?>;
    expect(pull['head'], 'me:tcode/fix');
    expect(net.log.last, 'POST api.github.com/repos/up/proj/pulls',
        reason: 'the request is opened against the original repository');
  });

  test('waits for a new fork to become readable', () async {
    int checks = 0;
    final FakeTransport net = github(push: false)
      ..on('GET', 'api.github.com/repos/me/proj-fork/git/commits/b+', (_) {
        checks++;
        return checks < 3
            ? jsonResponse(<String, Object?>{'message': 'Not Found'},
                status: 404)
            : jsonResponse(<String, Object?>{
                'tree': <String, Object?>{'sha': 'basetree'},
              });
      });
    await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );
    expect(checks, greaterThanOrEqualTo(3));
  });

  test('an existing branch name is reported as that', () async {
    final FakeTransport net = github(push: true)
      ..onJson('POST', 'api.github.com/repos/up/proj/git/refs',
          <String, Object?>{'message': 'Reference already exists'},
          status: 422);
    await expectLater(
      client(net).submit(repo: repo, baseSha: base, draft: draft, files: files()),
      throwsA(
        isA<RemoteConflictFailure>().having(
          (RemoteConflictFailure f) => f.hint,
          'hint',
          contains('"tcode/fix" already exists'),
        ),
      ),
    );
    expect(net.log.last, 'POST api.github.com/repos/up/proj/git/refs',
        reason: 'no pull request is attempted after the branch failed');
  });

  test('a 401 is a token problem, and says which permissions are needed',
      () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/user',
          <String, Object?>{'message': 'Bad credentials'}, status: 401);
    await expectLater(
      client(net).whoAmI(),
      throwsA(
        isA<AuthFailure>().having(
          (AuthFailure f) => f.hint,
          'hint',
          allOf(contains('Pull requests'), isNot(contains('sekrit'))),
        ),
      ),
    );
  });

  test('an exhausted rate limit is reported as one, with the reset time',
      () async {
    final FakeTransport net = FakeTransport()
      ..on(
        'GET',
        'api.github.com/repos/up/proj/commits/main',
        (_) => jsonResponse(
          <String, Object?>{'message': 'API rate limit exceeded'},
          status: 403,
          headers: <String, String>{
            'x-ratelimit-remaining': '0',
            'x-ratelimit-reset': '1790000000',
          },
        ),
      );
    await expectLater(
      client(net, token: null).resolveBranch(repo),
      throwsA(isA<RateLimitFailure>()),
    );
  });

  test('a missing branch is not-found, not a conflict', () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/repos/up/proj/commits/main',
          <String, Object?>{'message': 'No commit found for SHA: main'},
          status: 422);
    await expectLater(
      client(net).resolveBranch(repo),
      throwsA(isA<RepositoryNotFoundFailure>()),
    );
  });

  test('a truncated tree is refused rather than half-compared', () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/repos/up/proj/git/trees/b+',
          <String, Object?>{'truncated': true, 'tree': <Object?>[]});
    await expectLater(
      client(net).remoteTree(repo, base),
      throwsA(isA<UnsupportedOperationFailure>()),
    );
  });

  test('the tree keeps files only, with their modes', () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/repos/up/proj/git/trees/b+',
          <String, Object?>{
        'truncated': false,
        'tree': <Object?>[
          <String, Object?>{'path': 'lib', 'type': 'tree', 'sha': 't'},
          <String, Object?>{
            'path': 'lib/a.dart',
            'type': 'blob',
            'sha': 's1',
            'mode': '100644',
          },
          <String, Object?>{'path': 'sub', 'type': 'commit', 'sha': 'c'},
        ],
      });
    final Map<String, RemoteEntry> tree =
        await client(net).remoteTree(repo, base);
    expect(tree.keys, <String>['lib/a.dart']);
    expect(tree['lib/a.dart']!.sha, 's1');
    expect(net.requests.single.uri.queryParameters['recursive'], '1');
  });

  test('the token goes in the Authorization header and nowhere else',
      () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'api.github.com/user', <String, Object?>{'login': 'me'});
    expect(await client(net).whoAmI(), 'me');
    expect(net.requests.single.headers['Authorization'], 'Bearer sekrit-123');
    expect(net.requests.single.uri.toString(), isNot(contains('sekrit')));
  });
}
