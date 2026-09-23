/// An open editor tab and the per-tab state that must survive being closed and
/// reopened, or the app being killed.
library;

import 'package:flutter/foundation.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/services/language/language_definition.dart';

/// Cursor, selection and scroll for one tab.
///
/// Persisted, so reopening a file puts the user back exactly where they were
/// rather than at the top of the file.
@immutable
class EditorState {
  const EditorState({
    this.baseLine = 0,
    this.baseOffset = 0,
    this.extentLine = 0,
    this.extentOffset = 0,
    this.scrollOffset = 0,
    this.horizontalScrollOffset = 0,
  });

  /// Selection anchor.
  final int baseLine;
  final int baseOffset;

  /// Selection head — where the cursor actually is.
  final int extentLine;
  final int extentOffset;

  final double scrollOffset;
  final double horizontalScrollOffset;

  bool get isCollapsed =>
      baseLine == extentLine && baseOffset == extentOffset;

  Map<String, Object?> toJson() => <String, Object?>{
        'baseLine': baseLine,
        'baseOffset': baseOffset,
        'extentLine': extentLine,
        'extentOffset': extentOffset,
        'scrollOffset': scrollOffset,
        'hScrollOffset': horizontalScrollOffset,
      };

  factory EditorState.fromJson(Map<String, Object?> json) => EditorState(
        baseLine: _int(json['baseLine']),
        baseOffset: _int(json['baseOffset']),
        extentLine: _int(json['extentLine']),
        extentOffset: _int(json['extentOffset']),
        scrollOffset: _double(json['scrollOffset']),
        horizontalScrollOffset: _double(json['hScrollOffset']),
      );

  static int _int(Object? v) => v is int ? v : 0;

  static double _double(Object? v) => v is num ? v.toDouble() : 0;
}

/// Why a file opened in a restricted mode, so the UI can explain itself
/// instead of silently behaving differently.
enum DocumentRestriction {
  none,

  /// Over the read-only threshold: opened, but highlighting off and no editing.
  tooLargeToEdit,

  /// A line long enough to make highlighting stall the frame.
  longLines,

  /// Null bytes in the first 8 KB.
  binary,

  /// An image, shown in the image viewer rather than the text editor.
  image,
}

@immutable
class OpenTab {
  const OpenTab({
    required this.node,
    required this.rootIndex,
    required this.text,
    required this.savedText,
    required this.format,
    required this.language,
    required this.indent,
    this.editorState = const EditorState(),
    this.isPreview = false,
    this.restriction = DocumentRestriction.none,
    this.notice,
    this.externallyChanged = false,
  });

  final FileNode node;
  final int rootIndex;

  /// Current buffer, always with `\n` line endings. [format] records what was
  /// on disk so a save reproduces it exactly.
  final String text;

  /// What was last written to (or read from) disk.
  ///
  /// Dirtiness is derived by comparing against this rather than tracked as a
  /// flag, so typing a character and then undoing it correctly leaves the tab
  /// clean — a flag would leave it falsely dirty.
  final String savedText;

  final TextFormat format;
  final LanguageDefinition language;
  final IndentStyle indent;
  final EditorState editorState;

  /// A preview tab shows its name in italics and is replaced by the next file
  /// opened, unless it has been edited or explicitly pinned. Matches VS Code.
  final bool isPreview;

  final DocumentRestriction restriction;

  /// A non-fatal explanation, e.g. "opened read-only because it is 12 MB".
  final String? notice;

  /// Set when the file changed on disk while this tab was dirty. The UI shows
  /// a Reload / Keep my changes banner rather than silently picking one.
  final bool externallyChanged;

  /// Stable identity across a workspace: the same file in two roots is two
  /// different tabs.
  String get key => '$rootIndex:${node.id}';

  bool get isDirty => text != savedText;

  bool get isReadOnly =>
      restriction == DocumentRestriction.tooLargeToEdit ||
      restriction == DocumentRestriction.binary ||
      restriction == DocumentRestriction.image;

  /// Highlighting is off whenever it would be slow or meaningless.
  bool get highlightingEnabled =>
      restriction == DocumentRestriction.none && language.hasHighlighting;

  OpenTab copyWith({
    FileNode? node,
    String? text,
    String? savedText,
    TextFormat? format,
    EditorState? editorState,
    bool? isPreview,
    String? notice,
    bool clearNotice = false,
    bool? externallyChanged,
  }) {
    return OpenTab(
      node: node ?? this.node,
      rootIndex: rootIndex,
      text: text ?? this.text,
      savedText: savedText ?? this.savedText,
      format: format ?? this.format,
      language: language,
      indent: indent,
      editorState: editorState ?? this.editorState,
      isPreview: isPreview ?? this.isPreview,
      restriction: restriction,
      notice: clearNotice ? null : (notice ?? this.notice),
      externallyChanged: externallyChanged ?? this.externallyChanged,
    );
  }

  /// Session record. The buffer text is deliberately NOT stored here — only
  /// unsaved buffers are backed up, and those go to separate hot-exit files so
  /// the session index stays small and quick to write on every change.
  Map<String, Object?> toJson() => <String, Object?>{
        'rootIndex': rootIndex,
        'fileId': node.id,
        'name': node.name,
        'displayPath': node.displayPath,
        'isPreview': isPreview,
        'isDirty': isDirty,
        'editorState': editorState.toJson(),
      };
}

/// A tab that was closed, kept so "Reopen closed tab" can restore it with its
/// cursor and scroll position intact.
@immutable
class ClosedTab {
  const ClosedTab({
    required this.fileId,
    required this.rootIndex,
    required this.name,
    required this.editorState,
  });

  final String fileId;
  final int rootIndex;
  final String name;
  final EditorState editorState;
}
