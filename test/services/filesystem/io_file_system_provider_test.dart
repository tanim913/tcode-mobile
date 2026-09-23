@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/filesystem/cancellation.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/io/io_file_system_provider.dart';

void main() {
  late Directory root;
  const IoFileSystemProvider fs = IoFileSystemProvider();

  setUp(() {
    root = Directory.systemTemp.createTempSync('pocket_code_test_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  String at(String relative) => p.join(root.path, relative);

  void writeFile(String relative, String content) {
    final File f = File(at(relative))..createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  group('listing', () {
    test('lists direct children only, never recursing', () async {
      writeFile('a.txt', 'a');
      writeFile('sub/b.txt', 'b');

      final List<FileSystemNode> nodes = await fs.list(root.path);

      expect(nodes.map((FileSystemNode n) => n.name).toSet(), <String>{'a.txt', 'sub'});
      expect(
        nodes.whereType<FolderNode>().single.name,
        'sub',
        reason: 'sub must appear as a folder, and b.txt must not be listed',
      );
    });

    test('a missing folder reports NotFound rather than throwing raw io', () async {
      expect(
        () => fs.list(at('nope')),
        throwsA(isA<NotFoundFailure>()),
      );
    });

    test('file size and kind are reported', () async {
      writeFile('a.txt', 'hello');
      final List<FileSystemNode> nodes = await fs.list(root.path);
      final FileNode file = nodes.whereType<FileNode>().single;
      expect(file.size, 5);
      expect(file.extension, 'txt');
    });
  });

  group('create', () {
    test('creates a file and a folder', () async {
      final FileNode file = await fs.createFile(root.path, 'new.dart');
      final FolderNode folder = await fs.createFolder(root.path, 'lib');

      expect(File(file.id).existsSync(), isTrue);
      expect(Directory(folder.id).existsSync(), isTrue);
    });

    test('creating over an existing file fails instead of truncating it', () async {
      writeFile('keep.txt', 'precious');

      await expectLater(
        fs.createFile(root.path, 'keep.txt'),
        throwsA(isA<AlreadyExistsFailure>()),
      );
      expect(
        File(at('keep.txt')).readAsStringSync(),
        'precious',
        reason: 'the original content must survive a failed create',
      );
    });
  });

  group('write', () {
    test('writes and reads bytes back', () async {
      final String path = at('data.bin');
      await File(path).create();
      await fs.writeBytes(path, Uint8List.fromList(<int>[1, 2, 3]));
      expect(await fs.readBytes(path), <int>[1, 2, 3]);
    });

    test('an atomic write leaves no temp files behind', () async {
      final String path = at('x.txt');
      await File(path).create();
      await fs.writeText(path, 'hello', const TextFormat(endsWithNewline: false));

      final List<String> leftovers = root
          .listSync()
          .map((FileSystemEntity e) => p.basename(e.path))
          .where((String n) => n.endsWith('.tmp'))
          .toList();
      expect(leftovers, isEmpty);
      expect(File(path).readAsStringSync(), 'hello');
    });

    test('writeText preserves CRLF line endings', () async {
      final String path = at('crlf.txt');
      await File(path).create();
      await fs.writeText(
        path,
        'a\nb',
        const TextFormat(lineEnding: LineEnding.crlf, endsWithNewline: false),
      );
      expect(File(path).readAsStringSync(), 'a\r\nb');
    });
  });

  group('rename', () {
    test('renames a file', () async {
      writeFile('old.dart', 'x');
      final FileSystemNode node = await fs.rename(at('old.dart'), 'new.dart');

      expect(node.name, 'new.dart');
      expect(File(at('old.dart')).existsSync(), isFalse);
      expect(File(at('new.dart')).existsSync(), isTrue);
    });

    test('renaming onto an existing name fails', () async {
      writeFile('a.txt', 'a');
      writeFile('b.txt', 'b');
      await expectLater(
        fs.rename(at('a.txt'), 'b.txt'),
        throwsA(isA<AlreadyExistsFailure>()),
      );
    });

    test('renaming a folder keeps its contents', () async {
      writeFile('src/deep/file.txt', 'kept');
      await fs.rename(at('src'), 'lib');
      expect(File(at('lib/deep/file.txt')).readAsStringSync(), 'kept');
    });
  });

  group('copy', () {
    test('copies a single file', () async {
      writeFile('a.txt', 'content');
      await fs.createFolder(root.path, 'dest');

      await fs.copy(at('a.txt'), at('dest'));

      expect(File(at('dest/a.txt')).readAsStringSync(), 'content');
      expect(File(at('a.txt')).existsSync(), isTrue, reason: 'copy is not a move');
    });

    test('copies a folder tree recursively', () async {
      writeFile('src/one.txt', '1');
      writeFile('src/nested/two.txt', '2');
      writeFile('src/nested/deeper/three.txt', '3');
      await fs.createFolder(root.path, 'dest');

      await fs.copy(at('src'), at('dest'));

      expect(File(at('dest/src/one.txt')).readAsStringSync(), '1');
      expect(File(at('dest/src/nested/two.txt')).readAsStringSync(), '2');
      expect(File(at('dest/src/nested/deeper/three.txt')).readAsStringSync(), '3');
    });

    test('copying to a new name works', () async {
      writeFile('a.txt', 'content');
      await fs.copy(at('a.txt'), root.path, newName: 'a copy.txt');
      expect(File(at('a copy.txt')).readAsStringSync(), 'content');
    });

    test('reports progress for a large tree', () async {
      for (int i = 0; i < 80; i++) {
        writeFile('src/file$i.txt', '$i');
      }
      await fs.createFolder(root.path, 'dest');

      final List<FileOperationProgress> updates = <FileOperationProgress>[];
      await fs.copy(at('src'), at('dest'), onProgress: updates.add);

      expect(updates, isNotEmpty, reason: 'the progress dialog needs updates');
      expect(updates.last.total, greaterThan(0));
    });
  });

  group('move', () {
    test('moves a file into another folder', () async {
      writeFile('a.txt', 'content');
      await fs.createFolder(root.path, 'dest');

      await fs.move(at('a.txt'), at('dest'));

      expect(File(at('dest/a.txt')).readAsStringSync(), 'content');
      expect(File(at('a.txt')).existsSync(), isFalse);
    });

    test('refuses to move a folder into itself', () async {
      await fs.createFolder(root.path, 'src');
      await expectLater(
        fs.move(at('src'), at('src')),
        throwsA(isA<UnsupportedOperationFailure>()),
      );
    });

    test('refuses to move a folder into its own descendant', () async {
      writeFile('src/nested/deep/x.txt', 'x');
      await expectLater(
        fs.move(at('src'), at('src/nested/deep')),
        throwsA(isA<UnsupportedOperationFailure>()),
        reason: 'this would detach the tree and lose the files',
      );
    });

    test('a sibling folder with a similar prefix is not mistaken for a child',
        () async {
      await fs.createFolder(root.path, 'src');
      await fs.createFolder(root.path, 'src-backup');
      // "src-backup" starts with "src" but is not inside it. A naive
      // startsWith check would wrongly block this legitimate move.
      await fs.move(at('src'), at('src-backup'));
      expect(Directory(at('src-backup/src')).existsSync(), isTrue);
    });
  });

  group('delete', () {
    test('deletes a single file', () async {
      writeFile('a.txt', 'x');
      await fs.delete(at('a.txt'));
      expect(File(at('a.txt')).existsSync(), isFalse);
    });

    test('deletes a folder tree recursively', () async {
      writeFile('src/one.txt', '1');
      writeFile('src/nested/two.txt', '2');

      await fs.delete(at('src'));

      expect(Directory(at('src')).existsSync(), isFalse);
    });

    test('deleting something that is already gone reports NotFound', () async {
      await expectLater(
        fs.delete(at('ghost.txt')),
        throwsA(isA<NotFoundFailure>()),
      );
    });
  });

  group('folderStats', () {
    test('counts files, folders and bytes recursively', () async {
      writeFile('src/a.txt', '12345');
      writeFile('src/b.txt', '123');
      writeFile('src/nested/c.txt', '1');

      final FolderStats stats = await fs.folderStats(at('src'));

      expect(stats.fileCount, 3);
      expect(stats.folderCount, 1);
      expect(stats.totalBytes, 9);
    });

    test('a single file reports itself', () async {
      writeFile('a.txt', 'abcde');
      final FolderStats stats = await fs.folderStats(at('a.txt'));
      expect(stats.fileCount, 1);
      expect(stats.totalBytes, 5);
    });
  });

  group('cancellation', () {
    test('a token cancelled before the copy starts stops it', () async {
      writeFile('src/a.txt', 'a');
      await fs.createFolder(root.path, 'dest');

      final CancellationToken token = CancellationToken()..cancel();

      await expectLater(
        fs.copy(at('src'), at('dest'), token: token),
        throwsA(isA<CancelledFailure>()),
      );
      expect(
        Directory(at('dest/src')).existsSync(),
        isFalse,
        reason: 'nothing should have been copied',
      );
    });

    test('cancelling a delete leaves the source in place', () async {
      writeFile('src/a.txt', 'a');
      final CancellationToken token = CancellationToken()..cancel();

      await expectLater(
        fs.delete(at('src'), token: token),
        throwsA(isA<CancelledFailure>()),
      );
      expect(Directory(at('src')).existsSync(), isTrue);
    });

    test('an un-cancelled token does not interfere', () async {
      writeFile('src/a.txt', 'a');
      await fs.createFolder(root.path, 'dest');

      await fs.copy(at('src'), at('dest'), token: CancellationToken());

      expect(File(at('dest/src/a.txt')).readAsStringSync(), 'a');
    });
  });

  group('identity helpers', () {
    test('childId joins, parentOf splits, nameOf reads the base name', () {
      final String child = fs.childId('/a/b', 'c.txt');
      expect(child, p.join('/a/b', 'c.txt'));
      expect(fs.parentOf(child), '/a/b');
      expect(fs.nameOf(child), 'c.txt');
    });
  });
}
