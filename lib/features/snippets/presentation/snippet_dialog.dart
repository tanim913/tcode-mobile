/// Add or edit one snippet.
///
/// Validation lives in `validateSnippet`, a free function in the model, so the
/// rule is testable without pumping a widget — the same split
/// `validateExcludePattern` uses.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/services/language/language_definition.dart';
import 'package:pocket_code/services/language/language_registry.dart';

/// Shows the editor. Returns the snippet to save, or null if cancelled.
Future<Snippet?> showSnippetDialog(
  BuildContext context, {
  required Snippet? existing,
  required List<Snippet> others,
}) {
  return showDialog<Snippet>(
    context: context,
    builder: (BuildContext context) =>
        _SnippetDialog(existing: existing, others: others),
  );
}

class _SnippetDialog extends StatefulWidget {
  const _SnippetDialog({required this.existing, required this.others});

  final Snippet? existing;
  final List<Snippet> others;

  @override
  State<_SnippetDialog> createState() => _SnippetDialogState();
}

class _SnippetDialogState extends State<_SnippetDialog> {
  late final TextEditingController _prefix =
      TextEditingController(text: widget.existing?.prefix ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.existing?.body ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existing?.description ?? '');
  late List<String> _languages =
      widget.existing?.languageIds ?? const <String>[kAnyLanguage];

  String? _error;

  @override
  void dispose() {
    _prefix.dispose();
    _body.dispose();
    _description.dispose();
    super.dispose();
  }

  Snippet get _candidate => Snippet(
        id: widget.existing?.id ?? 'draft',
        prefix: _prefix.text.trim(),
        body: _body.text,
        description: _description.text.trim(),
        languageIds: _languages,
      );

  void _save() {
    final Snippet candidate = _candidate;
    final String? problem = validateSnippet(candidate, widget.others);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.of(context).pop(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return AlertDialog(
      title: Text(widget.existing == null ? 'New snippet' : 'Edit snippet'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _prefix,
              decoration: const InputDecoration(
                labelText: 'Name',
                helperText: 'What you type to reach it',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'JetBrains Mono'),
              decoration: const InputDecoration(
                labelText: 'Text to insert',
                helperText: r'Put $0 where the cursor should end up',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            Text('Languages', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            _LanguagePicker(
              selected: _languages,
              onChanged: (List<String> next) =>
                  setState(() => _languages = next),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.danger),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.selected, required this.onChanged});

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final bool all = selected.contains(kAnyLanguage);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        ChoiceChip(
          label: const Text('All languages'),
          selected: all,
          onSelected: (_) => onChanged(const <String>[kAnyLanguage]),
        ),
        for (final LanguageDefinition language in LanguageRegistry.all)
          if (language.id != LanguageRegistry.plainText.id)
            FilterChip(
              label: Text(language.label),
              selected: !all && selected.contains(language.id),
              onSelected: (bool on) {
                final List<String> next = all
                    ? <String>[]
                    : selected.where((String id) => id != kAnyLanguage).toList();
                if (on) {
                  next.add(language.id);
                } else {
                  next.remove(language.id);
                }
                onChanged(next.isEmpty ? const <String>[kAnyLanguage] : next);
              },
            ),
      ],
    );
  }
}
