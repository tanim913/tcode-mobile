/// Scoring subsequence matcher for Quick Open, Go to Symbol and the palette.
///
/// Returns the matched character positions alongside the score, because a fuzzy
/// list that does not show *why* a row matched is guesswork for the reader — the
/// highlight is what makes the ranking legible.
///
/// The score is an integer sum of named bonuses solved by dynamic programming,
/// not a greedy walk. A greedy matcher takes the first occurrence of each
/// pattern character and so ranks `human.dart` above `main.dart` for `mn`; the
/// DP picks the run that scores best overall, which is the whole point.
library;

/// A successful match of a pattern against a candidate.
class FuzzyMatch {
  const FuzzyMatch({required this.score, required this.indices});

  /// Higher is better. Only meaningful when comparing matches of the *same*
  /// pattern against different candidates.
  final int score;

  /// Ascending indices into the candidate string that the pattern matched.
  /// Empty when the pattern was empty.
  final List<int> indices;

  @override
  String toString() => 'FuzzyMatch(score: $score, indices: $indices)';
}

abstract final class FuzzyMatcher {
  /// Paid once per matched character, so a longer match beats a shorter one.
  static const int matchScore = 16;

  /// Typing the same case the candidate uses is a weak signal, but a real one.
  static const int sameCaseBonus = 2;

  /// A run of adjacent characters, e.g. `sea` in `search`.
  static const int consecutiveBonus = 21;

  /// First character of a `/`, `_`, `-`, `.` or space separated segment.
  ///
  /// Deliberately worth *more* than a consecutive character. People type
  /// initials — `fsp` for `file_system_provider` — far more often than they
  /// type a substring from the middle of a word, so `offsprings` must not
  /// outrank it on the strength of one adjacent pair.
  static const int boundaryBonus = 24;

  /// The capital in `fooBar`, which users type as `fb`. Just under
  /// [boundaryBonus]: an explicit separator is a stronger signal than a case
  /// change, which also occurs inside acronyms.
  static const int camelBonus = 22;

  /// First character of the file name itself. Ranked highest because that is
  /// how people think about files: `mai` means `main.dart`, not `src/mai…`.
  static const int basenameStartBonus = 40;

  /// Any match inside the file name beats the same match in a folder segment.
  static const int inBasenameBonus = 8;

  /// The basename, with or without its extension, is exactly the pattern.
  /// Large enough that an exact hit is never buried by path depth.
  static const int exactBasenameBonus = 80;

  /// Skipping characters before the first match costs one point each, capped so
  /// a deeply nested file is not ranked out of existence by its own path depth.
  static const int maxLeadingPenalty = 12;

  /// Sentinel for "no path reaches this cell". Far enough from real scores that
  /// arithmetic on it cannot accidentally look like a valid score.
  static const int _unreachable = -1 << 30;

  static const String _boundaryCharacters = r'/\_-. :';

