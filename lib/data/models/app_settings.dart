/// User settings, persisted and applied across the whole app.
///
/// Split into groups that match the settings screen sections, so a new setting
/// lands in one obvious place. Everything is immutable with `copyWith`, which
/// makes "change one setting" a cheap, safely-diffable state update.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/core/constants/limits.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/core/theme/editor_theme_registry.dart';

/// When unsaved changes get written back to disk.
enum AutoSaveMode {
  off('Off'),
  afterDelay('After a delay'),
  onFocusLost('When the app loses focus');

  const AutoSaveMode(this.label);

  final String label;
}

/// Order files appear in within the explorer. Folders always come first.
enum ExplorerSortOrder {
  name('Name'),
  type('Type'),
  modified('Last modified');

  const ExplorerSortOrder(this.label);

  final String label;
}

/// Monospace faces bundled with the app. Both work offline.
enum EditorFontFamily {
  jetBrainsMono('JetBrains Mono', 'JetBrains Mono'),
  firaCode('Fira Code', 'Fira Code'),
  systemMono('System monospace', 'monospace');

  const EditorFontFamily(this.label, this.family);

  final String label;

  /// The value handed to [TextStyle.fontFamily].
  final String family;
}

@immutable
class EditorSettings {
  const EditorSettings({
    this.fontSize = AppLimits.defaultFontSize,
    this.fontFamily = EditorFontFamily.jetBrainsMono,
    this.ligatures = true,
    this.lineHeight = 1.4,
    this.wordWrap = false,
    this.tabSize = 2,
    this.insertSpaces = true,
    this.detectIndentation = true,
    this.showLineNumbers = true,
    this.highlightCurrentLine = true,
    this.autoClosingPairs = true,
    this.codeFolding = true,
    this.wordCompletion = true,
    this.fileHistory = true,
    this.historyMaxVersions = 50,
    this.historyMaxAgeDays = 30,
    this.historyMaxBytesPerFile = 5 * 1024 * 1024,
    this.autoSaveMode = AutoSaveMode.afterDelay,
    this.autoSaveDelayMs = 1000,
  });

  /// Every field falls back to its default. A settings file written by an older
  /// or newer version must never stop the app from starting.
  factory EditorSettings.fromJson(Map<String, Object?> json) {
    const EditorSettings d = EditorSettings();
    return EditorSettings(
      fontSize: _double(json['fontSize'], d.fontSize)
          .clamp(AppLimits.minFontSize, AppLimits.maxFontSize),
      fontFamily: _enum(EditorFontFamily.values, json['fontFamily'], d.fontFamily),
      ligatures: _bool(json['ligatures'], d.ligatures),
      lineHeight: _double(json['lineHeight'], d.lineHeight),
      wordWrap: _bool(json['wordWrap'], d.wordWrap),
      tabSize: _int(json['tabSize'], d.tabSize).clamp(1, 8),
      insertSpaces: _bool(json['insertSpaces'], d.insertSpaces),
      detectIndentation: _bool(json['detectIndentation'], d.detectIndentation),
      showLineNumbers: _bool(json['showLineNumbers'], d.showLineNumbers),
      highlightCurrentLine:
          _bool(json['highlightCurrentLine'], d.highlightCurrentLine),
      autoClosingPairs: _bool(json['autoClosingPairs'], d.autoClosingPairs),
      codeFolding: _bool(json['codeFolding'], d.codeFolding),
      wordCompletion: _bool(json['wordCompletion'], d.wordCompletion),
      fileHistory: _bool(json['fileHistory'], d.fileHistory),
      historyMaxVersions:
          _int(json['historyMaxVersions'], d.historyMaxVersions).clamp(1, 500),
      historyMaxAgeDays:
          _int(json['historyMaxAgeDays'], d.historyMaxAgeDays).clamp(1, 3650),
      historyMaxBytesPerFile: _int(
        json['historyMaxBytesPerFile'],
        d.historyMaxBytesPerFile,
      ).clamp(64 * 1024, 256 * 1024 * 1024),
      autoSaveMode: _enum(AutoSaveMode.values, json['autoSaveMode'], d.autoSaveMode),
      autoSaveDelayMs: _int(json['autoSaveDelayMs'], d.autoSaveDelayMs),
    );
  }

