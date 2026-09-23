/// Snippets: expansion, validation, storage and ranking.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/snippets_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/features/snippets/presentation/snippet_picker.dart';

import '../../support/fake_file_system.dart';

Snippet snippet({
  String id = '1',
  String prefix = 'fori',
  String body = 'for (var i = 0; i < n; i++) {}',
  String description = '',
  List<String> languages = const <String>[kAnyLanguage],
}) =>
    Snippet(
      id: id,
      prefix: prefix,
      body: body,
      description: description,
      languageIds: languages,
    );

SupportStorage storageFor() {
  final FakeFileSystemProvider fs = FakeFileSystemProvider()
    ..seed(<String, String>{'/support/.keep': ''});
  return SupportStorage(provider: fs, rootId: '/support');
}

void main() {
  group('expandSnippet', () {
    test('the first line is not indented, later lines are', () {
      // The caret is already at the indent, so indenting the first line again
      // would double it.
      final ExpandedSnippet e =
          expandSnippet('if (x) {\n  y();\n}', lineIndent: '    ');
      expect(e.text, 'if (x) {\n      y();\n    }');
    });

    test(r'a $0 marker sets where the caret lands, and is removed', () {
      final ExpandedSnippet e =
          expandSnippet('if (\$0) {\n}', lineIndent: '');
      expect(e.text, 'if () {\n}');
      expect(e.lineOffset, 0);
      expect(e.column, 4);
    });

    test(r'a $0 on a later line accounts for the added indent', () {
      final ExpandedSnippet e =
          expandSnippet('try {\n  \$0\n}', lineIndent: '  ');
      expect(e.text, 'try {\n    \n  }');
      expect(e.lineOffset, 1);
      expect(e.column, 4, reason: '2 of indent plus 2 already in the body');
    });

    test('with no marker the caret ends where typing would have left it', () {
      final ExpandedSnippet e = expandSnippet('abc', lineIndent: '');
      expect(e.lineOffset, 0);
      expect(e.column, 3);
    });

    test('only the first marker is used', () {
      final ExpandedSnippet e = expandSnippet(r'a$0b$0c', lineIndent: '');
      expect(e.text, r'ab$0c', reason: 'a second marker is left as text');
      expect(e.column, 1);
    });

    test('a single-line snippet is unchanged', () {
      expect(expandSnippet('print()', lineIndent: '    ').text, 'print()');
    });
  });

  group('validateSnippet', () {
    test('accepts a reasonable snippet', () {
      expect(validateSnippet(snippet(), const <Snippet>[]), isNull);
    });

    test('rejects an empty or one-character name', () {
      expect(validateSnippet(snippet(prefix: ''), const <Snippet>[]), isNotNull);
      expect(validateSnippet(snippet(prefix: 'f'), const <Snippet>[]), isNotNull);
    });

    test('rejects a name that is not identifier-shaped', () {
      expect(validateSnippet(snippet(prefix: 'for i'), const <Snippet>[]),
          isNotNull);
      expect(validateSnippet(snippet(prefix: '1st'), const <Snippet>[]),
          isNotNull);
    });

    test('rejects an empty body', () {
      expect(validateSnippet(snippet(body: ''), const <Snippet>[]), isNotNull);
    });

    test('rejects a body beyond the cap', () {
      expect(
        validateSnippet(snippet(body: 'x' * 20), const <Snippet>[],
            maxBodyChars: 10),
        isNotNull,
      );
    });

    test('rejects a duplicate name that could apply at the same time', () {
      final Snippet existing = snippet(id: 'a', languages: <String>['dart']);
      expect(
        validateSnippet(
          snippet(id: 'b', languages: <String>['dart']),
          <Snippet>[existing],
        ),
        isNotNull,
      );
    });

    test('allows the same name for languages that never overlap', () {
      final Snippet existing = snippet(id: 'a', languages: <String>['dart']);
      expect(
        validateSnippet(
          snippet(id: 'b', languages: <String>['python']),
          <Snippet>[existing],
        ),
        isNull,
      );
    });

    test('an all-languages snippet always overlaps', () {
      final Snippet existing = snippet(id: 'a');
      expect(
        validateSnippet(
          snippet(id: 'b', languages: <String>['python']),
          <Snippet>[existing],
        ),
        isNotNull,
      );
    });

    test('editing a snippet does not collide with itself', () {
      final Snippet existing = snippet(id: 'a');
      expect(validateSnippet(existing, <Snippet>[existing]), isNull);
    });
  });

  group('snippetsFor', () {
    test('all-languages snippets apply everywhere', () {
      expect(snippetsFor(<Snippet>[snippet()], 'python'), hasLength(1));
    });

    test('a language-specific snippet applies only there', () {
      final List<Snippet> all = <Snippet>[
        snippet(id: 'a', languages: <String>['dart']),
      ];
      expect(snippetsFor(all, 'dart'), hasLength(1));
      expect(snippetsFor(all, 'python'), isEmpty);
    });
  });

  group('json', () {
    test('round trips', () {
      final Snippet original = snippet(
        description: 'a for loop',
        languages: <String>['dart', 'javascript'],
      );
      final Snippet? back = Snippet.fromJson(original.toJson());
      expect(back, isNotNull);
      expect(back!.prefix, original.prefix);
      expect(back.body, original.body);
      expect(back.description, original.description);
      expect(back.languageIds, original.languageIds);
    });

    test('a malformed entry decodes to null rather than throwing', () {
      expect(Snippet.fromJson(<String, Object?>{'id': 1}), isNull);
      expect(Snippet.fromJson(<String, Object?>{'id': 'a', 'prefix': ''}),
          isNull);
      expect(Snippet.fromJson(const <String, Object?>{}), isNull);
    });
  });

  group('repository', () {
    test('saves and loads', () async {
      final SnippetsRepository repo = SnippetsRepository(storageFor());
      await repo.save(<Snippet>[snippet(), snippet(id: '2', prefix: 'main')]);
      final List<Snippet> back = await repo.load();
      expect(back.map((Snippet s) => s.prefix), <String>['fori', 'main']);
    });

    test('an empty store loads as empty rather than failing', () async {
      expect(await SnippetsRepository(storageFor()).load(), isEmpty);
    });

    test('one bad entry does not cost the whole library', () async {
      final SupportStorage storage = storageFor();
      await storage.writeJson(SnippetsRepository.fileName, <String, Object?>{
        'version': 1,
        'snippets': <Object?>[
          <String, Object?>{'id': 'broken'},
          snippet(id: 'good', prefix: 'okay').toJson(),
        ],
      });
      final List<Snippet> back = await SnippetsRepository(storage).load();
      expect(back.map((Snippet s) => s.prefix), <String>['okay']);
    });

    test('corrupt json loads as empty', () async {
      final SupportStorage storage = storageFor();
      await storage.writeTextFile(
        storage.idFor(SnippetsRepository.fileName),
        'not json at all',
      );
      expect(await SnippetsRepository(storage).load(), isEmpty);
    });
  });

  group('rankSnippets', () {
    test('an empty query keeps the order they were defined in', () {
      final List<Snippet> all = <Snippet>[
        snippet(id: 'a', prefix: 'zeta'),
        snippet(id: 'b', prefix: 'alpha'),
      ];
      expect(
        rankSnippets(all, '').map((RankedSnippet r) => r.snippet.prefix),
        <String>['zeta', 'alpha'],
      );
    });

    test('a name match beats a description match', () {
      final List<Snippet> all = <Snippet>[
        snippet(id: 'a', prefix: 'other', description: 'fori loop helper'),
        snippet(id: 'b'),
      ];
      expect(
        rankSnippets(all, 'fori').first.snippet.prefix,
        'fori',
      );
    });

    test('the description is searched, so a synonym finds it', () {
      final List<Snippet> all = <Snippet>[
        snippet(id: 'a', description: 'counting loop'),
      ];
      expect(rankSnippets(all, 'loop'), hasLength(1));
    });

    test('no match yields nothing', () {
      expect(rankSnippets(<Snippet>[snippet()], 'zzzz'), isEmpty);
    });
  });
}