  /// Scores [pattern] against [candidate], or returns null when [pattern] is
  /// not a subsequence of it.
  ///
  /// [candidate] may be a path; the basename is located by the last separator.
  static FuzzyMatch? match(String pattern, String candidate) {
    if (pattern.isEmpty) {
      return const FuzzyMatch(score: 0, indices: <int>[]);
    }
    if (pattern.length > candidate.length) {
      return null;
    }

    final String lowerPattern = pattern.toLowerCase();
    final String lowerCandidate = candidate.toLowerCase();
    if (!_isSubsequence(lowerPattern, lowerCandidate)) {
      return null;
    }

    final int basenameStart = _basenameStart(candidate);
    final int n = lowerPattern.length;
    final int m = lowerCandidate.length;

    // table[k][j] is the best score for matching pattern[0..k] with pattern[k]
    // landing exactly on candidate[j]. parents[k][j] records where pattern[k-1]
    // landed on that best path, so the indices can be recovered afterwards.
    final List<List<int>> table = List<List<int>>.generate(
      n,
      (int _) => List<int>.filled(m, _unreachable),
      growable: false,
    );
    final List<List<int>> parents = List<List<int>>.generate(
      n,
      (int _) => List<int>.filled(m, -1),
      growable: false,
    );

    for (int j = 0; j < m; j++) {
      if (lowerCandidate.codeUnitAt(j) != lowerPattern.codeUnitAt(0)) {
        continue;
      }
      final int leadingGap = j < maxLeadingPenalty ? j : maxLeadingPenalty;
      table[0][j] = _characterScore(
            pattern: pattern,
            candidate: candidate,
            patternIndex: 0,
            candidateIndex: j,
            basenameStart: basenameStart,
          ) -
          leadingGap;
    }

    for (int k = 1; k < n; k++) {
      final List<int> previous = table[k - 1];
      // reach[j] is the best previous-row score still available at j after
      // paying one point per skipped character. Tracking it as a running max is
      // what keeps the whole matcher O(pattern x candidate).
      final List<int> reach = List<int>.filled(m, _unreachable);
      final List<int> reachFrom = List<int>.filled(m, -1);
      for (int j = 0; j < m; j++) {
        final int decayed = j == 0 || reach[j - 1] <= _unreachable
            ? _unreachable
            : reach[j - 1] - 1;
        if (previous[j] >= decayed) {
          reach[j] = previous[j];
          reachFrom[j] = j;
        } else {
          reach[j] = decayed;
          reachFrom[j] = reachFrom[j - 1];
        }
      }

      for (int j = k; j < m; j++) {
        if (lowerCandidate.codeUnitAt(j) != lowerPattern.codeUnitAt(k)) {
          continue;
        }
        int best = _unreachable;
        int from = -1;
        if (previous[j - 1] > _unreachable) {
          best = previous[j - 1] + consecutiveBonus;
          from = j - 1;
        }
        if (j >= 2 && reach[j - 2] > _unreachable) {
          final int gapped = reach[j - 2] - 1;
          if (gapped > best) {
            best = gapped;
            from = reachFrom[j - 2];
          }
        }
        if (best <= _unreachable) {
          continue;
        }
        table[k][j] = best +
            _characterScore(
              pattern: pattern,
              candidate: candidate,
              patternIndex: k,
              candidateIndex: j,
              basenameStart: basenameStart,
            );
        parents[k][j] = from;
      }
    }

    int bestEnd = -1;
    int bestScore = _unreachable;
    for (int j = 0; j < m; j++) {
      if (table[n - 1][j] > bestScore) {
        bestScore = table[n - 1][j];
        bestEnd = j;
      }
    }
    if (bestEnd < 0) {
      return null;
    }

    final List<int> indices = List<int>.filled(n, 0);
    int cursor = bestEnd;
    for (int k = n - 1; k >= 0; k--) {
      indices[k] = cursor;
      cursor = parents[k][cursor];
    }

    // Shorter candidates win ties: one point per character is small next to the
    // bonuses, so it only decides between otherwise equal matches.
    int score = bestScore - candidate.length;
    if (_isExactBasename(lowerCandidate, basenameStart, lowerPattern)) {
      score += exactBasenameBonus;
    }
    return FuzzyMatch(score: score, indices: indices);
  }

  /// Cheap rejection so the DP only runs on candidates that can match at all.
  static bool _isSubsequence(String lowerPattern, String lowerCandidate) {
    int p = 0;
    for (int i = 0; i < lowerCandidate.length && p < lowerPattern.length; i++) {
      if (lowerCandidate.codeUnitAt(i) == lowerPattern.codeUnitAt(p)) {
        p++;
      }
    }
    return p == lowerPattern.length;
  }

  /// Whether the pattern is the whole file name, ignoring its extension.
  ///
  /// Typing `main` means `main.dart`, and no amount of nesting should let
  /// `main_window.dart` come first.
  static bool _isExactBasename(
    String lowerCandidate,
    int basenameStart,
    String lowerPattern,
  ) {
    final String basename = lowerCandidate.substring(basenameStart);
    if (basename == lowerPattern) {
      return true;
    }
    final int dot = basename.lastIndexOf('.');
    return dot > 0 && basename.substring(0, dot) == lowerPattern;
  }

  static int _basenameStart(String candidate) {
    for (int i = candidate.length - 1; i >= 0; i--) {
      final int unit = candidate.codeUnitAt(i);
      if (unit == 0x2F || unit == 0x5C) {
        return i + 1;
      }
    }
    return 0;
  }

  static int _characterScore({
    required String pattern,
    required String candidate,
    required int patternIndex,
    required int candidateIndex,
    required int basenameStart,
  }) {
    int score = matchScore;
    if (pattern.codeUnitAt(patternIndex) ==
        candidate.codeUnitAt(candidateIndex)) {
      score += sameCaseBonus;
    }
    if (candidateIndex == basenameStart) {
      score += basenameStartBonus;
    } else if (_isBoundaryStart(candidate, candidateIndex)) {
      score += boundaryBonus;
    } else if (_isCamelStart(candidate, candidateIndex)) {
      score += camelBonus;
    }
    if (candidateIndex >= basenameStart) {
      score += inBasenameBonus;
    }
    return score;
  }

  static bool _isBoundaryStart(String candidate, int index) {
    if (index == 0) {
      return true;
    }
    return _boundaryCharacters.contains(candidate[index - 1]);
  }

  static bool _isCamelStart(String candidate, int index) {
    if (index == 0) {
      return false;
    }
    final int here = candidate.codeUnitAt(index);
    final int before = candidate.codeUnitAt(index - 1);
    final bool hereUpper = here >= 0x41 && here <= 0x5A;
    final bool beforeLowerOrDigit =
        (before >= 0x61 && before <= 0x7A) || (before >= 0x30 && before <= 0x39);
    return hereUpper && beforeLowerOrDigit;
  }
}