  /// Shared by pinch zoom and the settings slider — one value, so the two can
  /// never disagree.
  final double fontSize;

  final EditorFontFamily fontFamily;

  /// Programming ligatures (`=>`, `!=`). Disabled via the OpenType `calt`
  /// feature rather than by swapping fonts, so the metrics stay identical.
  final bool ligatures;

  final double lineHeight;
  final bool wordWrap;
  final int tabSize;
  final bool insertSpaces;

  /// When true, a file's own indentation overrides [tabSize]/[insertSpaces].
  final bool detectIndentation;

  final bool showLineNumbers;
  final bool highlightCurrentLine;
  final bool autoClosingPairs;

  /// Fold markers in the gutter. Folding follows brackets, and indentation in
  /// the languages that have no closing bracket.
  final bool codeFolding;

  /// Suggest words while typing, from this file and the language's keywords.
  final bool wordCompletion;

  /// Keep a copy of each file before it is overwritten.
  final bool fileHistory;

  /// Retention: whichever limit is reached first wins.
  final int historyMaxVersions;
  final int historyMaxAgeDays;
  final int historyMaxBytesPerFile;

  final AutoSaveMode autoSaveMode;
  final int autoSaveDelayMs;

  EditorSettings copyWith({
    double? fontSize,
    EditorFontFamily? fontFamily,
    bool? ligatures,
    double? lineHeight,
    bool? wordWrap,
    int? tabSize,
    bool? insertSpaces,
    bool? detectIndentation,
    bool? showLineNumbers,
    bool? highlightCurrentLine,
    bool? autoClosingPairs,
    bool? codeFolding,
    bool? wordCompletion,
    bool? fileHistory,
    int? historyMaxVersions,
    int? historyMaxAgeDays,
    int? historyMaxBytesPerFile,
    AutoSaveMode? autoSaveMode,
    int? autoSaveDelayMs,
  }) {
    return EditorSettings(
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      ligatures: ligatures ?? this.ligatures,
      lineHeight: lineHeight ?? this.lineHeight,
      wordWrap: wordWrap ?? this.wordWrap,
      tabSize: tabSize ?? this.tabSize,
      insertSpaces: insertSpaces ?? this.insertSpaces,
      detectIndentation: detectIndentation ?? this.detectIndentation,
      showLineNumbers: showLineNumbers ?? this.showLineNumbers,
      highlightCurrentLine: highlightCurrentLine ?? this.highlightCurrentLine,
      autoClosingPairs: autoClosingPairs ?? this.autoClosingPairs,
      codeFolding: codeFolding ?? this.codeFolding,
      wordCompletion: wordCompletion ?? this.wordCompletion,
      fileHistory: fileHistory ?? this.fileHistory,
      historyMaxVersions: historyMaxVersions ?? this.historyMaxVersions,
      historyMaxAgeDays: historyMaxAgeDays ?? this.historyMaxAgeDays,
      historyMaxBytesPerFile:
          historyMaxBytesPerFile ?? this.historyMaxBytesPerFile,
      autoSaveMode: autoSaveMode ?? this.autoSaveMode,
      autoSaveDelayMs: autoSaveDelayMs ?? this.autoSaveDelayMs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'fontSize': fontSize,
        'fontFamily': fontFamily.name,
        'ligatures': ligatures,
        'lineHeight': lineHeight,
        'wordWrap': wordWrap,
        'tabSize': tabSize,
        'insertSpaces': insertSpaces,
        'detectIndentation': detectIndentation,
        'showLineNumbers': showLineNumbers,
        'highlightCurrentLine': highlightCurrentLine,
        'autoClosingPairs': autoClosingPairs,
        'codeFolding': codeFolding,
        'wordCompletion': wordCompletion,
        'fileHistory': fileHistory,
        'historyMaxVersions': historyMaxVersions,
        'historyMaxAgeDays': historyMaxAgeDays,
        'historyMaxBytesPerFile': historyMaxBytesPerFile,
        'autoSaveMode': autoSaveMode.name,
        'autoSaveDelayMs': autoSaveDelayMs,
      };

}

@immutable
class AppSettings {
  const AppSettings({
    this.editor = const EditorSettings(),
    this.themeVariant = AppThemeVariant.system,
    this.editorThemeId = EditorThemeRegistry.defaultDarkId,
    this.lightEditorThemeId = EditorThemeRegistry.defaultLightId,
    this.accentColorValue,
    this.showHiddenFiles = false,
    this.sortOrder = ExplorerSortOrder.name,
    this.showFileExtensions = true,
    this.excludePatterns = defaultExcludes,
    this.closeExplorerAfterOpen = true,
    this.showAccessoryBar = true,
    this.accessoryKeyTokens = const <String>[],
    this.restoreSession = true,
    this.confirmDelete = true,
    this.confirmCloseUnsaved = true,
    this.warnFileSizeBytes = AppLimits.warnFileSizeBytes,
    this.readOnlyFileSizeBytes = AppLimits.readOnlyFileSizeBytes,
    this.searchResultLimit = AppLimits.searchResultLimit,
    this.onboardingComplete = false,
  });

