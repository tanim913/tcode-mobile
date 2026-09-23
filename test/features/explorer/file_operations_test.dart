/// Tests for the destructive half of the explorer: move, copy, conflict
/// resolution, delete-to-trash and undo.
///
/// These paths can lose a user's files if they are wrong, which is why they get
/// the most direct coverage in the project.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/file_operations.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/clipboard/file_clipboard.dart';

import '../../support/fake_file_system.dart';
import '../../support/harness.dart';

FakeFileSystemProvider seeded() {
  return FakeFileSystemProvider()
    ..seed(<String, String>{
      '/workspace/a.txt': 'A',
      '/workspace/b.txt': 'B',
      '/workspace/dest/': '',
      '/workspace/dest/a.txt': 'existing A',
      '/workspace/src/one.txt': '1',
      '/workspace/src/nested/two.txt': '2',
    });
}

Future<ProviderContainer> containerFor(FakeFileSystemProvider provider) async {
  final repo = await fakeSettingsRepository();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
      workspaceProvider.overrideWith(
        () => FixedWorkspaceController(workspaceFor(provider)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

ClipboardItem itemFor(String path, {bool folder = false}) => ClipboardItem(
      rootIndex: 0,
      node: folder
          ? FolderNode(id: path, name: path.split('/').last, displayPath: path)
          : FileNode(id: path, name: path.split('/').last, displayPath: path),
    );

/// Always answers the conflict dialog the same way.
ConflictResolver always(ConflictChoice choice) =>
    (ConflictRequest _) async =>
        ConflictDecision(choice, applyToAll: true);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('copy into another folder', () {
    test('copies a file and leaves the original', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final FileOpOutcome outcome =
          await c.read(fileOperationsProvider).transfer(
                items: <ClipboardItem>[itemFor('/workspace/b.txt')],
                targetRootIndex: 0,
                targetFolderId: '/workspace/dest',
                move: false,
                resolve: always(ConflictChoice.skip),
              );

      expect(outcome.ok, isTrue);
      expect(fs.fs.file('/workspace/dest/b.txt').readAsStringSync(), 'B');
      expect(fs.fs.file('/workspace/b.txt').existsSync(), isTrue);
    });

    test('copies a folder tree recursively', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      await c.read(fileOperationsProvider).transfer(
            items: <ClipboardItem>[itemFor('/workspace/src', folder: true)],
            targetRootIndex: 0,
            targetFolderId: '/workspace/dest',
            move: false,
            resolve: always(ConflictChoice.skip),
          );

      expect(fs.fs.file('/workspace/dest/src/one.txt').readAsStringSync(), '1');
      expect(
        fs.fs.file('/workspace/dest/src/nested/two.txt').readAsStringSync(),
        '2',
      );
    });
  });

  group('move', () {
    test('moving removes the original', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      await c.read(fileOperationsProvider).transfer(
            items: <ClipboardItem>[itemFor('/workspace/b.txt')],
            targetRootIndex: 0,
            targetFolderId: '/workspace/dest',
            move: true,
            resolve: always(ConflictChoice.skip),
          );

      expect(fs.fs.file('/workspace/dest/b.txt').readAsStringSync(), 'B');
      expect(fs.fs.file('/workspace/b.txt').existsSync(), isFalse);
    });

    test('moving into the folder it already lives in changes nothing', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final FileOpOutcome outcome =
          await c.read(fileOperationsProvider).transfer(
                items: <ClipboardItem>[itemFor('/workspace/a.txt')],
                targetRootIndex: 0,
                targetFolderId: '/workspace',
                move: true,
                resolve: always(ConflictChoice.skip),
              );

      expect(outcome.changed, 0);
      expect(fs.fs.file('/workspace/a.txt').readAsStringSync(), 'A');
    });
  });

  group('same-folder copy auto-names', () {
    test('copying into its own folder produces "copy" without asking',
        () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      bool asked = false;

      await c.read(fileOperationsProvider).transfer(
            items: <ClipboardItem>[itemFor('/workspace/a.txt')],
            targetRootIndex: 0,
            targetFolderId: '/workspace',
            move: false,
            resolve: (ConflictRequest _) async {
              asked = true;
              return const ConflictDecision(ConflictChoice.skip);
            },
          );

      expect(asked, isFalse, reason: 'a same-folder copy is unambiguous');
      expect(fs.fs.file('/workspace/a copy.txt').readAsStringSync(), 'A');
    });

    test('duplicate produces copy, then copy 2', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      final FileOperations ops = c.read(fileOperationsProvider);

      await ops.duplicate(<ClipboardItem>[itemFor('/workspace/a.txt')]);
      await ops.duplicate(<ClipboardItem>[itemFor('/workspace/a.txt')]);

      expect(fs.fs.file('/workspace/a copy.txt').existsSync(), isTrue);
      expect(fs.fs.file('/workspace/a copy 2.txt').existsSync(), isTrue);
    });
  });

  group('conflicts in a different folder', () {
    test('skip leaves the existing file untouched', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final FileOpOutcome outcome =
          await c.read(fileOperationsProvider).transfer(
                items: <ClipboardItem>[itemFor('/workspace/a.txt')],
                targetRootIndex: 0,
                targetFolderId: '/workspace/dest',
                move: false,
                resolve: always(ConflictChoice.skip),
              );

      expect(outcome.skipped, 1);
      expect(
        fs.fs.file('/workspace/dest/a.txt').readAsStringSync(),
        'existing A',
      );
    });

    test('replace overwrites the destination', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      await c.read(fileOperationsProvider).transfer(
            items: <ClipboardItem>[itemFor('/workspace/a.txt')],
            targetRootIndex: 0,
            targetFolderId: '/workspace/dest',
            move: false,
            resolve: always(ConflictChoice.replace),
          );

      expect(fs.fs.file('/workspace/dest/a.txt').readAsStringSync(), 'A');
    });

    test('keep both writes alongside, preserving the original', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      await c.read(fileOperationsProvider).transfer(
            items: <ClipboardItem>[itemFor('/workspace/a.txt')],
            targetRootIndex: 0,
            targetFolderId: '/workspace/dest',
            move: false,
            resolve: always(ConflictChoice.keepBoth),
          );

      expect(
        fs.fs.file('/workspace/dest/a.txt').readAsStringSync(),
        'existing A',
        reason: 'keep both must not touch what was already there',
      );
      expect(fs.fs.file('/workspace/dest/a copy.txt').readAsStringSync(), 'A');
    });
  });

  group('folder-into-itself guard', () {
    test('isWithin walks the parent chain rather than comparing strings', () {
      final FakeFileSystemProvider fs = seeded();
      expect(
        FileOperations.isWithin(fs, '/workspace/src', '/workspace/src/nested'),
        isTrue,
      );
      expect(
        FileOperations.isWithin(fs, '/workspace/src', '/workspace/src'),
        isTrue,
      );
      // A sibling sharing a name prefix is not a descendant. A startsWith
      // check would get this wrong and block a legitimate move.
      expect(
        FileOperations.isWithin(fs, '/workspace/src', '/workspace/src-backup'),
        isFalse,
      );
    });

    test('moving a folder into its own descendant is refused', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final FileOpOutcome outcome =
          await c.read(fileOperationsProvider).transfer(
                items: <ClipboardItem>[itemFor('/workspace/src', folder: true)],
                targetRootIndex: 0,
                targetFolderId: '/workspace/src/nested',
                move: true,
                resolve: always(ConflictChoice.replace),
              );

      expect(outcome.ok, isFalse);
      expect(outcome.failure, isA<UnsupportedOperationFailure>());
      expect(
        fs.fs.file('/workspace/src/nested/two.txt').existsSync(),
        isTrue,
        reason: 'the tree must be intact after a refused move',
      );
    });
  });

  group('delete and undo', () {
    test('deleting moves to the trash, not oblivion', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final DeleteOutcome result = await c
          .read(fileOperationsProvider)
          .moveToTrash(<ClipboardItem>[itemFor('/workspace/a.txt')]);

      expect(result.outcome.ok, isTrue);
      expect(fs.fs.file('/workspace/a.txt').existsSync(), isFalse);
      expect(result.batch, isNotNull,
          reason: 'without a batch there is nothing to undo');
      expect(result.batch!.entries.single.name, 'a.txt');
    });

    test('undo puts the file back with its contents', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      final FileOperations ops = c.read(fileOperationsProvider);

      final DeleteOutcome result =
          await ops.moveToTrash(<ClipboardItem>[itemFor('/workspace/a.txt')]);
      final FileOpOutcome restored = await ops.restore(result.batch!);

      expect(restored.ok, isTrue);
      expect(fs.fs.file('/workspace/a.txt').readAsStringSync(), 'A');
    });

    test('undo restores a whole folder tree', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      final FileOperations ops = c.read(fileOperationsProvider);

      final DeleteOutcome result = await ops
          .moveToTrash(<ClipboardItem>[itemFor('/workspace/src', folder: true)]);
      expect(fs.fs.directory('/workspace/src').existsSync(), isFalse);

      await ops.restore(result.batch!);

      expect(fs.fs.file('/workspace/src/one.txt').readAsStringSync(), '1');
      expect(
        fs.fs.file('/workspace/src/nested/two.txt').readAsStringSync(),
        '2',
      );
    });

    test('deleting several items gives one undoable batch', () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      final FileOperations ops = c.read(fileOperationsProvider);

      final DeleteOutcome result = await ops.moveToTrash(<ClipboardItem>[
        itemFor('/workspace/a.txt'),
        itemFor('/workspace/b.txt'),
      ]);

      expect(result.batch!.entries.length, 2);
      await ops.restore(result.batch!);
      expect(fs.fs.file('/workspace/a.txt').existsSync(), isTrue);
      expect(fs.fs.file('/workspace/b.txt').existsSync(), isTrue);
    });

    test('deleting something already gone reports a failure, not a crash',
        () async {
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);

      final DeleteOutcome result = await c
          .read(fileOperationsProvider)
          .moveToTrash(<ClipboardItem>[itemFor('/workspace/ghost.txt')]);

      expect(result.outcome.ok, isFalse);
    });
  });

  group('relative paths', () {
    test('are relative to the workspace root with forward slashes', () {
      final FakeFileSystemProvider fs = seeded();
      expect(
        // ignore: discarded_futures
        containerFor(fs).then(
          (ProviderContainer c) => c.read(fileOperationsProvider).relativePath(
                0,
                const FileNode(
                  id: '/workspace/src/nested/two.txt',
                  name: 'two.txt',
                  displayPath: '/workspace/src/nested/two.txt',
                ),
              ),
        ),
        completion('src/nested/two.txt'),
      );
    });
  });
}
