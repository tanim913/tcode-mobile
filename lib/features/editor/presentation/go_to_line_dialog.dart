/// "Go to line" — ask for a line number, validate it against the buffer.
///
/// Kept out of the shell so the parsing rule has one home and can be unit
/// tested without a dialog: [parseLineInput] is the whole of the logic.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reads a line number from what the user typed.
///
/// Returns null when the input is not a usable line number for a buffer of
/// [lineCount] lines. Accepts surrounding whitespace and a `:` suffix, because
/// people paste `main.dart:42` fragments and `42:` is a reasonable thing to
/// type; anything else is rejected rather than guessed at.
int? parseLineInput(String raw, {required int lineCount}) {
  String text = raw.trim();
  if (text.endsWith(':')) {
    text = text.substring(0, text.length - 1).trim();
  }
  // A column suffix is accepted and ignored: we place the cursor on the line,
  // so silently dropping the column is honest about what this does.
  final int colon = text.indexOf(':');
  if (colon >= 0) {
    text = text.substring(0, colon).trim();
  }
  if (text.isEmpty) {
    return null;
  }
  final int? line = int.tryParse(text);
  if (line == null || line < 1 || line > lineCount) {
    return null;
  }
  return line;
}

/// Shows the dialog and returns the chosen 1-based line, or null if cancelled.
Future<int?> promptForLine(
  BuildContext context, {
  required int lineCount,
  required int currentLine,
}) {
  return showDialog<int>(
    context: context,
    builder: (BuildContext context) => _GoToLineDialog(
      lineCount: lineCount,
      currentLine: currentLine,
    ),
  );
}

class _GoToLineDialog extends StatefulWidget {
  const _GoToLineDialog({required this.lineCount, required this.currentLine});

  final int lineCount;
  final int currentLine;

  @override
  State<_GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<_GoToLineDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final int? line =
        parseLineInput(_controller.text, lineCount: widget.lineCount);
    if (line == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.of(context).pop(line);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to line'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        // Digits and a colon only: the field cannot be put into a state the
        // parser would reject for a reason the user cannot see.
        inputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        ],
        textInputAction: TextInputAction.go,
        onChanged: (_) {
          if (_invalid) {
            setState(() => _invalid = false);
          }
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Line number',
          // The range is the useful hint, and it doubles as the error text.
          helperText: 'Line ${widget.currentLine} of ${widget.lineCount}',
          errorText: _invalid ? 'Enter a line between 1 and ${widget.lineCount}' : null,
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Go')),
      ],
    );
  }
}