  factory AppSettings.fromJson(Map<String, Object?> json) {
    const AppSettings d = AppSettings();
    final Object? editorJson = json['editor'];
    return AppSettings(
      editor: editorJson is Map<String, Object?>
          ? EditorSettings.fromJson(editorJson)
          : d.editor,
      themeVariant:
          _enum(AppThemeVariant.values, json['themeVariant'], d.themeVariant),
      editorThemeId: _string(json['editorThemeId'], d.editorThemeId),
      lightEditorThemeId:
          _string(json['lightEditorThemeId'], d.lightEditorThemeId),
      accentColorValue: json['accentColorValue'] is int
          ? json['accentColorValue']! as int
          : null,
      showHiddenFiles: _bool(json['showHiddenFiles'], d.showHiddenFiles),
      sortOrder: _enum(ExplorerSortOrder.values, json['sortOrder'], d.sortOrder),
      showFileExtensions:
          _bool(json['showFileExtensions'], d.showFileExtensions),
      excludePatterns: _stringList(json['excludePatterns'], d.excludePatterns),
      closeExplorerAfterOpen:
          _bool(json['closeExplorerAfterOpen'], d.closeExplorerAfterOpen),
      showAccessoryBar: _bool(json['showAccessoryBar'], d.showAccessoryBar),
      accessoryKeyTokens:
          _stringList(json['accessoryKeyTokens'], d.accessoryKeyTokens),
      restoreSession: _bool(json['restoreSession'], d.restoreSession),
      confirmDelete: _bool(json['confirmDelete'], d.confirmDelete),
      confirmCloseUnsaved:
          _bool(json['confirmCloseUnsaved'], d.confirmCloseUnsaved),
      warnFileSizeBytes: _int(json['warnFileSizeBytes'], d.warnFileSizeBytes),
      readOnlyFileSizeBytes:
          _int(json['readOnlyFileSizeBytes'], d.readOnlyFileSizeBytes),
      searchResultLimit: _int(json['searchResultLimit'], d.searchResultLimit),
      onboardingComplete:
          _bool(json['onboardingComplete'], d.onboardingComplete),
    );
  }

  /// Folders that are noise in almost every project. Editable in settings.
  static const List<String> defaultExcludes = <String>[
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
  ];

  final EditorSettings editor;
  final AppThemeVariant themeVariant;

  /// Editor theme used when the app chrome is dark.
  final String editorThemeId;

  /// Editor theme used when the app chrome is light.
  final String lightEditorThemeId;

  /// Null means "use the theme's own accent".
  final int? accentColorValue;

  final bool showHiddenFiles;
  final ExplorerSortOrder sortOrder;
  final bool showFileExtensions;
  final List<String> excludePatterns;
  final bool closeExplorerAfterOpen;
  final bool showAccessoryBar;

  /// The accessory bar's key layout, as tokens (see [AccessoryKeyLayouts]).
  /// Empty means "use the standard layout", so a fresh install carries no
  /// duplicate of the default that would then drift from it.
  final List<String> accessoryKeyTokens;
  final bool restoreSession;
  final bool confirmDelete;
  final bool confirmCloseUnsaved;
  final int warnFileSizeBytes;
  final int readOnlyFileSizeBytes;
  final int searchResultLimit;

