/// Ranking tests for the fuzzy matcher.
///
/// These assert specific orderings rather than raw scores: the constants are
/// tuning knobs and may move, but "typing `mn` must find main.dart" is the
/// contract Quick Open depends on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/utils/fuzzy_matcher.dart';

int? scoreOf(String pattern, String candidate) =>
    FuzzyMatcher.match(pattern, candidate)?.score;

/// Sorts [candidates] the way Quick Open does, best first.
List<String> ranked(String pattern, List<String> candidates) {
  final List<MapEntry<String, FuzzyMatch>> hits =
      <MapEntry<String, FuzzyMatch>>[];
  for (final String candidate in candidates) {
    final FuzzyMatch? match = FuzzyMatcher.match(pattern, candidate);
    if (match != null) {
      hits.add(MapEntry<String, FuzzyMatch>(candidate, match));
    }
  }
  hits.sort(
    (MapEntry<String, FuzzyMatch> a, MapEntry<String, FuzzyMatch> b) =>
        b.value.score.compareTo(a.value.score),
  );
  return hits.map((MapEntry<String, FuzzyMatch> e) => e.key).toList();
}

void main() {
  group('matching', () {
    test('an empty pattern matches everything with no highlights', () {
      final FuzzyMatch? match = FuzzyMatcher.match('', 'main.dart');
      expect(match, isNotNull);
      expect(match!.score, 0);
      expect(match.indices, isEmpty);
    });

    test('a non-subsequence does not match', () {
      expect(FuzzyMatcher.match('xyz', 'main.dart'), isNull);
      expect(FuzzyMatcher.match('dartmain', 'main.dart'), isNull);
    });

    test('a pattern longer than the candidate does not match', () {
      expect(FuzzyMatcher.match('mainmain', 'main'), isNull);
    });

    test('matching is case insensitive', () {
      expect(FuzzyMatcher.match('MAIN', 'main.dart'), isNotNull);
      expect(FuzzyMatcher.match('main', 'MAIN.DART'), isNotNull);
    });

    test('indices point at the characters that matched', () {
      final FuzzyMatch match = FuzzyMatcher.match('mn', 'main.dart')!;
      expect(match.indices, <int>[0, 3]);
      expect(
        match.indices.map((int i) => 'main.dart'[i]).join(),
        'mn',
        reason: 'highlighted characters must spell the pattern',
      );
    });

    test('indices are picked for the best run, not the first occurrence', () {
      // A greedy matcher takes the `e` at index 1 and then hunts for an `r`;
      // the best run is the adjacent `er` at 4-5.
      final FuzzyMatch match = FuzzyMatcher.match('er', 'renderer')!;
      expect(match.indices, <int>[4, 5]);
    });

    test('indices stay ascending and in range for a path', () {
      const String candidate = 'lib/features/search/presentation/panel.dart';
      final FuzzyMatch match = FuzzyMatcher.match('lfsp', candidate)!;
      expect(match.indices.length, 4);
      for (int i = 1; i < match.indices.length; i++) {
        expect(match.indices[i], greaterThan(match.indices[i - 1]));
      }
      expect(match.indices.last, lessThan(candidate.length));
    });
  });

  group('ranking', () {
    test('"mn" ranks main.dart above human.dart', () {
      expect(ranked('mn', <String>['human.dart', 'main.dart']).first,
          'main.dart');
    });

    test('a basename-start match beats a mid-word match', () {
      expect(
        ranked('set', <String>['assets.json', 'settings.dart']).first,
        'settings.dart',
      );
    });

    test('a consecutive run beats a scattered subsequence', () {
      expect(
        ranked('page', <String>['p_a_g_e.dart', 'page.dart']).first,
        'page.dart',
      );
    });

    test('a match in the file name beats the same match in a folder', () {
      expect(
        ranked('search', <String>[
          'lib/search/widget.dart',
          'lib/panel/search.dart',
        ]).first,
        'lib/panel/search.dart',
      );
    });

    test('word-boundary matches beat matches inside a word', () {
      expect(
        ranked('fsp', <String>[
          'offsprings.dart',
          'file_system_provider.dart',
        ]).first,
        'file_system_provider.dart',
      );
    });

    test('camelCase initials rank the camelCase identifier first', () {
      expect(
        ranked('fsp', <String>['fasterspin', 'fileSystemProvider']).first,
        'fileSystemProvider',
      );
    });

    test('an exact basename wins over a longer name containing it', () {
      expect(
        ranked('main', <String>['main_window.dart', 'main.dart']).first,
        'main.dart',
      );
    });

    test('shorter candidates win ties', () {
      expect(
        scoreOf('ab', 'ab.dart')!,
        greaterThan(scoreOf('ab', 'ab.dart.backup')!),
        reason: 'identical match shape, so length must be the tiebreak',
      );
    });

    test('a shallower path outranks a deeper one for the same name', () {
      expect(
        ranked('main', <String>[
          'lib/a/b/c/d/main.dart',
          'lib/main.dart',
        ]).first,
        'lib/main.dart',
      );
    });

    test('path depth alone cannot bury an otherwise exact match', () {
      expect(
        ranked('widget', <String>[
          'a/b/c/d/e/f/g/h/i/j/widget.dart',
          'lib/wonderful_intricate_deferred_gadget_extras_thing.dart',
        ]).first,
        'a/b/c/d/e/f/g/h/i/j/widget.dart',
      );
    });

    test('ranking a realistic project for "qo" puts quick_open first', () {
      final List<String> results = ranked('qo', <String>[
        'lib/features/editor/presentation/editor_pane.dart',
        'lib/features/search/presentation/quick_open.dart',
        'lib/core/theme/app_palettes.dart',
      ]);
      expect(results.first, 'lib/features/search/presentation/quick_open.dart');
    });
  });
}
