/// The request sequence behind a GitLab merge request.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/gitlab_client.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

import '../../support/fake_transport.dart';

const RepoSource repo = RepoSource(
  host: RepoHost.gitlab,
  owner: 'grp',
  name: 'proj',
  branch: 'main',
);
final String base = 'c' * 40;

const ChangeRequestDraft draft = ChangeRequestDraft(
  title: 'Tidy',
  description: 'Details',
  commitMessage: 'Tidy things',
  branch: 'tcode/tidy',
);

List<OutgoingFile> files() => <OutgoingFile>[
      OutgoingFile(
        path: 'new.md',
        kind: ChangeKind.added,
        bytes: Uint8List.fromList(utf8.encode('hi')),
      ),
      OutgoingFile(
        path: 'bin/tool',
        kind: ChangeKind.modified,
        bytes: Uint8List.fromList(utf8.encode('x')),
        mode: '100755',
      ),
      const OutgoingFile(path: 'gone.txt', kind: ChangeKind.deleted),
    ];

FakeTransport gitlab({required int access}) => FakeTransport()
  ..onJson('GET', 'gitlab.com/api/v4/user', <String, Object?>{'username': 'me'})
  ..onJson('GET', 'gitlab.com/api/v4/projects/grp%2Fproj', <String, Object?>{
    'id': 11,
    'permissions': <String, Object?>{
      'project_access': <String, Object?>{'access_level': access},
      'group_access': null,
    },
  })
  ..onJson('POST', 'gitlab.com/api/v4/projects/11/fork',
      <String, Object?>{'id': 22}, status: 201)
  ..onJson('GET', 'gitlab.com/api/v4/projects/22',
      <String, Object?>{'id': 22, 'import_status': 'finished'})
  ..onJson('POST', 'gitlab.com/api/v4/projects/\\d+/repository/commits',
      <String, Object?>{'id': 'newcommit'}, status: 201)
  ..onJson('POST', 'gitlab.com/api/v4/projects/\\d+/merge_requests',
      <String, Object?>{'web_url': 'https://gitlab.com/grp/proj/-/merge_requests/3'},
      status: 201);

GitLabClient client(FakeTransport net) =>
    GitLabClient(transport: net, token: 'glpat-sekrit', pause: (_) async {});

