/// Confirmation for "reset to defaults".
///
/// Settings persist the moment they change and there is no undo stack for
/// them, so resetting a whole group is the one destructive action on this
/// screen and asks first.
library;

import 'package:flutter/material.dart';

/// Returns true when the user confirmed.
Future<bool> confirmGroupReset(BuildContext context, String groupTitle) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('Reset ${groupTitle.toLowerCase()} settings?'),
      content: Text(
        'Every setting under $groupTitle goes back to its default. '
        'Your other settings are left alone, and this cannot be undone.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Reset'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
