/// Every state of the pull request screen, and one whole trip through it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/repositories/credentials_repository.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/change_request/presentation/change_request_screen.dart';
import 'package:pocket_code/services/git_host/git_blob_sha.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

import '../../data/credentials_repository_test.dart' show MapStore;
import '../../support/fake_file_system.dart';
import '../../support/fake_transport.dart';
import '../../support/harness.dart';

final String base = 'a' * 40;

String link({bool withBase = true}) =>
    '{"host":"github","owner":"up","name":"proj","branch":"main"'
    '${withBase ? ',"baseSha":"$base"' : ''}}';

FakeFileSystemProvider repoFolder({String? linkJson}) =>
    FakeFileSystemProvider()
      ..seed(<String, String>{
        '/p/README.md': '# changed\n',
        '/p/keep.txt': 'same',
        '/p/.tcode/repo.json': ?linkJson,
        '/p/.tcode/files': 'README.md\nkeep.txt',
      });

/// GitHub serving the downloaded tree and accepting a pull request.
FakeTransport github() => FakeTransport()
  ..onJson('GET', 'api.github.com/repos/up/proj/git/trees/a+', <String, Object?>{
    'truncated': false,
    'tree': <Object?>[
      <String, Object?>{
        'path': 'README.md',
        'type': 'blob',
        'sha': gitBlobSha(Uint8List.fromList('# old\n'.codeUnits)),
        'mode': '100644',
      },
      <String, Object?>{
        'path': 'keep.txt',
        'type': 'blob',
        'sha': gitBlobSha(Uint8List.fromList('same'.codeUnits)),
        'mode': '100644',
      },
    ],
  })
  ..onJson('GET', 'api.github.com/user', <String, Object?>{'login': 'me'})
  ..onJson('GET', 'api.github.com/repos/up/proj', <String, Object?>{
    'permissions': <String, Object?>{'push': true},
  })
  ..onJson('GET', 'api.github.com/repos/up/proj/git/commits/a+',
      <String, Object?>{'tree': <String, Object?>{'sha': 't'}})
  ..onJson('POST', 'api.github.com/repos/up/proj/git/blobs',
      <String, Object?>{'sha': 'b1'})
  ..onJson('POST', 'api.github.com/repos/up/proj/git/trees',
      <String, Object?>{'sha': 't2'})
  ..onJson('POST', 'api.github.com/repos/up/proj/git/commits',
      <String, Object?>{'sha': 'c2'})
  ..onJson('POST', 'api.github.com/repos/up/proj/git/refs',
      <String, Object?>{})
  ..onJson('POST', 'api.github.com/repos/up/proj/pulls', <String, Object?>{
    'html_url': 'https://github.com/up/proj/pull/9',
  });

Future<void> pumpScreen(
  WidgetTester tester,
  FakeFileSystemProvider fs, {
  FakeTransport? net,
  bool signedIn = true,
}) async {
  final MapStore store = MapStore();
  if (signedIn) {
    await CredentialsRepository(store)
        .save(RepoHost.github, token: 'sekrit', username: 'me');
  }
  await pumpInApp(
    tester,
    ChangeRequestScreen(provider: fs, folderId: '/p', folderName: 'proj'),
    overrides: <Override>[
      httpTransportProvider.overrideWithValue(net ?? github()),
      credentialsRepositoryProvider
          .overrideWithValue(CredentialsRepository(store)),
    ],
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a folder that was not downloaded says so', (tester) async {
    await pumpScreen(tester, repoFolder());
    expect(find.text('Not a downloaded repository'), findsOneWidget);
  });

  testWidgets('a download with no recorded commit says to download again',
      (tester) async {
    await pumpScreen(tester, repoFolder(linkJson: link(withBase: false)));
    expect(find.text('The downloaded commit is unknown'), findsOneWidget);
  });

  testWidgets('no token leads to Accounts', (tester) async {
    await pumpScreen(tester, repoFolder(linkJson: link()), signedIn: false);
    expect(find.text('Sign in to GitHub first'), findsOneWidget);
    expect(find.text('Open Accounts'), findsOneWidget);
  });

  testWidgets('lists what changed, and opens the pull request', (tester) async {
    final FakeTransport net = github();
    await pumpScreen(tester, repoFolder(linkJson: link()), net: net);

    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('keep.txt'), findsNothing, reason: 'unchanged');
    expect(find.text('Give the pull request a title'), findsOneWidget,
        reason: 'the button says why it is disabled');

    await tester.enterText(
        find.widgetWithText(TextField, 'Title'), 'Fix the readme');
    await tester.pump();
    final Finder send = find.text('Open pull request with 1 file');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.text('Pull request opened'), findsOneWidget);
    expect(find.text('https://github.com/up/proj/pull/9'), findsOneWidget);
    expect(net.log.last, 'POST api.github.com/repos/up/proj/pulls');
  });

  testWidgets('a refusal from the host is shown, and the form survives',
      (tester) async {
    final FakeTransport net = github()
      ..onJson('POST', 'api.github.com/repos/up/proj/git/refs',
          <String, Object?>{'message': 'Reference already exists'},
          status: 422);
    await pumpScreen(tester, repoFolder(linkJson: link()), net: net);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'x');
    await tester.pump();
    final Finder send = find.text('Open pull request with 1 file');
    await tester.ensureVisible(send);
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(find.textContaining('already exists there'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
  });
}
