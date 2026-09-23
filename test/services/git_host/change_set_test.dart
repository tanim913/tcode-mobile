library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/git_host/change_set.dart';

const RemoteEntry a1 = RemoteEntry(sha: 'a1', mode: '100644');
const RemoteEntry b1 = RemoteEntry(sha: 'b1', mode: '100644');
const RemoteEntry c1 = RemoteEntry(sha: 'c1', mode: '100644');

void main() {
  test('reports added, modified and deleted, sorted by path', () {
    final List<FileChange> changes = computeChanges(
      local: <String, String>{'a.txt': 'a1', 'b.txt': 'b2', 'new.txt': 'n'},
      remote: <String, RemoteEntry>{'a.txt': a1, 'b.txt': b1, 'c.txt': c1},
      downloaded: <String>{'a.txt', 'b.txt', 'c.txt'},
    );
    expect(changes.map((FileChange c) => c.toString()), <String>[
      'M b.txt',
      'D c.txt',
      'A new.txt',
    ]);
    expect(changes[0].baseSha, 'b1', reason: 'the diff needs the base blob');
    expect(changes[2].baseSha, isNull);
  });

  test('a remote file that was never downloaded is not reported deleted', () {
    // Archives honour export-ignore, so the tree can hold files the download
    // never had. Treating them as deleted would make the PR delete them.
    final List<FileChange> changes = computeChanges(
      local: <String, String>{'a.txt': 'a1'},
      remote: <String, RemoteEntry>{'a.txt': a1, 'tests/big.bin': b1},
      downloaded: <String>{'a.txt'},
    );
    expect(changes, isEmpty);
  });

  test("the app's own .tcode folder is never part of a change", () {
    final List<FileChange> changes = computeChanges(
      local: <String, String>{'.tcode/repo.json': 'x', '.tcode/files': 'y'},
      remote: const <String, RemoteEntry>{},
      downloaded: const <String>{},
    );
    expect(changes, isEmpty);
    expect(isRepoMetaPath('.tcode'), isTrue);
    expect(isRepoMetaPath('.tcodex/a'), isFalse);
  });

  test('symbolic links are left alone either way', () {
    const RemoteEntry link = RemoteEntry(sha: 'l1', mode: '120000');
    expect(
      computeChanges(
        local: <String, String>{'link': 'written-as-file'},
        remote: <String, RemoteEntry>{'link': link},
        downloaded: <String>{'link'},
      ),
      isEmpty,
    );
    expect(
      computeChanges(
        local: const <String, String>{},
        remote: <String, RemoteEntry>{'link': link},
        downloaded: <String>{'link'},
      ),
      isEmpty,
    );
  });
}
