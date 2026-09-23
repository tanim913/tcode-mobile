/// The keyword list for a language, harvested from its highlighting grammar.
///
/// The app ships no keyword lists of its own — `re_highlight` already carries
/// them, and duplicating 28 of them by hand would guarantee they drift. What is
/// needed is a reader that copes with how irregular the grammars actually are.
///
/// `Mode.keywords` is `dynamic` and comes in three shapes in the wild:
///
/// * a space-separated `String` — `"true false null this is new super"` (Dart)
/// * a `Map` whose values are `List<String>` — `{"keyword": ["def", "class"]}`
/// * a `Map` whose values are space-separated `String`s — CSS's
///   `{"keyframePosition": "from to"}`
///
/// `DefaultCodeAutocompletePromptsBuilder` reads only the second shape, and
/// only at the top level, which is why CSS, Markdown and several others would
/// otherwise contribute nothing at all. This walks the whole mode graph and
/// accepts all three.
library;

import 'package:pocket_code/services/language/language_definition.dart';
import 'package:re_highlight/re_highlight.dart';

/// Grammars self-reference, so the walk is bounded as well as cycle-guarded.
const int _maxNodes = 800;

/// Keys inside a `keywords` map that are configuration, not keywords.
const Set<String> _notKeywords = <String>{r'$pattern'};

final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Every keyword [mode] and its descendants declare, sorted and deduplicated.
///
/// Filtered to things that look like identifiers: a grammar's keyword list
/// often contains regex fragments and punctuation, which are not useful
/// completions and would look like noise in the popup.
List<String> harvestKeywords(Mode? mode, {int minLength = 3}) {
  if (mode == null) {
    return const <String>[];
  }
  final Set<String> found = <String>{};
  final List<Mode> queue = <Mode>[mode];
  final Set<Mode> seen = Set<Mode>.identity();
  int visited = 0;

  while (queue.isNotEmpty && visited < _maxNodes) {
    final Mode node = queue.removeLast();
    if (!seen.add(node)) {
      continue;
    }
    visited++;

    _collect(node.keywords, found, minLength);
    final String? begins = node.beginKeywords;
    if (begins != null) {
      _addAll(begins.split(' '), found, minLength);
    }

    _enqueue(node.contains, queue);
    _enqueue(node.variants, queue);
    final Mode? starts = node.starts;
    if (starts != null) {
      queue.add(starts);
    }
  }

  final List<String> keywords = found.toList()..sort();
  return keywords;
}

void _enqueue(Object? value, List<Mode> queue) {
  if (value is List) {
    for (final Object? child in value) {
      if (child is Mode) {
        queue.add(child);
      }
    }
  } else if (value is Mode) {
    queue.add(value);
  }
}

void _collect(Object? keywords, Set<String> out, int minLength) {
  if (keywords is String) {
    _addAll(keywords.split(' '), out, minLength);
    return;
  }
  if (keywords is Map) {
    for (final MapEntry<Object?, Object?> entry in keywords.entries) {
      if (_notKeywords.contains(entry.key)) {
        continue;
      }
      final Object? value = entry.value;
      if (value is String) {
        _addAll(value.split(' '), out, minLength);
      } else if (value is List) {
        _addAll(value.whereType<String>(), out, minLength);
      }
    }
  }
}

void _addAll(Iterable<String> words, Set<String> out, int minLength) {
  for (final String raw in words) {
    // Grammars write relevance as `word|10`; the word is what matters here.
    final String word = raw.split('|').first.trim();
    if (word.length < minLength || !_identifier.hasMatch(word)) {
      continue;
    }
    out.add(word);
  }
}

/// Keywords per language, harvested once per process.
///
/// Walking a grammar is cheap but not free, and the same language is asked for
/// on every keystroke in a file, so the result is cached.
abstract final class LanguageKeywords {
  static final Map<String, List<String>> _cache = <String, List<String>>{};

  static List<String> forLanguage(LanguageDefinition language) =>
      _cache.putIfAbsent(language.id, () => harvestKeywords(language.mode));

  /// Only for tests that need a cold cache.
  static void clearCache() => _cache.clear();
}
