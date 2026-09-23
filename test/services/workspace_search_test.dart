/// Workspace search: the matching rules, and the walk that applies them.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/search/file_indexer.dart';
import 'package:pocket_code/services/search/workspace_search.dart';

import '../support/fake_file_system.dart';

const String sample = 'final catalog = 1;\n'
    'final cat = 2;\n'
    'FINAL CAT = 3;\n'
    'concatenate();\n';

Future<FileIndex> indexOf(FakeFileSystemProvider provider) {
  return const FileIndexer().build(
    <IndexRoot>[IndexRoot(provider: provider, rootId: '/w', rootIndex: 0)],
    showHidden: false,
    excludePatterns: const <String>[],
  );
}

void main() {
  group('findMatchesInText', () {
    test('is case-insensitive by default', () {
      final List<SearchMatch> m =
          findMatchesInText(sample, const SearchQuery(pattern: 'cat'));
      // catalog, cat, CAT, concatenate
      expect(m, hasLength(4));
    });

    test('case-sensitive excludes the wrong case', () {
      final List<SearchMatch> m = findMatchesInText(
        sample,
        const SearchQuery(pattern: 'cat', caseSensitive: true),
      );
      expect(m, hasLength(3), reason: 'CAT is excluded, concatenate is not');
    });

    test('whole word excludes matches inside longer words', () {
      final List<SearchMatch> m = findMatchesInText(
        sample,
        const SearchQuery(pattern: 'cat', wholeWord: true),
      );
      expect(m, hasLength(2), reason: 'only the standalone cat and CAT');
      expect(m.first.line, 2);
    });

    test('reports 1-based line and column, and the whole line', () {
      final List<SearchMatch> m = findMatchesInText(
        sample,
        const SearchQuery(pattern: 'cat', wholeWord: true),
      );
      expect(m.first.line, 2);
      expect(m.first.column, 7, reason: '"final cat" — c is the 7th character');
      expect(m.first.lineText, 'final cat = 2;');
      expect(m.first.start, 6);
      expect(m.first.length, 3);
    });

    test('treats the pattern literally unless regex is on', () {
      expect(
        findMatchesInText('a.c and abc', const SearchQuery(pattern: 'a.c')),
        hasLength(1),
        reason: 'the dot must not match any character when regex is off',
      );
      expect(
        findMatchesInText(
          'a.c and abc',
          const SearchQuery(pattern: 'a.c', regex: true),
        ),
        hasLength(2),
      );
    });

    test('an invalid regex yields nothing instead of throwing', () {
      expect(
        findMatchesInText('anything', const SearchQuery(pattern: '(', regex: true)),
        isEmpty,
      );
    });

    test('ignores zero-width matches', () {
      // `x*` matches the empty string at every position; reporting those would
      // drown the result list.
      final List<SearchMatch> m = findMatchesInText(
        'abc',
        const SearchQuery(pattern: 'x*', regex: true),
      );
      expect(m, isEmpty);
    });

    test('an empty pattern finds nothing', () {
      expect(findMatchesInText(sample, const SearchQuery(pattern: '')), isEmpty);
    });
  });

  group('replaceAllInText', () {
    test('replaces every match', () {
      final String out = replaceAllInText(
        sample,
        const SearchQuery(pattern: 'cat', wholeWord: true),
        'dog',
      );
      expect(out, contains('final dog = 2;'));
      expect(out, contains('final catalog = 1;'),
          reason: 'whole word must leave catalog alone');
    });

    test('a literal replacement is not treated as a capture reference', () {
      final String out = replaceAllInText(
        'price: X',
        const SearchQuery(pattern: 'X'),
        r'$1',
      );
      expect(out, r'price: $1',
          reason: r'typing $1 with regex off must paste $1, not a group');
    });

    test('regex mode does expand capture groups', () {
      final String out = replaceAllInText(
        'a1',
        const SearchQuery(pattern: r'a(\d)', regex: true),
        r'b$1',
      );
      expect(out, 'b1');
    });

    test('an invalid regex leaves the text untouched', () {
      expect(
        replaceAllInText('abc', const SearchQuery(pattern: '(', regex: true), 'x'),
        'abc',
      );
    });
  });

  group('WorkspaceSearch.run', () {
    FakeFileSystemProvider seeded() => FakeFileSystemProvider()
      ..seed(<String, String>{
        '/w/a.dart': sample,
        '/w/lib/b.dart': 'no hits here\n',
        '/w/lib/c.dart': 'cat\ncat\n',
      });

    Future<SearchResults> search(
      FakeFileSystemProvider provider,
      SearchQuery query, {
      WorkspaceSearch engine = const WorkspaceSearch(),
    }) async {
      return engine.run(
        index: await indexOf(provider),
        query: query,
        providerFor: (int _) => provider,
      );
    }

    test('groups matches by file and counts them', () async {
      final SearchResults r =
          await search(seeded(), const SearchQuery(pattern: 'cat'));

      expect(r.files, hasLength(2), reason: 'b.dart has no hits');
      expect(r.matchCount, 6, reason: '4 in a.dart, 2 in c.dart');
      expect(r.filesSearched, 3);
    });

    test('an empty query searches nothing', () async {
      final SearchResults r =
          await search(seeded(), const SearchQuery(pattern: ''));
      expect(r.files, isEmpty);
      expect(r.filesSearched, 0);
    });

    test('stops at the result limit and admits it', () async {
      final SearchResults r = await search(
        seeded(),
        const SearchQuery(pattern: 'cat'),
        engine: const WorkspaceSearch(resultLimit: 3),
      );

      expect(r.matchCount, 3);
      expect(r.truncated, isTrue);
    });

    test('skips a file larger than the limit without reading it', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{
          '/w/big.txt': 'cat ' * 500,
          '/w/small.txt': 'cat',
        });

      final SearchResults r = await search(
        provider,
        const SearchQuery(pattern: 'cat'),
        engine: const WorkspaceSearch(maxFileBytes: 100),
      );

      expect(r.filesSkipped, 1);
      expect(r.files, hasLength(1));
      expect(r.files.single.file.name, 'small.txt');
    });

    test('skips a file that vanished after indexing', () async {
      // The real race: the index is a snapshot, and a file can be deleted
      // between building it and reading it.
      final FakeFileSystemProvider provider = seeded();
      final FileIndex index = await indexOf(provider);
      await provider.delete('/w/a.dart');

      final SearchResults r = await const WorkspaceSearch().run(
        index: index,
        query: const SearchQuery(pattern: 'cat'),
        providerFor: (int _) => provider,
      );

      expect(r.filesSkipped, 1);
      expect(r.files.map((FileMatches f) => f.file.name), contains('c.dart'),
          reason: 'one missing file must not cost the whole search');
    });

    test('reports no matches distinctly from no files', () async {
      final SearchResults r =
          await search(seeded(), const SearchQuery(pattern: 'zzzzz'));

      expect(r.files, isEmpty);
      expect(r.filesSearched, 3, reason: 'searched, and genuinely found nothing');
    });
  });
}
