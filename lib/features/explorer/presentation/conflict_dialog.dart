/// The "that name is taken" question, asked once per colliding item.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/features/explorer/application/file_operations.dart';

/// Returns the user's decision, or null if they dismissed the dialog — which
/// [FileOperations.transfer] reads as "stop the whole operation".
Future<ConflictDecision?> showConflictDialog(
  BuildContext context,
  ConflictRequest request,
) {
  return showDialog<ConflictDecision>(
    context: context,
    builder: (BuildContext context) => _ConflictDialog(request: request),
  );
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({required this.request});

  final ConflictRequest request;

  @override
  State<_ConflictDialog> createState() => _ConflictDialogState();
}

class _ConflictDialogState extends State<_ConflictDialog> {
  bool _applyToAll = false;

  void _choose(ConflictChoice choice) {
    Navigator.of(context).pop(
      ConflictDecision(choice, applyToAll: _applyToAll),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String kind = widget.request.isFolder ? 'Folder' : 'File';
    return AlertDialog(
      title: Text('$kind "${widget.request.name}" already exists'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Replace it, keep both by adding "copy" to the name, or skip this '
            'item. Replacing moves the existing item to the trash first, so it '
            'can be undone.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (widget.request.offerApplyToAll)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: CheckboxListTile(
                value: _applyToAll,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Apply to all'),
                onChanged: (bool? value) =>
                    setState(() => _applyToAll = value ?? false),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => _choose(ConflictChoice.skip),
          child: const Text('Skip'),
        ),
        TextButton(
          onPressed: () => _choose(ConflictChoice.keepBoth),
          child: const Text('Keep Both'),
        ),
        FilledButton(
          onPressed: () => _choose(ConflictChoice.replace),
          child: const Text('Replace'),
        ),
      ],
    );
  }
}
