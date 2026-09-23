/// File history: the key, the policy and the store.
///
/// Nearly all of this feature is pure, which is why the policy lives in its own
/// module — the rules about when to record and what to drop are the part that
/// would be impossible to trust otherwise.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/utils/relative_path.dart';
import 'package:pocket_code/core/utils/stable_hash.dart';
import 'package:pocket_code/data/models/file_version.dart';
import 'package:pocket_code/data/repositories/history_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/features/history/application/history_key.dart';
import 'package:pocket_code/features/history/application/history_policy.dart';

import '../../support/fake_file_system.dart';

const HistoryPolicy defaultPolicy = HistoryPolicy();

FileVersion version({
  required DateTime at,
  int bytes = 100,
  String hash = 'h',
}) =>
    FileVersion(
      stamp: at.microsecondsSinceEpoch,
      savedAt: at,
      byteLength: bytes,
      contentHash: hash,
    );

SupportStorage storageFor() {
  final FakeFileSystemProvider fs = FakeFileSystemProvider()
    ..seed(<String, String>{'/support/.keep': ''});
  return SupportStorage(provider: fs, rootId: '/support');
}

FakeFileSystemProvider workspace() => FakeFileSystemProvider()
  ..seed(<String, String>{
    '/w/lib/main.dart': 'void main() {}',
    '/w/README.md': '# hi',
  });

