/// Editable list of folder and file names the explorer and search skip.
///
/// A chip list rather than a multi-line text field: each pattern is an
/// independent thing to remove, and a text field would make a typo in one line
/// invalidate the rest.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

class ExcludePatternsEditor extends StatelessWidget {
  const ExcludePatternsEditor({
    required this.patterns,
    required this.onChanged,
    super.key,
  });

  final List<String> patterns;
  final ValueChanged<List<String>> onChanged;

  Future<void> _add(BuildContext context) async {
    final String? pattern = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => _AddPatternDialog(existing: patterns),
    );
    if (pattern == null) {
      return;
    }
    onChanged(<String>[...patterns, pattern]);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Excluded patterns',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (patterns.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Nothing is excluded. Every folder will be listed and searched.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.textMuted),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (final String pattern in patterns)
                InputChip(
                  label: Text(pattern),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  deleteIcon: const Icon(Icons.close, size: 16),
                  deleteButtonTooltipMessage: 'Stop excluding $pattern',
                  onDeleted: () => onChanged(
                    patterns.where((String p) => p != pattern).toList(),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('Add pattern'),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onPressed: () => _add(context),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddPatternDialog extends StatefulWidget {
  const _AddPatternDialog({required this.existing});

  final List<String> existing;

  @override
  State<_AddPatternDialog> createState() => _AddPatternDialogState();
}

class _AddPatternDialogState extends State<_AddPatternDialog> {
  final TextEditingController _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    final String value = _field.text.trim();
    final String? error = validateExcludePattern(value, widget.existing);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add an exclude pattern'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _field,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Folder or file name',
              hintText: 'node_modules',
              errorText: _error,
            ),
            onChanged: (String _) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (String _) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Matching entries are hidden in the explorer and skipped by search.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Shared so the rule can be tested without driving the dialog.
String? validateExcludePattern(String pattern, List<String> existing) {
  if (pattern.isEmpty) {
    return 'Enter a folder or file name to exclude.';
  }
  if (pattern.contains('/') || pattern.contains(r'\')) {
    return 'Use a single name, not a path. Separators are not matched.';
  }
  if (existing.contains(pattern)) {
    return 'That pattern is already in the list.';
  }
  return null;
}
