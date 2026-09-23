/// The workspace walk behind Quick Open.
///
/// Runs against the in-memory provider, so nesting, exclusions and unreadable
/// folders are all exercised without a device.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

import '../support/fake_file_system.dart';

FakeFileSystemProvider seeded() => FakeFileSystemProvider()
  ..seed(<String, String>{
    '/w/main.dart': 'void main() {}',
    '/w/README.md': '# hi',
    '/w/.env': 'SECRET=1',
    '/w/lib/app.dart': '',
    '/w/lib/src/deep/nested.dart': '',
    '/w/node_modules/left-pad/index.js': '',
    '/w/build/output.o': '',
    '/w/empty/': '',
  });

List<IndexRoot> rootsOf(FakeFileSystemProvider provider) => <IndexRoot>[
  IndexRoot(provider: provider, rootId: '/w', rootIndex: 0),
];

Future<FileIndex> index(
  FakeFileSystemProvider provider, {
  bool showHidden = false,
  List<String> exclude = const <String>[],
  FileIndexer indexer = const FileIndexer(),
}) {
  return indexer.build(
    rootsOf(provider),
    showHidden: showHidden,
    excludePatterns: exclude,
  );
}

void main() {
  test('finds files at every depth', () async {
    final FileIndex result = await index(seeded());

    expect(
      result.files.map((IndexedFile f) => f.relativePath),
      containsAll(<String>[
        'main.dart',
        'README.md',
        'lib/app.dart',
        'lib/src/deep/nested.dart',
      ]),
    );
  });

  test('relative paths are root-relative and slash-separated', () async {
    final FileIndex result = await index(seeded());
    final IndexedFile nested = result.files.firstWhere(
      (IndexedFile f) => f.name == 'nested.dart',
    );

    expect(
      nested.relativePath,
      'lib/src/deep/nested.dart',
      reason: 'the row shows this, and the fuzzy matcher scores it',
    );
    expect(nested.rootIndex, 0);
  });

  test('lists folders but does not index them as files', () async {
    final FileIndex result = await index(seeded());

    expect(
      result.files.map((IndexedFile f) => f.name),
      isNot(contains('empty')),
      reason: 'Quick Open opens files; a folder is not a destination',
    );
  });

  test('hides hidden files unless asked, matching the explorer', () async {
    final FileIndex hidden = await index(seeded());
    expect(
      hidden.files.map((IndexedFile f) => f.name),
      isNot(contains('.env')),
    );

    final FileIndex shown = await index(seeded(), showHidden: true);
    expect(shown.files.map((IndexedFile f) => f.name), contains('.env'));
  });

  test('honours exclude patterns, including globs', () async {
    final FileIndex result = await index(
      seeded(),
      exclude: <String>['node_modules', '*.o'],
    );

    final Iterable<String> paths = result.files.map(
      (IndexedFile f) => f.relativePath,
    );
    expect(
      paths,
      isNot(contains('node_modules/left-pad/index.js')),
      reason: 'an excluded folder must not be descended into at all',
    );
    expect(paths, isNot(contains('build/output.o')));
    expect(paths, contains('main.dart'));
  });

  test('skips an unreadable folder instead of abandoning the walk', () async {
    final FakeFileSystemProvider provider = seeded()..denyList.add('/w/lib');

    final FileIndex result = await index(provider);

    expect(
      result.files.map((IndexedFile f) => f.relativePath),
      contains('main.dart'),
      reason: 'one denied directory must not cost every other result',
    );
    expect(
      result.files.map((IndexedFile f) => f.relativePath),
      isNot(contains('lib/app.dart')),
    );
  });

  test('stops at the file limit and admits it', () async {
    final FakeFileSystemProvider provider = FakeFileSystemProvider();
    provider.seed(<String, String>{
      for (int i = 0; i < 30; i++) '/w/f$i.dart': '',
    });

    final FileIndex result = await index(
      provider,
      indexer: const FileIndexer(fileLimit: 10),
    );

    expect(result.files, hasLength(10));
    expect(
      result.truncated,
      isTrue,
      reason: 'a silently partial list lies about what the workspace holds',
    );
  });

  test('a complete walk is not marked truncated', () async {
    final FileIndex result = await index(seeded());
    expect(result.truncated, isFalse);
  });

  test('an empty workspace yields an empty index, not an error', () async {
    final FakeFileSystemProvider provider = FakeFileSystemProvider()
      ..seed(<String, String>{'/w/': ''});

    final FileIndex result = await index(provider);

    expect(result.files, isEmpty);
    expect(result.truncated, isFalse);
  });

  test('breadth-first: shallow files are indexed before deep ones', () async {
    final FileIndex result = await index(seeded());
    final int shallow = result.files.indexWhere(
      (IndexedFile f) => f.relativePath == 'main.dart',
    );
    final int deep = result.files.indexWhere(
      (IndexedFile f) => f.relativePath.contains('deep/'),
    );

    expect(
      shallow,
      lessThan(deep),
      reason: 'if the limit cuts the walk short, keep the likely targets',
    );
  });

  group('scoped to a folder (Find in Folder)', () {
    Future<FileIndex> scoped(String startId, String startPath) =>
        const FileIndexer().build(
          <IndexRoot>[
            IndexRoot(
              provider: seeded(),
              rootId: '/w',
              rootIndex: 0,
              startId: startId,
              startPath: startPath,
            ),
          ],
          showHidden: false,
          excludePatterns: const <String>[],
        );

    test('only files inside the folder are indexed', () async {
      final FileIndex result = await scoped('/w/lib', 'lib');
      expect(
        result.files.map((IndexedFile f) => f.relativePath).toSet(),
        <String>{'lib/app.dart', 'lib/src/deep/nested.dart'},
        reason: 'main.dart and README.md sit outside lib/ and must not appear',
      );
    });

    test('paths stay relative to the workspace root, not the folder', () async {
      // So a scoped result displays, and opens, exactly like an unscoped one.
      final FileIndex result = await scoped('/w/lib/src', 'lib/src');
      expect(result.files.single.relativePath, 'lib/src/deep/nested.dart');
    });

    test(
      'a folder that has gone yields an empty index, not an error',
      () async {
        final FileIndex result = await scoped('/w/deleted', 'deleted');
        expect(result.files, isEmpty);
      },
    );

    test('with no start given, the walk is the whole root as before', () {
      final IndexRoot root = IndexRoot(
        provider: seeded(),
        rootId: '/w',
        rootIndex: 0,
      );
      expect(root.startId, '/w');
      expect(root.startPath, '');
    });
  });
}
