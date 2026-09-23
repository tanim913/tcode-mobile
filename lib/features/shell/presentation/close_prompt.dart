/// Dialogs asking what to do about unsaved changes.
///
/// Kept apart from the shell so the wording lives in one place: the same three
/// choices are offered when closing a tab, closing a workspace, and quitting.
library;

import 'package:flutter/material.dart';

enum CloseChoice { cancel, discard, save }

/// "Save changes to main.dart?" — Cancel, Don't save, Save.
///
/// Cancel is the default (returned if the dialog is dismissed), because losing
/// work must never be the accidental outcome.
Future<CloseChoice> promptToClose(BuildContext context, String fileName) async {
  final CloseChoice? choice = await showDialog<CloseChoice>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text('Save changes to $fileName?'),
      content: const Text(
        'If you do not save, your changes to this file will be lost.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.discard),
          child: const Text("Don't save"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.save),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  return choice ?? CloseChoice.cancel;
}

Future<CloseChoice> promptToCloseWorkspace(BuildContext context) async {
  final CloseChoice? choice = await showDialog<CloseChoice>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('Save your changes before closing?'),
      content: const Text(
        'Some open files have unsaved changes. If you do not save them, '
        'those changes will be lost.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.discard),
          child: const Text("Don't save"),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(CloseChoice.save),
          child: const Text('Save all'),
        ),
      ],
    ),
  );
  return choice ?? CloseChoice.cancel;
}