void main() {
  test('as a developer: one commit call with every action, then the MR',
      () async {
    final FakeTransport net = gitlab(access: 30);
    final ChangeRequestResult result = await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );
    expect(result.url, 'https://gitlab.com/grp/proj/-/merge_requests/3');
    expect(result.viaFork, isFalse);
    expect(net.log, <String>[
      'GET gitlab.com/api/v4/user',
      'GET gitlab.com/api/v4/projects/grp%2Fproj',
      'POST gitlab.com/api/v4/projects/11/repository/commits',
      'POST gitlab.com/api/v4/projects/11/merge_requests',
    ]);

    final Map<String, Object?> commit = net.bodyOf(2)! as Map<String, Object?>;
    expect(commit['branch'], 'tcode/tidy');
    expect(commit['start_sha'], base,
        reason: 'the branch starts at the downloaded commit');
    expect(commit['commit_message'], 'Tidy things');
    final List<Object?> actions = commit['actions']! as List<Object?>;
    expect(actions, hasLength(3));
    expect(actions[0], <String, Object?>{
      'action': 'create',
      'file_path': 'new.md',
      'content': base64.encode(utf8.encode('hi')),
      'encoding': 'base64',
    });
    expect((actions[1]! as Map<String, Object?>)['action'], 'update');
    expect((actions[1]! as Map<String, Object?>)['execute_filemode'], isTrue);
    expect(actions[2], <String, Object?>{
      'action': 'delete',
      'file_path': 'gone.txt',
    });

    final Map<String, Object?> mr = net.bodyOf(3)! as Map<String, Object?>;
    expect(mr['source_branch'], 'tcode/tidy');
    expect(mr['target_branch'], 'main');
    expect(mr.containsKey('target_project_id'), isFalse);
  });

  test('below developer it forks and targets the original project', () async {
    final FakeTransport net = gitlab(access: 20);
    final ChangeRequestResult result = await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );
    expect(result.viaFork, isTrue);
    expect(net.log, contains('POST gitlab.com/api/v4/projects/11/fork'));
    expect(net.log,
        contains('POST gitlab.com/api/v4/projects/22/repository/commits'));
    final Map<String, Object?> mr =
        net.bodyOf(net.requests.length - 1)! as Map<String, Object?>;
    expect(net.log.last, 'POST gitlab.com/api/v4/projects/22/merge_requests');
    expect(mr['target_project_id'], 11);
  });

  test('an existing fork is found instead of failing', () async {
    final FakeTransport net = gitlab(access: 10)
      ..onJson('POST', 'gitlab.com/api/v4/projects/11/fork', <String, Object?>{
        'message': <String, Object?>{
          'name': <String>['has already been taken'],
        },
      }, status: 409)
      ..onJson('GET', 'gitlab.com/api/v4/projects/11/forks', <Object?>[
        <String, Object?>{'id': 22},
      ]);
    final ChangeRequestResult result = await client(net).submit(
      repo: repo,
      baseSha: base,
      draft: draft,
      files: files(),
    );
    expect(result.viaFork, isTrue);
    expect(
      net.requests
          .firstWhere((TransportRequest r) => r.uri.path.endsWith('/forks'))
          .uri
          .queryParameters['owned'],
      'true',
    );
  });

  test('a taken branch name is reported as that', () async {
    final FakeTransport net = gitlab(access: 40)
      ..onJson('POST', 'gitlab.com/api/v4/projects/11/repository/commits',
          <String, Object?>{'message': "A branch called 'tcode/tidy' already exists"},
          status: 400);
    await expectLater(
      client(net).submit(repo: repo, baseSha: base, draft: draft, files: files()),
      throwsA(
        isA<RemoteConflictFailure>()
            .having((RemoteConflictFailure f) => f.hint, 'hint',
                contains('Pick another branch name')),
      ),
    );
  });

  test('the tree is paged until GitLab stops sending a next page', () async {
    final FakeTransport net = FakeTransport()
      ..on('GET', 'gitlab.com/api/v4/projects/grp%2Fproj/repository/tree',
          (TransportRequest r) {
        final String page = r.uri.queryParameters['page']!;
        return jsonResponse(
          <Object?>[
            <String, Object?>{
              'path': 'f$page.txt',
              'type': 'blob',
              'id': 'id$page',
              'mode': '100644',
            },
            <String, Object?>{'path': 'dir$page', 'type': 'tree', 'id': 't'},
          ],
          headers: <String, String>{
            'x-next-page': page == '1' ? '2' : '',
          },
        );
      });
    final Map<String, RemoteEntry> tree =
        await client(net).remoteTree(repo, base);
    expect(tree.keys, <String>['f1.txt', 'f2.txt']);
    expect(net.requests.first.uri.queryParameters['ref'], base);
  });

  test('the token goes in PRIVATE-TOKEN', () async {
    final FakeTransport net = gitlab(access: 30);
    expect(await client(net).whoAmI(), 'me');
    expect(net.requests.single.headers['PRIVATE-TOKEN'], 'glpat-sekrit');
  });

  test('401 is a token problem naming the api scope', () async {
    final FakeTransport net = FakeTransport()
      ..onJson('GET', 'gitlab.com/api/v4/user',
          <String, Object?>{'message': '401 Unauthorized'}, status: 401);
    await expectLater(
      client(net).whoAmI(),
      throwsA(isA<AuthFailure>().having(
          (AuthFailure f) => f.hint, 'hint', contains('"api"'))),
    );
  });
}
