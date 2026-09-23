/// The editing actions the toolbars, accessory bar and keyboard shortcuts all
/// invoke.
///
/// One implementation, three callers: that is what guarantees "toggle comment"
/// behaves identically whether it came from the bottom toolbar, a hardware
/// Ctrl+/, or the command palette later.
///
/// Everything goes through [CodeLineEditingController]. Nothing here synthesises
/// a platform key event — the brief requires that, and it is also the only way
/// these keys can coexist with an arbitrary soft keyboard's autocorrect.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/data/models/accessory_key.dart';
import 'package:pocket_code/data/models/document_symbol.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/services/language/bracket_matcher.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:re_editor/re_editor.dart';

class EditorActions {
  const EditorActions(this.controller);

  final CodeLineEditingController controller;

  // --- Insertion ------------------------------------------------------------

  /// Inserts [text] at the cursor, replacing any selection.
  ///
  /// Deliberately the same path a typed character takes, so undo history,
  /// auto-closing pairs and the dirty flag all behave identically.
  void insert(String text) => controller.replaceSelection(text);

  /// Inserts [snippet], re-indented to the current line and with the caret
  /// placed at its `$0` marker.
  ///
  /// Goes through [insert], so undo, dirtiness and auto-closing pairs behave
  /// exactly as they do for typed text.
  void insertSnippet(Snippet snippet) {
    final CodeLineSelection selection = controller.selection;
    final int line = selection.extentIndex.clamp(0, controller.lineCount - 1);
    final String lineText = controller.codeLines[line].text;
    final String indent =
        lineText.substring(0, lineText.length - lineText.trimLeft().length);

    final ExpandedSnippet expanded =
        expandSnippet(snippet.body, lineIndent: indent);
    final int startLine = selection.startIndex;
    insert(expanded.text);

    // `replaceSelection` leaves the caret at the end of what it inserted; the
    // marker, if there was one, is usually somewhere before that.
    final int targetLine =
        (startLine + expanded.lineOffset).clamp(0, controller.lineCount - 1);
    final int lineLength = controller.codeLines[targetLine].text.length;
    controller.selection = CodeLineSelection.collapsed(
      index: targetLine,
      offset: expanded.column.clamp(0, lineLength),
    );
    controller.makeCursorCenterIfInvisible();
  }

  /// Replaces the whole buffer, in one undoable step.
  ///
  /// Used by "restore this version": going through the buffer rather than
  /// writing the file directly means the restore itself can be undone, which
  /// is what makes trying one safe.
  void replaceAll(String text) {
    controller.selectAll();
    controller.replaceSelection(text);
  }

  void indent() => controller.applyIndent();

  void outdent() => controller.applyOutdent();

  void newLine() => controller.applyNewLine();

  void backspace() => controller.deleteBackward();

  // --- Navigation -----------------------------------------------------------

  /// Moves the cursor, or extends the selection when [extend] is set — which is
  /// how the accessory bar's sticky Shift works.
  void move(AxisDirection direction, {required bool extend}) {
    if (extend) {
      controller.extendSelection(direction);
    } else {
      controller.moveCursor(direction);
    }
  }

  /// Nudges the cursor horizontally by [steps] characters.
  ///
  /// Used by the drag-along-the-accessory-bar gesture, which is the only
  /// precise way to place a cursor in code on a touch screen.
  void nudge(int steps, {required bool extend}) {
    final AxisDirection direction =
        steps < 0 ? AxisDirection.left : AxisDirection.right;
    for (int i = 0; i < steps.abs(); i++) {
      move(direction, extend: extend);
    }
  }

  /// How many lines the buffer has. 1-based line numbers run up to this.
  int get lineCount => controller.lineCount;

  /// Puts the cursor at the start of [line] (1-based) and scrolls it into view.
  ///
  /// Returns false when the line is out of range, so the caller can say so
  /// rather than silently jumping somewhere the user did not ask for.
  bool goToLine(int line) {
    final int index = line - 1;
    if (index < 0 || index >= controller.lineCount) {
      return false;
    }
    controller.selection = CodeLineSelection.collapsed(index: index, offset: 0);
    // Centre rather than merely reveal: a line scrolled to the very bottom edge
    // is technically visible and practically useless.
    controller.makeCursorCenterIfInvisible();
    return true;
  }

