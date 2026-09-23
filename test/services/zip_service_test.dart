/// ZIP export and import, including the zip-slip guard.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/archive/zip_service.dart';

import '../support/fake_file_system.dart';

const ZipService zip = ZipService();

FakeFileSystemProvider seeded() => FakeFileSystemProvider()
  ..seed(<String, String>{
    '/w/main.dart': 'void main() {}',
    '/w/lib/app.dart': 'class App {}',
    '/w/lib/empty/': '',
  });

Uint8List archiveOf(Map<String, String> entries, {List<String> dirs = const <String>[]}) {
  final Archive archive = Archive();
  for (final String dir in dirs) {
    archive.addFile(ArchiveFile.directory(dir));
  }
  entries.forEach((String path, String content) {
    archive.addFile(
      ArchiveFile.bytes(path, Uint8List.fromList(content.codeUnits)),
    );
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Set<String> pathsIn(Uint8List bytes) =>
    ZipDecoder().decodeBytes(bytes).files.map((ArchiveFile f) => f.name).toSet();

void main() {
  group('sanitiseEntryPath', () {
    test('keeps an ordinary relative path', () {
      expect(sanitiseEntryPath('lib/app.dart'), 'lib/app.dart');
      expect(sanitiseEntryPath('./lib//app.dart'), 'lib/app.dart');
      expect(sanitiseEntryPath(r'lib\app.dart'), 'lib/app.dart',
          reason: 'archives written on Windows use backslashes');
    });

    test('refuses anything that escapes the destination', () {
      // Zip-slip. Refused rather than resolved: an archive that wants to write
      // outside the folder is not one to be clever about.
      expect(sanitiseEntryPath('../evil.sh'), isNull);
      expect(sanitiseEntryPath('lib/../../evil.sh'), isNull);
      expect(sanitiseEntryPath('/etc/passwd'), isNull);
      expect(sanitiseEntryPath(r'C:\windows\evil'), isNull);
    });

    test('refuses an empty path', () {
      expect(sanitiseEntryPath(''), isNull);
      expect(sanitiseEntryPath('./'), isNull);
    });
  });

  group('export', () {
    test('includes every file, with folder-relative paths', () async {
      final Uint8List bytes =
          await zip.export(provider: seeded(), folderId: '/w');

      expect(pathsIn(bytes), containsAll(<String>['main.dart', 'lib/app.dart']));
    });

    test('keeps empty folders, which most tools drop', () async {
      final Uint8List bytes =
          await zip.export(provider: seeded(), folderId: '/w');

      expect(pathsIn(bytes), contains('lib/empty/'),
          reason: 'a project skeleton is mostly empty folders');
    });

    test('round-trips content unchanged', () async {
      final Uint8List bytes =
          await zip.export(provider: seeded(), folderId: '/w');
      final ArchiveFile entry = ZipDecoder()
          .decodeBytes(bytes)
          .files
          .firstWhere((ArchiveFile f) => f.name == 'main.dart');

      expect(String.fromCharCodes(entry.content as List<int>), 'void main() {}');
    });

    test('an empty folder produces a valid, empty archive', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/': ''});

      final Uint8List bytes =
          await zip.export(provider: provider, folderId: '/w');

      expect(ZipDecoder().decodeBytes(bytes).files, isEmpty);
    });
  });

  group('import', () {
    test('writes files and creates the folders they need', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/': ''});

      final int written = await zip.import(
        provider: provider,
        folderId: '/w',
        bytes: archiveOf(<String, String>{
          'readme.md': '# hi',
          'src/deep/file.txt': 'nested',
        }),
      );

      expect(written, 2);
      expect(provider.fs.file('/w/readme.md').readAsStringSync(), '# hi');
      expect(
        provider.fs.file('/w/src/deep/file.txt').readAsStringSync(),
        'nested',
      );
    });

    test('skips entries that would escape, without failing the import',
        () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/': ''});

      final int written = await zip.import(
        provider: provider,
        folderId: '/w',
        bytes: archiveOf(<String, String>{
          '../escaped.sh': 'bad',
          'safe.txt': 'good',
        }),
      );

      expect(written, 1, reason: 'only the safe entry is written');
      expect(provider.fs.file('/w/safe.txt').existsSync(), isTrue);
      expect(provider.fs.file('/escaped.sh').existsSync(), isFalse);
    });

    test('refuses to overwrite unless told to', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/keep.txt': 'original'});

      await expectLater(
        zip.import(
          provider: provider,
          folderId: '/w',
          bytes: archiveOf(<String, String>{'keep.txt': 'replacement'}),
        ),
        throwsA(isA<AlreadyExistsFailure>()),
      );
      expect(provider.fs.file('/w/keep.txt').readAsStringSync(), 'original',
          reason: 'overwriting is not undoable, so it must be asked for');
    });

    test('overwrites when explicitly allowed', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/keep.txt': 'original'});

      await zip.import(
        provider: provider,
        folderId: '/w',
        bytes: archiveOf(<String, String>{'keep.txt': 'replacement'}),
        overwrite: true,
      );

      expect(provider.fs.file('/w/keep.txt').readAsStringSync(), 'replacement');
    });

    test('recreates empty folders', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/': ''});

      await zip.import(
        provider: provider,
        folderId: '/w',
        bytes: archiveOf(const <String, String>{}, dirs: <String>['assets/']),
      );

      expect(provider.fs.directory('/w/assets').existsSync(), isTrue);
    });

    test('looksLikeZip recognises the signature', () {
      expect(looksLikeZip(Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04])), isTrue);
      expect(looksLikeZip(Uint8List.fromList(<int>[0x50, 0x4B, 0x05, 0x06])), isTrue,
          reason: 'an empty archive is still a ZIP');
      expect(looksLikeZip(Uint8List.fromList(<int>[1, 2, 3, 4])), isFalse);
      expect(looksLikeZip(Uint8List.fromList(<int>[0x50])), isFalse);
    });

    test('rejects bytes that are not a ZIP', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{'/w/': ''});

      await expectLater(
        zip.import(
          provider: provider,
          folderId: '/w',
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
        throwsA(isA<UnknownFailure>()),
      );
    });

    test('export then import reproduces the tree', () async {
      final Uint8List bytes =
          await zip.export(provider: seeded(), folderId: '/w');
      final FakeFileSystemProvider target = FakeFileSystemProvider()
        ..seed(<String, String>{'/out/': ''});

      await zip.import(provider: target, folderId: '/out', bytes: bytes);

      expect(target.fs.file('/out/main.dart').readAsStringSync(),
          'void main() {}');
      expect(target.fs.file('/out/lib/app.dart').existsSync(), isTrue);
      expect(target.fs.directory('/out/lib/empty').existsSync(), isTrue);
    });
  });
}