  /// Set once the user finishes or skips onboarding.
  final bool onboardingComplete;

  AppSettings copyWith({
    EditorSettings? editor,
    AppThemeVariant? themeVariant,
    String? editorThemeId,
    String? lightEditorThemeId,
    int? accentColorValue,
    bool clearAccentColor = false,
    bool? showHiddenFiles,
    ExplorerSortOrder? sortOrder,
    bool? showFileExtensions,
    List<String>? excludePatterns,
    bool? closeExplorerAfterOpen,
    bool? showAccessoryBar,
    List<String>? accessoryKeyTokens,
    bool? restoreSession,
    bool? confirmDelete,
    bool? confirmCloseUnsaved,
    int? warnFileSizeBytes,
    int? readOnlyFileSizeBytes,
    int? searchResultLimit,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      editor: editor ?? this.editor,
      themeVariant: themeVariant ?? this.themeVariant,
      editorThemeId: editorThemeId ?? this.editorThemeId,
      lightEditorThemeId: lightEditorThemeId ?? this.lightEditorThemeId,
      accentColorValue:
          clearAccentColor ? null : (accentColorValue ?? this.accentColorValue),
      showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
      sortOrder: sortOrder ?? this.sortOrder,
      showFileExtensions: showFileExtensions ?? this.showFileExtensions,
      excludePatterns: excludePatterns ?? this.excludePatterns,
      closeExplorerAfterOpen:
          closeExplorerAfterOpen ?? this.closeExplorerAfterOpen,
      showAccessoryBar: showAccessoryBar ?? this.showAccessoryBar,
      accessoryKeyTokens: accessoryKeyTokens ?? this.accessoryKeyTokens,
      restoreSession: restoreSession ?? this.restoreSession,
      confirmDelete: confirmDelete ?? this.confirmDelete,
      confirmCloseUnsaved: confirmCloseUnsaved ?? this.confirmCloseUnsaved,
      warnFileSizeBytes: warnFileSizeBytes ?? this.warnFileSizeBytes,
      readOnlyFileSizeBytes:
          readOnlyFileSizeBytes ?? this.readOnlyFileSizeBytes,
      searchResultLimit: searchResultLimit ?? this.searchResultLimit,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'editor': editor.toJson(),
        'themeVariant': themeVariant.name,
        'editorThemeId': editorThemeId,
        'lightEditorThemeId': lightEditorThemeId,
        'accentColorValue': accentColorValue,
        'showHiddenFiles': showHiddenFiles,
        'sortOrder': sortOrder.name,
        'showFileExtensions': showFileExtensions,
        'excludePatterns': excludePatterns,
        'closeExplorerAfterOpen': closeExplorerAfterOpen,
        'showAccessoryBar': showAccessoryBar,
        'accessoryKeyTokens': accessoryKeyTokens,
        'restoreSession': restoreSession,
        'confirmDelete': confirmDelete,
        'confirmCloseUnsaved': confirmCloseUnsaved,
        'warnFileSizeBytes': warnFileSizeBytes,
        'readOnlyFileSizeBytes': readOnlyFileSizeBytes,
        'searchResultLimit': searchResultLimit,
        'onboardingComplete': onboardingComplete,
      };

}

// --- Lenient JSON readers ---------------------------------------------------
// Settings files are user-editable and version-skewed. Every reader falls back
// to a default rather than throwing, so a bad value costs one setting, not the
// whole app.

bool _bool(Object? v, bool fallback) => v is bool ? v : fallback;

int _int(Object? v, int fallback) => v is int ? v : fallback;

double _double(Object? v, double fallback) =>
    v is num ? v.toDouble() : fallback;

String _string(Object? v, String fallback) => v is String ? v : fallback;

List<String> _stringList(Object? v, List<String> fallback) =>
    v is List ? v.whereType<String>().toList() : fallback;

T _enum<T extends Enum>(List<T> values, Object? v, T fallback) {
  if (v is String) {
    for (final T value in values) {
      if (value.name == v) {
        return value;
      }
    }
  }
  return fallback;
}
