/// Recent workspaces and files: promotion, limits and storage.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/recents_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/features/workspace/application/recents_controller.dart';
import 'package:pocket_code/features/workspace/presentation/recent_list.dart';

import '../../support/fake_file_system.dart';

RecentWorkspace workspace(String name, {DateTime? at}) => RecentWorkspace(
      name: name,
      roots: <WorkspaceRoot>[
        WorkspaceRoot(
          providerScheme: 'io',
          rootId: '/w/$name',
          name: name,
          displayPath: '/w/$name',
        ),
      ],
      lastOpened: at ?? DateTime(2026),
    );

SupportStorage storageFor() {
  final FakeFileSystemProvider fs = FakeFileSystemProvider()
    ..seed(<String, String>{'/support/.keep': ''});
  return SupportStorage(provider: fs, rootId: '/support');
}

String nameOf(RecentWorkspace w) => w.name;

void main() {
  group('promote', () {
    test('puts the entry first', () {
      final List<RecentWorkspace> list =
          promote(<RecentWorkspace>[workspace('a')], workspace('b'), nameOf, 10);
      expect(list.map(nameOf), <String>['b', 'a']);
    });

    test('moves an existing entry rather than duplicating it', () {
      final List<RecentWorkspace> list = promote(
        <RecentWorkspace>[workspace('a'), workspace('b')],
        workspace('a'),
        nameOf,
        10,
      );
      expect(list.map(nameOf), <String>['a', 'b']);
      expect(list, hasLength(2));
    });

    test('trims to the cap, dropping the oldest', () {
      List<RecentWorkspace> list = <RecentWorkspace>[];
      for (int i = 0; i < 5; i++) {
        list = promote(list, workspace('w$i'), nameOf, 3);
      }
      expect(list.map(nameOf), <String>['w4', 'w3', 'w2']);
    });

    test('an entry already at the front stays there', () {
      final List<RecentWorkspace> list = promote(
        <RecentWorkspace>[workspace('a'), workspace('b')],
        workspace('a'),
        nameOf,
        10,
      );
      expect(list.first.name, 'a');
    });
  });

  group('identity', () {
    test('a workspace is identified by its roots', () {
      expect(workspace('a').key, '/w/a');
    });

    test('a file is identified by provider and id together', () {
      // The same path under two providers is two different files.
      final RecentFile io = RecentFile(
        providerScheme: 'io',
        fileId: '/a.txt',
        name: 'a.txt',
        lastOpened: DateTime(2026),
      );
      final RecentFile saf = RecentFile(
        providerScheme: 'saf',
        fileId: '/a.txt',
        name: 'a.txt',
        lastOpened: DateTime(2026),
      );
      expect(recentFileKey(io), isNot(recentFileKey(saf)));
    });
  });

  group('limits are the ones already declared', () {
    test('workspaces and files have their own caps', () {
      expect(AppLimits.maxRecentWorkspaces, 20);
      expect(AppLimits.maxRecentFiles, 50);
    });
  });

  group('repository', () {
    test('round trips both lists', () async {
      final RecentsRepository repo = RecentsRepository(storageFor());
      await repo.save(RecentItems(
        workspaces: <RecentWorkspace>[workspace('a')],
        files: <RecentFile>[
          RecentFile(
            providerScheme: 'io',
            fileId: '/a.txt',
            name: 'a.txt',
            lastOpened: DateTime(2026, 5, 4),
          ),
        ],
      ));

      final RecentItems back = await repo.load();
      expect(back.workspaces.single.name, 'a');
      expect(back.files.single.fileId, '/a.txt');
      expect(back.files.single.lastOpened, DateTime(2026, 5, 4));
    });

    test('nothing stored loads as empty', () async {
      expect((await RecentsRepository(storageFor()).load()).isEmpty, isTrue);
    });

    test('corrupt json loads as empty rather than throwing', () async {
      final SupportStorage storage = storageFor();
      await storage.writeTextFile(
        storage.idFor(RecentsRepository.fileName),
        '{ not json',
      );
      expect((await RecentsRepository(storage).load()).isEmpty, isTrue);
    });

    test('a malformed entry is skipped, the rest survive', () async {
      final SupportStorage storage = storageFor();
      await storage.writeJson(RecentsRepository.fileName, <String, Object?>{
        'version': 1,
        'workspaces': <Object?>['not a map', workspace('good').toJson()],
        'files': <Object?>[],
      });
      final RecentItems back = await RecentsRepository(storage).load();
      expect(back.workspaces.map(nameOf), <String>['good']);
    });
  });

  group('relativeTime', () {
    final DateTime now = DateTime(2026, 6, 15, 12);

    test('reads in coarse units', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 20)), now: now),
          'just now');
      expect(relativeTime(now.subtract(const Duration(minutes: 5)), now: now),
          '5m ago');
      expect(relativeTime(now.subtract(const Duration(hours: 3)), now: now),
          '3h ago');
      expect(relativeTime(now.subtract(const Duration(days: 2)), now: now),
          '2d ago');
      expect(relativeTime(now.subtract(const Duration(days: 20)), now: now),
          '2w ago');
      expect(relativeTime(now.subtract(const Duration(days: 800)), now: now),
          '2y ago');
    });
  });
}
