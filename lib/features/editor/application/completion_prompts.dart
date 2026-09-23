/// Choosing and ordering what the completion popup offers.
///
/// The ranking is a free function with no editor in sight, because this is the
/// part whose behaviour anyone would argue about — and the only part that can
/// be tested, since the popup itself needs a laid-out, focused editor.
library;

import 'package:flutter/widgets.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/features/editor/application/word_index.dart';
import 'package:re_editor/re_editor.dart';

/// Where a suggestion came from. Shown beside it, so an unfamiliar word is
/// explained rather than just appearing.
enum CompletionKind { buffer, keyword }

String labelFor(CompletionKind kind) => switch (kind) {
      CompletionKind.buffer => 'in file',
      CompletionKind.keyword => 'keyword',
    };

/// A suggestion before it becomes a `re_editor` prompt.
@immutable
class Completion {
  const Completion(this.word, this.kind);

  final String word;
  final CompletionKind kind;

  @override
  bool operator ==(Object other) =>
      other is Completion && other.word == word && other.kind == kind;

  @override
  int get hashCode => Object.hash(word, kind);

  @override
  String toString() => '$word (${labelFor(kind)})';
}

/// The suggestions for [input], best first.
///
/// Order: **buffer words before keywords.** In a real file the identifier about
/// to be typed is overwhelmingly one that already appears in it, and a keyword
/// is short enough to type in full. Within each group, shorter first — the
/// shortest completion of a prefix is the likeliest — then alphabetical so the
/// list does not reshuffle between keystrokes.
///
/// The word being typed is excluded: offering the user what they have already
/// written is noise, and accepting it would do nothing.
List<Completion> rankCompletions({
  required String input,
  required Set<String> bufferWords,
  required List<String> keywords,
  int max = AppLimits.completionMaxPrompts,
}) {
  if (input.isEmpty) {
    return const <Completion>[];
  }
  final String lower = input.toLowerCase();

  bool matches(String word) =>
      word.length > input.length && word.toLowerCase().startsWith(lower);

  int byLengthThenName(String a, String b) {
    final int byLength = a.length.compareTo(b.length);
    return byLength != 0 ? byLength : a.compareTo(b);
  }

  final List<String> fromBuffer = bufferWords.where(matches).toList()
    ..sort(byLengthThenName);
  final Set<String> taken = fromBuffer.toSet();
  final List<String> fromKeywords =
      keywords.where((String w) => matches(w) && !taken.contains(w)).toList()
        ..sort(byLengthThenName);

  return <Completion>[
    for (final String word in fromBuffer) Completion(word, CompletionKind.buffer),
    for (final String word in fromKeywords)
      Completion(word, CompletionKind.keyword),
  ].take(max).toList();
}

/// Turns ranked completions into the prompts `re_editor` accepts.
List<CodePrompt> promptsFor(List<Completion> completions) => <CodePrompt>[
      for (final Completion c in completions)
        CodeFieldPrompt(word: c.word, type: labelFor(c.kind)),
    ];

/// Supplies the popup's contents on every keystroke.
///
/// `re_editor` calls [build] **synchronously** while handling a code change and
/// hands over only the current line — never the document. So the buffer index
/// has to live outside and be ready before the call, which is what
/// `AutocompleteController` is for.
class WordPromptsBuilder implements CodeAutocompletePromptsBuilder {
  const WordPromptsBuilder({
    required this.enabled,
    required this.bufferWords,
    required this.keywords,
    required this.lineComment,
  });

  /// Read at call time rather than captured, so a rebuilt index is picked up
  /// without replacing the builder.
  final bool Function() enabled;
  final Set<String> Function() bufferWords;
  final List<String> Function() keywords;
  final String? Function() lineComment;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    if (!enabled() || !selection.isCollapsed) {
      return null;
    }
    final String text = codeLine.text;
    final int offset = selection.extentOffset;
    if (insideStringOrComment(text, offset, lineComment: lineComment())) {
      return null;
    }
    final ({int start, String input})? word = identifierBefore(text, offset);
    if (word == null) {
      return null;
    }
    final List<Completion> ranked = rankCompletions(
      input: word.input,
      bufferWords: bufferWords(),
      keywords: keywords(),
    );
    if (ranked.isEmpty) {
      return null;
    }
    return CodeAutocompleteEditingValue(
      input: word.input,
      prompts: promptsFor(ranked),
      index: 0,
    );
  }
}
