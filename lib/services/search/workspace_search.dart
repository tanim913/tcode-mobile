/// Searching, and replacing, across every file in the workspace.
///
/// Two halves, split so the hard part is testable without a file system:
///
/// * [findMatchesInText] is a pure function over one string. Every rule about
///   case, whole words, regex and where a match sits lives there.
/// * [WorkspaceSearch] walks the index and applies it, skipping what cannot
///   sensibly be searched and stopping at a stated limit.
///
/// The walk yields to the event loop between files rather than using an
/// isolate, for the same reason [FileIndexer] does: the providers cannot all be
/// sent to one, and the work is mostly awaiting I/O anyway.
library;

import 'dart:typed_data';

import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/text_codec.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

/// What to look for.
class SearchQuery {
  const SearchQuery({
    required this.pattern,
    this.caseSensitive = false,
    this.wholeWord = false,
    this.regex = false,
  });

  final String pattern;
  final bool caseSensitive;
  final bool wholeWord;
  final bool regex;

  bool get isEmpty => pattern.isEmpty;

  /// Compiles the query, or returns null when the user's regex does not parse.
  ///
  /// Returning null rather than throwing lets the panel show "not a valid
  /// pattern" while the user is still typing it, which is most of the time.
  RegExp? compile() {
    if (pattern.isEmpty) {
      return null;
    }
    final String body = regex ? pattern : RegExp.escape(pattern);
    // Whole word is the same `\b` emulation the in-file find panel uses, so
    // both surfaces agree on what a word boundary is.
    final String source = wholeWord ? r'\b' + body + r'\b' : body;
    try {
      return RegExp(source, caseSensitive: caseSensitive, multiLine: true);
    } on FormatException {
      return null;
    }
  }
}

/// One hit, with enough context to render a row and to jump to it.
class SearchMatch {
  const SearchMatch({
    required this.line,
    required this.column,
    required this.lineText,
    required this.start,
    required this.length,
  });

  /// 1-based, matching the editor and the status bar.
  final int line;

  /// 1-based column of the match within its line.
  final int column;

  /// The whole line, for the preview row.
  final String lineText;

  /// Offset of the match within [lineText], for highlighting.
  final int start;

  final int length;
}

/// Every match in one file.
class FileMatches {
  const FileMatches({required this.file, required this.matches});

  final IndexedFile file;
  final List<SearchMatch> matches;
}

/// The outcome of a search.
class SearchResults {
  const SearchResults({
    required this.files,
    required this.truncated,
    required this.filesSearched,
    required this.filesSkipped,
  });

  const SearchResults.empty()
      : files = const <FileMatches>[],
        truncated = false,
        filesSearched = 0,
        filesSkipped = 0;

  final List<FileMatches> files;

  /// True when [AppLimits.searchResultLimit] was reached. Said out loud in the
  /// UI, because a quietly capped result list misrepresents the workspace.
  final bool truncated;

  final int filesSearched;

  /// Files that were too large or not text. Reported rather than hidden, so
  /// "not found" never silently means "not looked at".
  final int filesSkipped;

  int get matchCount =>
      files.fold(0, (int sum, FileMatches f) => sum + f.matches.length);
}

/// Finds every match of [query] in [text].
///
/// Pure and synchronous: this is where the search rules are pinned down.
List<SearchMatch> findMatchesInText(String text, SearchQuery query) {
  final RegExp? expression = query.compile();
  if (expression == null || text.isEmpty) {
    return const <SearchMatch>[];
  }

  final List<SearchMatch> matches = <SearchMatch>[];
  final List<String> lines = text.split('\n');
  for (int i = 0; i < lines.length; i++) {
    final String line = lines[i];
    for (final RegExpMatch match in expression.allMatches(line)) {
      // A zero-width match (`a*` against an empty run) would otherwise produce
      // one hit per character and drown the results.
      if (match.end == match.start) {
        continue;
      }
      matches.add(
        SearchMatch(
          line: i + 1,
          column: match.start + 1,
          lineText: line,
          start: match.start,
          length: match.end - match.start,
        ),
      );
    }
  }
  return matches;
}

