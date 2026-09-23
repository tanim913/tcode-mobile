/// Asks for a repository link and a branch.
///
/// Titled "Download", not "Clone", and says so in the body: what arrives is the
/// files at one branch, with no `.git`, no history and no way to pull. Calling
/// it a clone would set an expectation the app cannot meet.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/services/repo/repo_source.dart';

/// Shows the dialog. Returns the chosen source, or null if cancelled.
Future<RepoSource?> promptForRepo(
  BuildContext context, {
  required bool available,
  required String unavailableReason,
}) {
  return showDialog<RepoSource>(
    context: context,
    builder: (BuildContext context) => _DownloadRepoDialog(
      available: available,
      unavailableReason: unavailableReason,
    ),
  );
}

class _DownloadRepoDialog extends StatefulWidget {
  const _DownloadRepoDialog({
    required this.available,
    required this.unavailableReason,
  });

  final bool available;
  final String unavailableReason;

  @override
  State<_DownloadRepoDialog> createState() => _DownloadRepoDialogState();
}

class _DownloadRepoDialogState extends State<_DownloadRepoDialog> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _branch = TextEditingController(text: 'main');
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _branch.dispose();
    super.dispose();
  }

  void _submit() {
    final Object result =
        parseRepoUrl(_url.text, branch: _branch.text.trim().isEmpty
            ? 'main'
            : _branch.text.trim());
    if (result is RepoUrlError) {
      setState(() => _error = result.message);
      return;
    }
    Navigator.of(context).pop(result as RepoSource);
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    if (!widget.available) {
      return AlertDialog(
        title: const Text('Downloading is not available here'),
        content: Text(widget.unavailableReason),
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Download a repository'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _url,
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Repository link',
              hintText: 'https://github.com/owner/name',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branch,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Branch',
              helperText: 'Often "main" or "master"',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'You get the files at this branch, with no history. For a private '
            'repository, add a token under Settings → Accounts first. With a '
            'token you can later propose your changes back as a pull or merge '
            'request; there is no pull or merge in the app.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.textMuted),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Download')),
      ],
    );
  }
}
