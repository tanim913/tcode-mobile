/// Prompt for a file or folder name, with validation shown under the field.
///
/// Validation happens as the user types rather than on submit, so an illegal
/// name is caught before they commit to it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Characters that are illegal in a file name on at least one supported
/// platform. Being strict everywhere keeps a project portable.
const String _illegalCharacters = r'/\:*?"<>|';

/// Returns the entered name, or null if the user cancelled.
Future<String?> promptForName(
  BuildContext context, {
  required String title,
  required String label,
  String initialValue = '',
  Set<String> existingNames = const <String>{},
  bool selectBaseNameOnly = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => _NameDialog(
      title: title,
      label: label,
      initialValue: initialValue,
      existingNames: existingNames,
      selectBaseNameOnly: selectBaseNameOnly,
    ),
  );
}

/// Shared validation, exposed so tests can cover it without a widget.
String? validateName(String name, Set<String> existingNames) {
  final String trimmed = name.trim();
  if (trimmed.isEmpty) {
    return 'Enter a name.';
  }
  if (trimmed == '.' || trimmed == '..') {
    return 'That name is reserved.';
  }
  for (final int unit in trimmed.codeUnits) {
    if (unit < 0x20) {
      return 'Names cannot contain control characters.';
    }
  }
  for (int i = 0; i < _illegalCharacters.length; i++) {
    if (trimmed.contains(_illegalCharacters[i])) {
      return 'Names cannot contain ${_illegalCharacters[i]}';
    }
  }
  if (trimmed.endsWith('.') || trimmed.endsWith(' ')) {
    return 'Names cannot end with a dot or a space.';
  }
  if (existingNames.contains(trimmed)) {
    return 'An item with that name already exists here.';
  }
  return null;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.existingNames,
    required this.selectBaseNameOnly,
  });

  final String title;
  final String label;
  final String initialValue;
  final Set<String> existingNames;
  final bool selectBaseNameOnly;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _field =
      TextEditingController(text: widget.initialValue);
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.selectBaseNameOnly) {
      // Renaming main.dart should preselect "main", not ".dart" — the
      // extension is almost never the part being changed.
      final int dot = widget.initialValue.lastIndexOf('.');
      final int end = dot > 0 ? dot : widget.initialValue.length;
      _field.selection = TextSelection(baseOffset: 0, extentOffset: end);
    } else {
      _field.selection =
          TextSelection(baseOffset: 0, extentOffset: widget.initialValue.length);
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _field.text.trim();
    final String? problem = validateName(value, widget.existingNames);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TextField(
            controller: _field,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _error,
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (String value) {
              final String? problem =
                  validateName(value.trim(), widget.existingNames);
              if (problem != _error) {
                setState(() => _error = problem);
              }
            },
            inputFormatters: <TextInputFormatter>[
              // Block path separators outright: a name is never a path.
              FilteringTextInputFormatter.deny(RegExp(r'[/\\]')),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _error == null ? _submit : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