void main() {
  group('stableHash', () {
    test('is deterministic', () {
      expect(stableHash('abc'), stableHash('abc'));
    });

    test('separates different inputs', () {
      expect(stableHash('abc'), isNot(stableHash('abd')));
    });

    test('stays inside 32-bit arithmetic, so it works on the web', () {
      // A 64-bit FNV constant cannot be written as a literal in JavaScript,
      // and a 64-bit multiply loses precision in a double. The digest must be
      // plain hex with no sign and no exponent, whatever the platform.
      for (final String input in <String>['', 'a', 'x' * 300, 'io|lib/main.dart']) {
        expect(stableHash(input), matches(RegExp(r'^[0-9a-f]{16}$')),
            reason: 'for "$input"');
      }
    });

    test('is always the same width, so folder names line up', () {
      expect(stableHash(''), hasLength(16));
      expect(stableHash('a' * 500), hasLength(16));
    });
  });

  group('relativePathIn', () {
    test('walks parents rather than splitting the id', () {
      final FakeFileSystemProvider fs = workspace();
      expect(
        relativePathIn(fs, '/w', '/w/lib/main.dart', fallback: 'x'),
        'lib/main.dart',
      );
    });

    test('a file directly in the root has a bare name', () {
      final FakeFileSystemProvider fs = workspace();
      expect(relativePathIn(fs, '/w', '/w/README.md', fallback: 'x'), 'README.md');
    });

    test('a node outside the root falls back', () {
      final FakeFileSystemProvider fs = workspace();
      expect(
        relativePathIn(fs, '/other', '/w/README.md', fallback: 'fallback'),
        'fallback',
      );
    });
  });

  group('historyKeyFor', () {
    test('is the scheme plus the path relative to the root', () {
      final FakeFileSystemProvider fs = workspace();
      expect(
        historyKeyFor(
          provider: fs,
          rootId: '/w',
          fileId: '/w/lib/main.dart',
          fallbackName: 'main.dart',
        ),
        'fake|lib/main.dart',
      );
    });

    test('the same file keeps its key when the workspace moves', () {
      // The whole point: an absolute path or a SAF URI changes, the relative
      // path does not.
      final FakeFileSystemProvider before = FakeFileSystemProvider()
        ..seed(<String, String>{'/old/lib/main.dart': 'x'});
      final FakeFileSystemProvider after = FakeFileSystemProvider()
        ..seed(<String, String>{'/new/place/lib/main.dart': 'x'});

      expect(
        historyKeyFor(
          provider: before,
          rootId: '/old',
          fileId: '/old/lib/main.dart',
          fallbackName: 'main.dart',
        ),
        historyKeyFor(
          provider: after,
          rootId: '/new/place',
          fileId: '/new/place/lib/main.dart',
          fallbackName: 'main.dart',
        ),
      );
    });

    test('different files get different folders', () {
      final FakeFileSystemProvider fs = workspace();
      final String a = historyKeyFor(
        provider: fs,
        rootId: '/w',
        fileId: '/w/lib/main.dart',
        fallbackName: 'main.dart',
      );
      final String b = historyKeyFor(
        provider: fs,
        rootId: '/w',
        fileId: '/w/README.md',
        fallbackName: 'README.md',
      );
      expect(historyFolderFor(a), isNot(historyFolderFor(b)));
    });
  });

  group('rebasedKey', () {
    test('follows a renamed file', () {
      expect(rebasedKey('io|a.txt', 'a.txt', 'b.txt'), 'io|b.txt');
    });

    test('follows a file inside a renamed folder', () {
      // This is the case that would otherwise orphan history for every file
      // the user was not looking at.
      expect(
        rebasedKey('io|old/deep/a.txt', 'old', 'new'),
        'io|new/deep/a.txt',
      );
    });

    test('leaves unrelated keys alone', () {
      expect(rebasedKey('io|other/a.txt', 'old', 'new'), isNull);
      expect(rebasedKey('io|older/a.txt', 'old', 'new'), isNull,
          reason: 'a prefix must match a whole path segment');
    });
  });

  group('shouldSnapshot', () {
    final DateTime now = DateTime(2026, 6, 15, 12);

    bool check({
      FileVersion? newest,
      String previous = 'old text',
      String next = 'new text',
      bool explicit = true,
      HistoryPolicy policy = defaultPolicy,
    }) =>
        shouldSnapshot(
          now: now,
          newest: newest,
          previousText: previous,
          nextText: next,
          previousHash: stableHash(previous),
          explicit: explicit,
          policy: policy,
        );

    test('records the first version of a file', () {
      expect(check(), isTrue);
    });

    test('records nothing when the text did not change', () {
      expect(check(previous: 'same', next: 'same'), isFalse);
    });

    test('records nothing identical to the newest version', () {
      expect(
        check(newest: version(at: now, bytes: 8, hash: stableHash('old text'))),
        isFalse,
      );
    });

    test('an explicit save always records', () {
      expect(
        check(
          newest: version(at: now.subtract(const Duration(seconds: 1))),
        ),
        isTrue,
      );
    });

    test('an automatic save inside the interval is coalesced away', () {
      // Auto-save fires every second by default; without this there would be a
      // version per second of typing.
      expect(
        check(
          newest: version(at: now.subtract(const Duration(seconds: 2))),
          explicit: false,
        ),
        isFalse,
      );
    });

    test('an automatic save past the interval records', () {
      expect(
        check(
          newest: version(at: now.subtract(const Duration(minutes: 30))),
          explicit: false,
        ),
        isTrue,
      );
    });

    test('a large change beats the interval', () {
      expect(
        check(
          newest: version(at: now.subtract(const Duration(seconds: 2))),
          previous: 'x',
          next: 'y' * 900,
          explicit: false,
        ),
        isTrue,
        reason: 'pasting or deleting a block is worth keeping immediately',
      );
    });

    test('a very large file is not recorded at all', () {
      expect(
        check(
          previous: 'x' * 2000,
          policy: const HistoryPolicy(maxFileBytes: 1000),
        ),
        isFalse,
      );
    });
  });

  group('eviction', () {
    final DateTime now = DateTime(2026, 6, 15, 12);

    List<FileVersion> series(int count, {int bytes = 100}) => <FileVersion>[
          for (int i = 0; i < count; i++)
            version(at: now.subtract(Duration(minutes: i)), bytes: bytes),
        ];

    test('keeps the newest up to the count limit', () {
      final List<FileVersion> kept = keepVersions(
        series(10),
        now: now,
        policy: const HistoryPolicy(maxVersionsPerFile: 3),
      );
      expect(kept, hasLength(3));
      expect(kept.first.savedAt, now, reason: 'newest first');
    });

    test('drops anything past the age limit', () {
      final List<FileVersion> versions = <FileVersion>[
        version(at: now),
        version(at: now.subtract(const Duration(days: 40))),
      ];
      final List<FileVersion> kept = keepVersions(
        versions,
        now: now,
        policy: const HistoryPolicy(),
      );
      expect(kept, hasLength(1));
    });

    test('stops at the byte budget', () {
      final List<FileVersion> kept = keepVersions(
        series(10, bytes: 400),
        now: now,
        policy: const HistoryPolicy(maxBytesPerFile: 1000),
      );
      expect(kept, hasLength(2));
    });

    test('always keeps at least one, even if it exceeds the budget', () {
      // Otherwise a single large file would record nothing and look broken.
      final List<FileVersion> kept = keepVersions(
        <FileVersion>[version(at: now, bytes: 10000)],
        now: now,
        policy: const HistoryPolicy(maxBytesPerFile: 100),
      );
      expect(kept, hasLength(1));
    });

    test('evict is the complement of keep', () {
      final List<FileVersion> all = series(10);
      const HistoryPolicy policy = HistoryPolicy(maxVersionsPerFile: 4);
      expect(
        keepVersions(all, now: now, policy: policy).length +
            evictVersions(all, now: now, policy: policy).length,
        all.length,
      );
    });
  });

  group('repository', () {
    test('records a version and reads it back', () async {
      final HistoryRepository repo = HistoryRepository(storageFor());
      final DateTime at = DateTime(2026, 6, 15, 12);

      await repo.addVersion(
        key: 'io|a.txt',
        name: 'a.txt',
        displayPath: '/w/a.txt',
        text: 'first',
        contentHash: stableHash('first'),
        savedAt: at,
      );

      final HistoryFolder? folder = await repo.folderFor(
        'io|a.txt',
        name: 'a.txt',
        displayPath: '/w/a.txt',
      );
      expect(folder, isNotNull);
      expect(folder!.meta.versions, hasLength(1));
      expect(await repo.contentOf(folder.id, folder.meta.versions.first),
          'first');
    });

    test('newest first', () async {
      final HistoryRepository repo = HistoryRepository(storageFor());
      for (int i = 0; i < 3; i++) {
        await repo.addVersion(
          key: 'io|a.txt',
          name: 'a.txt',
          displayPath: '/w/a.txt',
          text: 'v$i',
          contentHash: stableHash('v$i'),
          savedAt: DateTime(2026, 6, 15, 12, i),
        );
      }
      final HistoryFolder folder = (await repo.folderFor(
        'io|a.txt',
        name: 'a.txt',
        displayPath: '/w/a.txt',
      ))!;
      expect(
        await repo.contentOf(folder.id, folder.meta.versions.first),
        'v2',
      );
    });

    test('a folder belonging to another key is not reused', () async {
      // The hash collision case. Without the stored key this would silently
      // mix two files' history together.
      final SupportStorage storage = storageFor();
      final HistoryRepository repo = HistoryRepository(storage);
      await repo.addVersion(
        key: 'io|a.txt',
        name: 'a.txt',
        displayPath: '/w/a.txt',
        text: 'mine',
        contentHash: stableHash('mine'),
        savedAt: DateTime(2026),
      );

      expect(
        await repo.folderFor('io|different.txt',
            name: 'different.txt', displayPath: '/w/different.txt'),
        isNull,
        reason: 'a different key must not resolve to that folder',
      );
    });

    test('unknown files have no folder until one is created', () async {
      final HistoryRepository repo = HistoryRepository(storageFor());
      expect(
        await repo.folderFor('io|never.txt',
            name: 'never.txt', displayPath: '/w/never.txt'),
        isNull,
      );
    });

    test('removing versions deletes their snapshots', () async {
      final HistoryRepository repo = HistoryRepository(storageFor());
      for (int i = 0; i < 3; i++) {
        await repo.addVersion(
          key: 'io|a.txt',
          name: 'a.txt',
          displayPath: '/w/a.txt',
          text: 'v$i',
          contentHash: stableHash('v$i'),
          savedAt: DateTime(2026, 6, 15, 12, i),
        );
      }
      HistoryFolder folder = (await repo.folderFor('io|a.txt',
          name: 'a.txt', displayPath: '/w/a.txt'))!;

      await repo.removeVersions(folder, folder.meta.versions.sublist(1));

      folder = (await repo.folderFor('io|a.txt',
          name: 'a.txt', displayPath: '/w/a.txt'))!;
      expect(folder.meta.versions, hasLength(1));
      expect(await repo.contentOf(folder.id, folder.meta.versions.first), 'v2');
    });

    test('clearing removes everything', () async {
      final HistoryRepository repo = HistoryRepository(storageFor());
      await repo.addVersion(
        key: 'io|a.txt',
        name: 'a.txt',
        displayPath: '/w/a.txt',
        text: 'x',
        contentHash: stableHash('x'),
        savedAt: DateTime(2026),
      );
      await repo.clearAll();
      expect(await repo.allFolders(), isEmpty);
    });
  });
}
