/// Harvesting keyword lists out of the highlighting grammars.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:pocket_code/services/language/language_keywords.dart';
import 'package:pocket_code/services/language/language_registry.dart';
import 'package:re_highlight/re_highlight.dart';

/// Languages that legitimately carry no keywords, so an empty list is correct
/// rather than a regression. Everything else must produce some.
///
/// These four are structural rather than keyword-driven: plain text has no
/// grammar, and Markdown, YAML and TOML are defined by punctuation and layout.
/// Completion in those files therefore comes from the buffer alone, which is
/// the right answer for them anyway.
const Set<String> kNoKeywords = <String>{
  'plaintext',
  'markdown',
  'yaml',
  'toml',
};

void main() {
  group('shapes', () {
    test('a space-separated string is read', () {
      // Dart's grammar writes its literals this way.
      expect(
        harvestKeywords(Mode(keywords: 'true false null this is new super')),
        containsAll(<String>['true', 'false', 'null', 'super']),
      );
    });

    test('a map of lists is read', () {
      expect(
        harvestKeywords(Mode(keywords: <String, Object?>{
          'keyword': <String>['def', 'class'],
          'built_in': <String>['print'],
        })),
        containsAll(<String>['def', 'class', 'print']),
      );
    });

    test('a map of space-separated strings is read', () {
      // CSS's top-level is `{"keyframePosition": "from to"}` — the shape
      // re_editor's own builder ignores, which is why CSS would otherwise
      // contribute nothing.
      expect(
        harvestKeywords(Mode(keywords: <String, Object?>{
          'keyframePosition': 'from to something',
        })),
        contains('something'),
      );
    });

    test(r'the $pattern key is configuration, not a keyword', () {
      expect(
        harvestKeywords(Mode(keywords: <String, Object?>{
          r'$pattern': r'[A-Za-z]+',
          'keyword': <String>['while'],
        })),
        <String>['while'],
      );
    });

    test('a relevance suffix is stripped', () {
      expect(harvestKeywords(Mode(keywords: 'import|10 export')),
          <String>['export', 'import']);
    });

    test('nested modes contribute their keywords', () {
      expect(
        harvestKeywords(Mode(
          keywords: 'outer',
          contains: <Mode>[
            Mode(keywords: 'inner', contains: <Mode>[Mode(keywords: 'deepest')]),
          ],
        )),
        containsAll(<String>['outer', 'inner', 'deepest']),
      );
    });

    test('beginKeywords are harvested too', () {
      expect(harvestKeywords(Mode(beginKeywords: 'class interface')),
          containsAll(<String>['class', 'interface']));
    });

    test('a cycle does not hang the walk', () {
      final Mode a = Mode(keywords: 'alpha');
      final Mode b = Mode(keywords: 'beta', contains: <Mode>[a]);
      a.contains = <Mode>[b];
      expect(harvestKeywords(a), containsAll(<String>['alpha', 'beta']));
    });

    test('null yields nothing rather than throwing', () {
      expect(harvestKeywords(null), isEmpty);
    });
  });

  group('filtering', () {
    test('punctuation and regex fragments are dropped', () {
      expect(
        harvestKeywords(Mode(keywords: r'return ( ) [A-Za-z]+ -> yield')),
        <String>['return', 'yield'],
      );
    });

    test('very short words are dropped, being faster to type than to read', () {
      expect(harvestKeywords(Mode(keywords: 'a in for')), <String>['for']);
    });

    test('the result is sorted and deduplicated', () {
      final List<String> got =
          harvestKeywords(Mode(keywords: 'zebra apple zebra mango'));
      expect(got, <String>['apple', 'mango', 'zebra']);
    });
  });

  group('every registered language', () {
    setUp(LanguageKeywords.clearCache);

    test('produces keywords, or is a known exception', () {
      // This is the test that catches a future re_highlight changing the shape
      // of a grammar: a language silently dropping to zero keywords would
      // otherwise just look like slightly worse completion.
      final List<String> empty = <String>[];
      for (final LanguageDefinition language in LanguageRegistry.all) {
        final List<String> keywords = LanguageKeywords.forLanguage(language);
        if (keywords.isEmpty && !kNoKeywords.contains(language.id)) {
          empty.add(language.id);
        }
      }
      expect(empty, isEmpty,
          reason: 'these languages harvested no keywords at all');
    });

    test('the known exceptions really are empty', () {
      for (final String id in kNoKeywords) {
        final LanguageDefinition? language = LanguageRegistry.byId(id);
        expect(language, isNotNull, reason: id);
        expect(LanguageKeywords.forLanguage(language!), isEmpty, reason: id);
      }
    });

    test('a few languages carry the keywords you would expect', () {
      expect(LanguageKeywords.forLanguage(LanguageRegistry.byId('dart')!),
          containsAll(<String>['class', 'extends', 'final']));
      expect(LanguageKeywords.forLanguage(LanguageRegistry.byId('python')!),
          containsAll(<String>['def', 'import', 'return']));
    });

    test('the cache returns the same list rather than re-walking', () {
      final LanguageDefinition dart = LanguageRegistry.byId('dart')!;
      expect(
        identical(
          LanguageKeywords.forLanguage(dart),
          LanguageKeywords.forLanguage(dart),
        ),
        isTrue,
      );
    });
  });
}
