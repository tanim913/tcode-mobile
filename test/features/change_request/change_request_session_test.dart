/// Scanning a downloaded folder for changes and handing them to the host.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/repo_link.dart';
import 'package:pocket_code/features/change_request/application/change_request_session.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_blob_sha.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/git_host/github_client.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

import '../../support/fake_file_system.dart';
import '../../support/fake_transport.dart';

String sha(String text) => gitBlobSha(Uint8List.fromList(utf8.encode(text)));

final String base = 'e' * 40;

/// A host whose tree holds what was downloaded, and which records the submit
/// instead of sending it.
class RecordingClient extends GitHubClient {
  RecordingClient() : super(transport: FakeTransport(), token: 't');

  List<OutgoingFile>? sent;
  String? sentBase;

  @override
  Future<Map<String, RemoteEntry>> remoteTree(
    RepoSource repo,
    String sha,
  ) async =>
      <String, RemoteEntry>{
        'README.md': RemoteEntry(sha: _hash('# hi\n'), mode: '100644'),
        'run.sh': RemoteEntry(sha: _hash('echo\n'), mode: '100755'),
        'old.txt': RemoteEntry(sha: _hash('old'), mode: '100644'),
        'ignored.bin': const RemoteEntry(sha: 'x', mode: '100644'),
      };

  static String _hash(String text) => sha(text);

  @override
  Future<Uint8List> readBlob(RepoSource repo, String blobSha) async =>
      Uint8List.fromList(utf8.encode('# hi\n'));

  @override
  Future<ChangeRequestResult> submit({
    required RepoSource repo,
    required String baseSha,
    required ChangeRequestDraft draft,
    required List<OutgoingFile> files,
    SubmitProgressCallback? onProgress,
  }) async {
    sent = files;
    sentBase = baseSha;
    return ChangeRequestResult(url: 'u', branch: draft.branch, viaFork: false);
  }
}

void main() {
  late FakeFileSystemProvider fs;
  late RecordingClient client;
  late ChangeRequestSession session;

  setUp(() {
    fs = FakeFileSystemProvider()
      ..seed(<String, String>{
        '/r/README.md': '# hello\n', // modified
        '/r/run.sh': 'echo\n', // unchanged
        '/r/new.txt': 'new', // added
        // old.txt was deleted locally.
        '/r/.tcode/repo.json': '{}',
        '/r/.tcode/files': 'README.md\nrun.sh\nold.txt',
      });
    client = RecordingClient();
    session = ChangeRequestSession(
      provider: fs,
      folderId: '/r',
      link: RepoLink(
        host: RepoHost.github,
        owner: 'o',
        name: 'r',
        branch: 'main',
        baseSha: base,
        downloadedAt: DateTime.utc(2026),
      ),
      client: client,
    );
  });

  test('finds added, modified and deleted, and nothing of .tcode', () async {
    final List<FileChange> changes = await session.scan();
    expect(changes.map((FileChange c) => c.toString()), <String>[
      'M README.md',
      'A new.txt',
      'D old.txt',
    ], reason: 'ignored.bin was never downloaded, so it is not deleted');
  });

  test('the diff shows the base blob against the file on disk', () async {
    final List<FileChange> changes = await session.scan();
    final (String before, String after) = await session.textsOf(changes.first);
    expect(before, '# hi\n');
    expect(after, '# hello\n');
  });

  test('submits only the ticked files, re-read from disk, with modes',
      () async {
    final List<FileChange> changes = await session.scan();
    // Edited after the scan: what is sent must be what is on disk now.
    await fs.writeBytes('/r/README.md', Uint8List.fromList(utf8.encode('v3')));

    await session.submit(
      const ChangeRequestDraft(
        title: 't',
        description: '',
        commitMessage: 'm',
        branch: 'b',
      ),
      <FileChange>[changes[0], changes[2]],
    );

    expect(client.sentBase, base);
    expect(client.sent!.map((OutgoingFile f) => f.path),
        <String>['README.md', 'old.txt']);
    expect(utf8.decode(client.sent![0].bytes!), 'v3');
    expect(client.sent![1].bytes, isNull);
  });

  test('branch names', () {
    expect(defaultBranchName(DateTime(2026, 9, 2, 7, 5)), 'tcode/20260902-0705');
    expect(branchNameProblem('tcode/fix-1'), isNull);
    expect(branchNameProblem(''), isNotNull);
    expect(branchNameProblem('has space'), isNotNull);
    expect(branchNameProblem('a..b'), isNotNull);
    expect(branchNameProblem('end/'), isNotNull);
    expect(branchNameProblem('x.lock'), isNotNull);
  });
}
