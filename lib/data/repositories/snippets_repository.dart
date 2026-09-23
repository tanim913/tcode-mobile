/// Loads and saves the user's snippet library.
library;

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';

class SnippetsRepository {
  const SnippetsRepository(this._storage);

  static const String fileName = 'snippets.json';

  final SupportStorage _storage;

  /// Every saved snippet, or an empty list when there is nothing to read.
  ///
  /// A malformed entry is dropped rather than failing the whole load: losing
  /// one snippet is recoverable, losing the library is not.
  Future<List<Snippet>> load() async {
    final Map<String, Object?>? json = await _storage.readJson(fileName);
    final Object? items = json?['snippets'];
    if (items is! List) {
      return const <Snippet>[];
    }
    return <Snippet>[
      for (final Object? item in items)
        if (item is Map<String, Object?>)
          if (Snippet.fromJson(item) case final Snippet snippet) snippet,
    ].take(AppLimits.maxSnippets).toList();
  }

  Future<void> save(List<Snippet> snippets) => _storage.writeJson(
        fileName,
        <String, Object?>{
          'version': 1,
          'snippets': snippets
              .take(AppLimits.maxSnippets)
              .map((Snippet s) => s.toJson())
              .toList(),
        },
      );
}
