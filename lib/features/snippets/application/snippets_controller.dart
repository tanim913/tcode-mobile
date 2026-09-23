/// The user's snippet library, and the writes that persist it.
///
/// Seeded from `bootstrap()` so the first frame has it synchronously — the same
/// shape as `SettingsNotifier`, for the same reason.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/data/models/snippet.dart';

class SnippetsController extends Notifier<List<Snippet>> {
  @override
  List<Snippet> build() => ref.read(initialSnippetsProvider);

  Future<void> _persist(List<Snippet> next) async {
    state = next;
    await ref.read(snippetsRepositoryProvider)?.save(next);
  }

  /// A new snippet, or null when the library is full.
  Future<Snippet?> add({
    required String prefix,
    required String body,
    String description = '',
    List<String> languageIds = const <String>[kAnyLanguage],
  }) async {
    if (state.length >= AppLimits.maxSnippets) {
      return null;
    }
    final Snippet snippet = Snippet(
      // Microseconds, like the trash's batch folders: two snippets created in
      // the same millisecond must not share an id.
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      prefix: prefix.trim(),
      body: body,
      description: description.trim(),
      languageIds: languageIds,
    );
    await _persist(<Snippet>[...state, snippet]);
    return snippet;
  }

  Future<void> update(Snippet snippet) => _persist(<Snippet>[
        for (final Snippet s in state)
          if (s.id == snippet.id) snippet else s,
      ]);

  Future<void> remove(String id) =>
      _persist(state.where((Snippet s) => s.id != id).toList());

  Future<void> clear() => _persist(const <Snippet>[]);
}

final NotifierProvider<SnippetsController, List<Snippet>> snippetsProvider =
    NotifierProvider<SnippetsController, List<Snippet>>(
  SnippetsController.new,
);
