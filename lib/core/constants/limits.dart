/// Size and performance thresholds.
///
/// These are defaults. The brief requires them to be tunable from settings,
/// so nothing should read these constants directly once settings exist — they
/// seed [AppSettings] instead.
library;

abstract final class AppLimits {
  /// Above this, opening asks for confirmation first.
  static const int warnFileSizeBytes = 2 * 1024 * 1024; // 2 MB

  /// Above this, the file opens read-only with highlighting disabled.
  static const int readOnlyFileSizeBytes = 10 * 1024 * 1024; // 10 MB

  /// Above this, the editor refuses and offers Open With / Share instead.
  static const int refuseFileSizeBytes = 50 * 1024 * 1024; // 50 MB

  /// A single line longer than this (minified bundles, generated data) makes
  /// highlighting pathologically slow, so it is disabled for the whole file.
  static const int longLineCharacters = 10000;

  /// Bytes inspected when deciding whether a file is binary.
  static const int binarySniffBytes = 8 * 1024;

  /// Files larger than this are skipped by workspace content search.
  static const int maxSearchableFileBytes = 1024 * 1024; // 1 MB

  /// Cap on search results before the UI offers "Show more".
  static const int searchResultLimit = 2000;

  /// Tree rows revealed by an expand animate in only when there are this few;
  /// beyond it they appear instantly to protect frame time.
  static const int animatedRevealMaxRows = 40;

  /// Completion: the shortest run of characters that opens the popup. Below
  /// this it would flash open on the first letter of every word typed.
  static const int completionMinPrefix = 2;

  /// Words shorter than this are not worth suggesting — typing them in full is
  /// faster than reading a list.
  static const int completionMinWordLength = 3;

  /// Cap on identifiers indexed from one buffer, so a generated data file
  /// cannot grow the index without bound.
  static const int completionMaxIndexedWords = 20000;

  /// Suggestions offered at once. More than this cannot be read on a phone.
  static const int completionMaxPrompts = 12;

  /// Above this the buffer is not indexed at all. Language keywords still work,
  /// so completion degrades rather than disappearing.
  static const int completionMaxFileBytes = 2 * 1024 * 1024; // 2 MB

  /// Above this many lines a diff degrades to "replaced" rather than spending
  /// unbounded time on an optimal edit script.
  static const int maxDiffLines = 20000;

  /// Snippets kept. Far more than anyone writes by hand, and low enough that
  /// a corrupt file cannot make startup slow.
  static const int maxSnippets = 500;

  /// Lines scanned in each direction when looking for a matching bracket.
  /// Past this the jump gives up rather than stalling a frame on a minified
  /// file that is one enormous line.
  static const int bracketScanMaxLines = 5000;

  /// Closed tabs retained for "Reopen Closed Tab".
  static const int reopenableTabHistory = 20;

  static const int maxRecentWorkspaces = 20;
  static const int maxRecentFiles = 50;

  /// Editor font size bounds, enforced by both pinch zoom and the settings
  /// slider so the two can never disagree.
  static const double minFontSize = 8;
  static const double maxFontSize = 36;
  static const double defaultFontSize = 14;
}
