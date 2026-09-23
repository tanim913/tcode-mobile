/// A reusable piece of text the user can insert by name.
///
/// Stored in a JSON file rather than in the settings blob: settings are
/// rewritten in full on every change, including each tick of the font-size
/// slider, and a snippet library grows. `SettingsRepository`'s own doc comment
/// makes that rule explicit.
library;

/// Marks where the caret should land after inserting. One stop, not a full set
/// of numbered tab stops: `re_editor` has no tab-stop machinery, so anything
/// beyond this would mean owning selection state across later edits. `$0` is
/// what almost every real snippet actually needs.
const String kSnippetCursorMarker = r'$0';

/// Language id meaning "offer this everywhere".
const String kAnyLanguage = '*';

class Snippet {
  const Snippet({
    required this.id,
    required this.prefix,
    required this.body,
    this.description = '',
    this.languageIds = const <String>[kAnyLanguage],
  });

  /// Stable id. Microseconds, for the same reason the trash uses them: two
  /// snippets created in one millisecond must not collide.
  final String id;

  /// What the user types to reach it.
  final String prefix;

  final String body;
  final String description;

  /// Language ids this applies to, or `['*']` for all of them.
  final List<String> languageIds;

  bool get appliesToAll => languageIds.contains(kAnyLanguage);

  bool appliesTo(String languageId) =>
      appliesToAll || languageIds.contains(languageId);

  Snippet copyWith({
    String? prefix,
    String? body,
    String? description,
    List<String>? languageIds,
  }) =>
      Snippet(
        id: id,
        prefix: prefix ?? this.prefix,
        body: body ?? this.body,
        description: description ?? this.description,
        languageIds: languageIds ?? this.languageIds,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'prefix': prefix,
        'body': body,
        if (description.isNotEmpty) 'description': description,
        'languages': languageIds,
      };

  /// Lenient, like every other model here: one malformed entry written by a
  /// different version must not cost the user their whole library.
  static Snippet? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? prefix = json['prefix'];
    final Object? body = json['body'];
    if (id is! String || prefix is! String || body is! String) {
      return null;
    }
    if (prefix.isEmpty || body.isEmpty) {
      return null;
    }
    final Object? languages = json['languages'];
    return Snippet(
      id: id,
      prefix: prefix,
      body: body,
      description: json['description'] is String
          ? json['description']! as String
          : '',
      languageIds: languages is List
          ? languages.whereType<String>().toList()
          : const <String>[kAnyLanguage],
    );
  }

  @override
  String toString() => 'Snippet($prefix)';
}

/// The text to insert, and where the caret should end up.
typedef ExpandedSnippet = ({String text, int lineOffset, int column});

/// Prepares [body] for insertion at a line indented by [lineIndent].
///
/// Two things happen. Every line after the first is re-indented to match the
/// line the snippet is being inserted into — without that, a multi-line snippet
/// lands flush against column zero. And a single [kSnippetCursorMarker] is
/// removed, with its position reported so the caller can put the caret there.
///
/// Buffers are normalised to `\n` internally (`text_codec.dart`), so this never
/// has to think about CRLF.
ExpandedSnippet expandSnippet(String body, {required String lineIndent}) {
  final List<String> lines = body.split('\n');
  final StringBuffer out = StringBuffer();

  int? cursorLine;
  int? cursorColumn;

  for (int i = 0; i < lines.length; i++) {
    // The first line starts where the caret already is, so it is not indented.
    final String prefix = i == 0 ? '' : lineIndent;
    String line = lines[i];

    if (cursorLine == null) {
      final int marker = line.indexOf(kSnippetCursorMarker);
      if (marker >= 0) {
        cursorLine = i;
        cursorColumn = prefix.length + marker;
        line = line.replaceFirst(kSnippetCursorMarker, '');
      }
    }

    out.write(prefix);
    out.write(line);
    if (i != lines.length - 1) {
      out.write('\n');
    }
  }

  final String text = out.toString();
  if (cursorLine == null || cursorColumn == null) {
    // No marker: the caret goes to the end, which is where typing would have
    // left it.
    final List<String> written = text.split('\n');
    return (
      text: text,
      lineOffset: written.length - 1,
      column: written.last.length,
    );
  }
  return (text: text, lineOffset: cursorLine, column: cursorColumn);
}

/// Why a snippet cannot be saved, or null when it can.
///
/// A free function, exported for testing, exactly as `validateExcludePattern`
/// is — the rule is the part worth covering, not the dialog around it.
String? validateSnippet(
  Snippet candidate,
  List<Snippet> existing, {
  int maxBodyChars = 8000,
}) {
  final String prefix = candidate.prefix.trim();
  if (prefix.isEmpty) {
    return 'Give the snippet a short name to type.';
  }
  if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_$]*$').hasMatch(prefix)) {
    return 'Use letters, digits and underscores, starting with a letter.';
  }
  if (prefix.length < 2) {
    return 'Use at least two characters, or it will be offered constantly.';
  }
  if (candidate.body.isEmpty) {
    return 'A snippet needs something to insert.';
  }
  if (candidate.body.length > maxBodyChars) {
    return 'That snippet is longer than $maxBodyChars characters.';
  }
  if (candidate.languageIds.isEmpty) {
    return 'Choose at least one language, or All languages.';
  }
  for (final Snippet other in existing) {
    if (other.id == candidate.id) {
      continue;
    }
    if (other.prefix != prefix) {
      continue;
    }
    // Two snippets may share a name only if they never apply at once.
    final bool overlap = other.appliesToAll ||
        candidate.appliesToAll ||
        other.languageIds.any(candidate.languageIds.contains);
    if (overlap) {
      return 'Another snippet already uses "$prefix" for that language.';
    }
  }
  return null;
}

/// Snippets that apply to [languageId], in the order they were defined.
List<Snippet> snippetsFor(List<Snippet> all, String languageId) =>
    all.where((Snippet s) => s.appliesTo(languageId)).toList();
