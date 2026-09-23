/// Delete confirmation.
///
/// The file count in the message is the whole point of the dialog: "Delete
/// screens?" is a shrug, "Delete screens? This folder contains 8 files." is a
/// decision. Counting is recursive and runs off the UI isolate in the provider,
/// so the dialog opens immediately and fills the detail line in when it arrives.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Returns true when the user confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String headline,
  required Future<String?> details,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) =>
        _DeleteDialog(headline: headline, details: details),
  );
  return confirmed ?? false;
}

class _DeleteDialog extends StatelessWidget {
  const _DeleteDialog({required this.headline, required this.details});

  final String headline;
  final Future<String?> details;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return AlertDialog(
      title: Text(headline),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FutureBuilder<String?>(
            future: details,
            builder: (
              BuildContext context,
              AsyncSnapshot<String?> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text(
                  'Counting contents…',
                  style: Theme.of(context).textTheme.bodyMedium,
                );
              }
              final String? text = snapshot.data;
              if (text == null || text.isEmpty) {
                return const SizedBox.shrink();
              }
              return Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium,
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.undo, size: 14, color: tokens.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'You can undo this for a few seconds afterwards.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: tokens.danger),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