/// Applies every match of [query] in [text], replacing each with [replacement].
///
/// Kept beside the finder so replace can never disagree with what was shown:
/// the same compiled expression drives both.
String replaceAllInText(String text, SearchQuery query, String replacement) {
  final RegExp? expression = query.compile();
  if (expression == null) {
    return text;
  }
  return text.replaceAllMapped(expression, (Match m) {
    if (m.end == m.start) {
      return m[0]!;
    }
    // `replaceAllMapped` hands back whatever the callback returns, verbatim —
    // it does no `$1` expansion of its own. So literal mode needs no escaping,
    // and regex mode has to expand groups here or `$1` would never work.
    return query.regex ? expandGroups(replacement, m) : replacement;
  });
}

/// Expands `$0`–`$9` in [replacement] from [match]; `$$` is a literal `$`.
///
/// A reference to a group the pattern does not have is left as typed rather
/// than silently becoming empty, so a mistake is visible instead of deleting
/// text.
String expandGroups(String replacement, Match match) {
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < replacement.length; i++) {
    final String c = replacement[i];
    if (c != r'$' || i + 1 >= replacement.length) {
      out.write(c);
      continue;
    }
    final String next = replacement[i + 1];
    if (next == r'$') {
      out.write(r'$');
      i++;
      continue;
    }
    final int? group = int.tryParse(next);
    if (group == null || group > match.groupCount) {
      out.write(c);
      continue;
    }
    out.write(match[group] ?? '');
    i++;
  }
  return out.toString();
}

class WorkspaceSearch {
  const WorkspaceSearch({
    this.resultLimit = AppLimits.searchResultLimit,
    this.maxFileBytes = AppLimits.maxSearchableFileBytes,
  });

  final int resultLimit;

  /// Files above this are skipped. Reading a 40 MB minified bundle into a
  /// string to search it is how a phone runs out of memory.
  final int maxFileBytes;

  /// Searches every file in [index].
  Future<SearchResults> run({
    required FileIndex index,
    required SearchQuery query,
    required FileSystemProvider Function(int rootIndex) providerFor,
  }) async {
    if (query.isEmpty || query.compile() == null) {
      return const SearchResults.empty();
    }

    final List<FileMatches> results = <FileMatches>[];
    int total = 0;
    int searched = 0;
    int skipped = 0;
    bool truncated = false;

    for (final IndexedFile file in index.files) {
      if (truncated) {
        break;
      }
      final FileSystemProvider provider = providerFor(file.rootIndex);

      // The index already carries the size the listing reported, so a huge file
      // is skipped without reading a byte of it.
      if (file.node.size > maxFileBytes) {
        skipped++;
        continue;
      }

      final String text;
      try {
        final Uint8List bytes = await provider.readBytes(file.node.id);
        // Binary files are skipped rather than searched: a match inside a PNG
        // is noise, and rendering its "line" would be gibberish.
        if (TextCodec.isBinary(bytes)) {
          skipped++;
          continue;
        }
        text = (await provider.readText(file.node.id)).text;
      } on AppFailure {
        // Unreadable is not a match and not a crash; it is a skip we admit to.
        skipped++;
        continue;
      }

      searched++;
      final List<SearchMatch> matches = findMatchesInText(text, query);
      if (matches.isEmpty) {
        continue;
      }

      final int room = resultLimit - total;
      if (matches.length >= room) {
        results.add(
          FileMatches(file: file, matches: matches.sublist(0, room)),
        );
        total = resultLimit;
        truncated = true;
        break;
      }

      results.add(FileMatches(file: file, matches: matches));
      total += matches.length;
      await Future<void>.delayed(Duration.zero);
    }

    return SearchResults(
      files: results,
      truncated: truncated,
      filesSearched: searched,
      filesSkipped: skipped,
    );
  }
}