  /// Moves the cursor to the bracket matching the one at the cursor.
  ///
  /// Returns false when the cursor is not on a bracket, or the bracket has no
  /// partner, so the caller can say so rather than moving the cursor somewhere
  /// the user did not ask for.
  ///
  /// [lineComment] comes from the file's language, so a bracket inside a
  /// comment is not mistaken for code.
  bool jumpToMatchingBracket({String? lineComment}) {
    final CodeLineSelection selection = controller.selection;
    final BracketMatch? found = matchingBracket(
      lineCount: controller.lineCount,
      lineAt: (int i) => controller.codeLines[i].text,
      line: selection.extentIndex,
      offset: selection.extentOffset,
      lineComment: lineComment,
    );
    if (found == null) {
      return false;
    }
    controller.selection = CodeLineSelection.collapsed(
      index: found.line,
      offset: found.offset,
    );
    controller.makeCursorCenterIfInvisible();
    return true;
  }

  /// Jumps to a symbol from the outline, landing on the identifier itself.
  ///
  /// The column matters: dropping the caret at the start of the line would put
  /// it before the indentation, so "go to this function" would not actually
  /// leave you on the name you tapped.
  bool goToSymbol(DocumentSymbol symbol) {
    final int index = symbol.line - 1;
    if (index < 0 || index >= controller.lineCount) {
      return false;
    }
    final int lineLength = controller.codeLines[index].length;
    controller.selection = CodeLineSelection.collapsed(
      index: index,
      offset: (symbol.column - 1).clamp(0, lineLength),
    );
    controller.makeCursorCenterIfInvisible();
    return true;
  }

  // --- History --------------------------------------------------------------

  bool get canUndo => controller.canUndo;

  bool get canRedo => controller.canRedo;

  void undo() => controller.undo();

  void redo() => controller.redo();

  // --- Comments -------------------------------------------------------------

  /// Whether [language] has comment syntax at all.
  ///
  /// JSON does not, so the action is disabled rather than hidden — a button
  /// that vanishes between files is more confusing than one that greys out.
  static bool canComment(LanguageDefinition language) =>
      language.lineComment != null || language.blockComment != null;

  /// Toggles a comment over the selection, or the current line if there is none.
  ///
  /// [single] picks line comments over block comments where a language has
  /// both. Returns false when the language has no comment syntax.
  bool toggleComment(OpenTab tab, {bool single = true}) {
    final LanguageDefinition language = tab.language;
    if (!canComment(language)) {
      return false;
    }
    final (String, String)? block = language.blockComment;
    final CodeCommentFormatter formatter = DefaultCodeCommentFormatter(
      singleLinePrefix: language.lineComment,
      multiLinePrefix: block?.$1,
      multiLineSuffix: block?.$2,
    );
    // A language with only block comments (HTML) must use them even when the
    // caller asked for a single-line toggle.
    final bool useSingle = single && language.lineComment != null;
    controller.value = formatter.format(
      controller.value,
      tab.indent.unit,
      useSingle,
    );
    return true;
  }

  // --- Accessory bar dispatch ----------------------------------------------

  /// Applies one accessory-bar key press.
  ///
  /// [shiftHeld] is the sticky modifier state, owned by the bar.
  void applyKey(AccessoryKey key, {required bool shiftHeld}) {
    switch (key.kind) {
      case AccessoryKeyKind.insert:
        final String? text = key.text;
        if (text != null && text.isNotEmpty) {
          insert(text);
        }
      case AccessoryKeyKind.tab:
        // Shift+Tab outdents, matching every other editor.
        if (shiftHeld) {
          outdent();
        } else {
          indent();
        }
      case AccessoryKeyKind.shift:
        // Handled by the bar itself, which owns the modifier state.
        break;
      case AccessoryKeyKind.arrowLeft:
        move(AxisDirection.left, extend: shiftHeld);
      case AccessoryKeyKind.arrowRight:
        move(AxisDirection.right, extend: shiftHeld);
      case AccessoryKeyKind.arrowUp:
        move(AxisDirection.up, extend: shiftHeld);
      case AccessoryKeyKind.arrowDown:
        move(AxisDirection.down, extend: shiftHeld);
    }
  }
}
