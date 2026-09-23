/// Downloading a repository and unpacking it.
///
/// The network is faked so the archive handling — which is where the damage
/// would be — is covered without reaching anything.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/features/repo/application/download_repo.dart';
import 'package:pocket_code/services/git_host/github_client.dart';
import 'package:pocket_code/services/git_host/http_transport.dart';
import 'package:pocket_code/services/git_host/repo_link_store.dart';
import 'package:pocket_code/services/repo/repo_download.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

import '../../support/fake_file_system.dart';
import '../../support/fake_transport.dart';

const RepoSource source = RepoSource(
  host: RepoHost.github,
  owner: 'flutter',
  name: 'samples',
  branch: 'main',
);

/// An archive shaped like the real thing: one wrapping `repo-branch/` folder.
Uint8List wrappedArchive({String root = 'samples-main'}) {
  final Archive archive = Archive()
    ..addFile(ArchiveFile.directory('$root/'))
    ..addFile(
      ArchiveFile.bytes(
        '$root/README.md',
        Uint8List.fromList('# samples'.codeUnits),
      ),
    )
    ..addFile(
      ArchiveFile.bytes(
        '$root/lib/main.dart',
        Uint8List.fromList('void main() {}'.codeUnits),
      ),
    );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class FakeDownload implements RepoDownload {
  FakeDownload(this._bytes, {this.available = true});

  final Uint8List? _bytes;
  final bool available;
  Uri? requested;

  @override
  bool get isAvailable => available;

  @override
  String get unavailableReason => 'no network in this build';

  @override
  Future<Uint8List> fetch(Uri url, {DownloadProgressCallback? onProgress}) async {
    requested = url;
    if (!available) {
      throw UnsupportedOperationFailure(what: unavailableReason);
    }
    if (_bytes == null) {
      throw const RepositoryNotFoundFailure();
    }
    onProgress?.call(
      DownloadProgress(received: _bytes.length, total: _bytes.length),
    );
    return _bytes;
  }
}

FakeFileSystemProvider target() =>
    FakeFileSystemProvider()..seed(<String, String>{'/projects/': ''});

void main() {
  test('unpacks the archive into a folder named after the repository',
      () async {
    final FakeFileSystemProvider fs = target();
    final FakeDownload net = FakeDownload(wrappedArchive());

    final FolderNode folder = await RepoInstaller(download: net).install(
      source: source,
      provider: fs,
      parentId: '/projects',
    );

    expect(folder.name, 'samples');
    expect(net.requested!.host, 'codeload.github.com');
  });

  test('the returned folder is the repository, not the folder holding them',
      () async {
    // The welcome screen opens what this returns. It used to open the whole
    // Projects folder instead, so downloading a second repository showed the
    // first one sitting beside it and looked as though closing the project had
    // not worked.
    final FakeFileSystemProvider fs = target();
    await RepoInstaller(download: FakeDownload(wrappedArchive())).install(
      source: source,
      provider: fs,
      parentId: '/projects',
    );

    final FolderNode second =
        await RepoInstaller(download: FakeDownload(wrappedArchive(root: 'other-main')))
            .install(
      source: const RepoSource(
        host: RepoHost.github,
        owner: 'flutter',
        name: 'other',
        branch: 'main',
      ),
      provider: fs,
      parentId: '/projects',
    );

    expect(second.id, '/projects/other');
    expect(second.name, 'other');

    // Both still exist on disk — Projects is the library — but the id handed
    // back names only the one just downloaded.
    expect(fs.fs.directory('/projects/samples').existsSync(), isTrue);
    final List<FileSystemNode> inSecond = await fs.list(second.id);
    expect(
      inSecond.map((FileSystemNode n) => n.name),
      isNot(contains('samples')),
      reason: 'opening the downloaded repo must not show the previous one',
    );
  });

  test('flattens the wrapping folder the host adds', () async {
    final FakeFileSystemProvider fs = target();

    await RepoInstaller(download: FakeDownload(wrappedArchive())).install(
      source: source,
      provider: fs,
      parentId: '/projects',
    );

    // Without flattening the user opens a folder containing one folder.
    expect(fs.fs.file('/projects/samples/README.md').existsSync(), isTrue);
    expect(fs.fs.file('/projects/samples/lib/main.dart').existsSync(), isTrue);
    expect(fs.fs.directory('/projects/samples/samples-main').existsSync(),
        isFalse);
  });

  test('leaves an archive with several top-level entries alone', () async {
    final Archive archive = Archive()
      ..addFile(ArchiveFile.bytes('a.txt', Uint8List.fromList('a'.codeUnits)))
      ..addFile(ArchiveFile.bytes('b.txt', Uint8List.fromList('b'.codeUnits)));
    final FakeFileSystemProvider fs = target();

    await RepoInstaller(
      download: FakeDownload(Uint8List.fromList(ZipEncoder().encode(archive))),
    ).install(source: source, provider: fs, parentId: '/projects');

    expect(fs.fs.file('/projects/samples/a.txt').existsSync(), isTrue);
    expect(fs.fs.file('/projects/samples/b.txt').existsSync(), isTrue);
  });

  test('a missing repository or branch says so, in those words', () async {
    // It used to reuse NotFoundFailure, whose hint is "refresh the explorer" —
    // advice about a file on this device, shown when the real cause was a
    // branch called "main" that does not exist on the remote.
    final FakeFileSystemProvider fs = target();
    final RepoInstaller installer = RepoInstaller(download: FakeDownload(null));

    await expectLater(
      installer.install(source: source, provider: fs, parentId: '/projects'),
      throwsA(isA<RepositoryNotFoundFailure>()),
    );

    const AppFailure failure = RepositoryNotFoundFailure();
    expect(failure.hint.toLowerCase(), contains('master'),
        reason: 'the commonest cause is the default branch name');
    expect(failure.hint.toLowerCase(), isNot(contains('refresh the explorer')),
        reason: 'that is advice about a file on this device');
  });

  test('a 404 does not claim the repository is missing', () {
    // GitHub answers 404 for a private repository exactly as for a missing
    // one, so that an unauthenticated client cannot discover that a private
    // repository exists. Saying "does not exist" would be a guess, and wrong
    // for every private repository anyone tries.
    const AppFailure failure = RepositoryNotFoundFailure();
    expect(failure.hint.toLowerCase(), contains('private'),
        reason: 'privacy is one of the three causes and must be named');
    expect(failure.message.toLowerCase(), isNot(contains('does not exist')));
    expect(failure.message.toLowerCase(), isNot(contains('no repository')));
  });

  test('a sign-in response does not claim the repository is private', () {
    // GitLab redirects to its sign-in page for a private project and for a
    // mistyped name alike, and both end as 403.
    const AppFailure failure = RepositoryPrivateFailure();
    expect(failure.hint.toLowerCase(), contains('name is wrong'),
        reason: 'the other cause must be named too');
    expect(failure.hint, contains('Settings → Accounts'),
        reason: 'a token is now the way in, and the hint must say where');
    expect(failure.hint.toLowerCase(), isNot(contains('re-grant')));
  });

  test('refuses when a folder of that name already exists', () async {
    final FakeFileSystemProvider fs = target()
      ..seed(<String, String>{'/projects/samples/keep.txt': 'mine'});

    await expectLater(
      RepoInstaller(download: FakeDownload(wrappedArchive())).install(
        source: source,
        provider: fs,
        parentId: '/projects',
      ),
      throwsA(isA<AlreadyExistsFailure>()),
    );
    expect(fs.fs.file('/projects/samples/keep.txt').readAsStringSync(), 'mine',
        reason: 'an existing working copy must never be overwritten');
  });

  test('a failed download leaves no folder behind', () async {
    final FakeFileSystemProvider fs = target();

    await expectLater(
      RepoInstaller(download: FakeDownload(null)).install(
        source: source,
        provider: fs,
        parentId: '/projects',
      ),
      throwsA(isA<RepositoryNotFoundFailure>()),
    );
    expect(fs.fs.directory('/projects/samples').existsSync(), isFalse,
        reason: 'a half-made folder looks like a working checkout');
  });

  test('a corrupt archive leaves no folder behind', () async {
    final FakeFileSystemProvider fs = target();

    await expectLater(
      RepoInstaller(
        download: FakeDownload(Uint8List.fromList(<int>[1, 2, 3, 4])),
      ).install(source: source, provider: fs, parentId: '/projects'),
      throwsA(isA<UnknownFailure>()),
    );
    expect(fs.fs.directory('/projects/samples').existsSync(), isFalse);
  });

  test('a build with no network refuses before creating anything', () async {
    final FakeFileSystemProvider fs = target();

    await expectLater(
      RepoInstaller(download: FakeDownload(null, available: false)).install(
        source: source,
        provider: fs,
        parentId: '/projects',
      ),
      throwsA(isA<UnsupportedOperationFailure>()),
    );
    expect(fs.fs.directory('/projects/samples').existsSync(), isFalse);
  });

  group('progress fraction', () {
    test('is null until the size is known, so the bar stays indeterminate', () {
      expect(const RepoProgress(stage: RepoStage.downloading).fraction, isNull);
      expect(
        const RepoProgress(stage: RepoStage.downloading, received: 100)
            .fraction,
        isNull,
        reason: 'bytes received without a total cannot become a percentage',
      );
    });

    test('reports how far along once the total is known', () {
      expect(
        const RepoProgress(
          stage: RepoStage.downloading,
          received: 25,
          total: 100,
        ).fraction,
        0.25,
      );
    });

    test('cannot exceed one, however the server counts', () {
      expect(
        const RepoProgress(
          stage: RepoStage.downloading,
          received: 120,
          total: 100,
        ).fraction,
        1.0,
      );
      expect(
        const RepoProgress(
          stage: RepoStage.downloading,
          received: 5,
          total: 0,
        ).fraction,
        isNull,
      );
    });
  });

  test('reports progress through both stages', () async {
    final FakeFileSystemProvider fs = target();
    final List<RepoStage> stages = <RepoStage>[];

    await RepoInstaller(download: FakeDownload(wrappedArchive())).install(
      source: source,
      provider: fs,
      parentId: '/projects',
      onProgress: (RepoProgress p) => stages.add(p.stage),
    );

    expect(stages, contains(RepoStage.downloading));
    expect(stages, contains(RepoStage.unpacking));
  });

  group('recording where the folder came from', () {
    final String sha = 'd' * 40;

    FakeTransport api({bool resolves = true}) {
      final FakeTransport net = FakeTransport();
      if (resolves) {
        net.onJson('GET', 'api.github.com/repos/flutter/samples/commits/main',
            <String, Object?>{'sha': sha});
      }
      net.on(
        'GET',
        'api.github.com/repos/flutter/samples/zipball/d+',
        (_) => TransportResponse(status: 200, body: wrappedArchive()),
      );
      return net;
    }

    test('with a token, downloads through the API at the resolved commit',
        () async {
      final FakeFileSystemProvider fs = target();
      final FakeTransport net = api();
      final FakeDownload anonymous = FakeDownload(wrappedArchive());

      await RepoInstaller(
        download: anonymous,
        api: GitHubClient(transport: net, token: 'sekrit'),
        clock: () => DateTime.utc(2026, 9, 22),
      ).install(source: source, provider: fs, parentId: '/projects');

      expect(net.log, <String>[
        'GET api.github.com/repos/flutter/samples/commits/main',
        'GET api.github.com/repos/flutter/samples/zipball/$sha',
      ]);
      expect(anonymous.requested, isNull,
          reason: 'the anonymous route cannot reach a private repository');

      final RepoLink link =
          (await RepoLinkStore(fs).read('/projects/samples'))!;
      expect(link.baseSha, sha);
      expect(link.owner, 'flutter');
      expect(link.branch, 'main');
      expect(
        await RepoLinkStore(fs).downloadedFiles('/projects/samples'),
        <String>{'README.md', 'lib/main.dart'},
        reason: 'the list is what makes "deleted" exact',
      );
    });

    test('without a token, pins the anonymous archive to the resolved commit',
        () async {
      final FakeFileSystemProvider fs = target();
      final FakeDownload anonymous = FakeDownload(wrappedArchive());

      await RepoInstaller(
        download: anonymous,
        api: GitHubClient(transport: api()),
      ).install(source: source, provider: fs, parentId: '/projects');

      expect(anonymous.requested.toString(),
          'https://codeload.github.com/flutter/samples/zip/$sha');
      expect((await RepoLinkStore(fs).read('/projects/samples'))!.baseSha, sha);
    });

    test('if the commit cannot be resolved, the download still happens',
        () async {
      final FakeFileSystemProvider fs = target();
      final FakeDownload anonymous = FakeDownload(wrappedArchive());

      await RepoInstaller(
        download: anonymous,
        api: GitHubClient(transport: api(resolves: false)),
      ).install(source: source, provider: fs, parentId: '/projects');

      expect(anonymous.requested, source.archiveUrl);
      final RepoLink link =
          (await RepoLinkStore(fs).read('/projects/samples'))!;
      expect(link.baseSha, isNull);
      expect(link.canPropose, isFalse,
          reason: 'without the base every remote change would look reverted');
    });
  });
}
