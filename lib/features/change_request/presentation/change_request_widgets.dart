/// The pieces of the pull request screen: changed-file rows, the progress
/// view and the result.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/services/git_host/change_set.dart';
import 'package:pocket_code/services/git_host/git_host_client.dart';
import 'package:pocket_code/services/share/share_factory.dart';

/// One changed file: a tick to include it, its A/M/D badge, and a tap target
/// that opens the diff.
class ChangeRow extends StatelessWidget {
  const ChangeRow({
    required this.change,
    required this.included,
    required this.onToggle,
    required this.onOpen,
    super.key,
  });

  final FileChange change;
  final bool included;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final Color badge = switch (change.kind) {
      ChangeKind.added => tokens.success,
      ChangeKind.modified => tokens.warning,
      ChangeKind.deleted => tokens.danger,
    };
    final int slash = change.path.lastIndexOf('/');
    final String name =
        slash < 0 ? change.path : change.path.substring(slash + 1);
    final String folder = slash < 0 ? '' : change.path.substring(0, slash);

    return InkWell(
      onTap: onOpen,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: AppSizes.primaryTouchTarget),
        child: Row(
          children: <Widget>[
            Checkbox(
              value: included,
              onChanged: (bool? value) => onToggle(value ?? false),
            ),
            Semantics(
              label: change.kind.label,
              container: true,
              excludeSemantics: true,
              child: SizedBox(
                width: 22,
                child: Text(
                  change.kind.letter,
                  style: TextStyle(color: badge, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(name, overflow: TextOverflow.ellipsis),
                  if (folder.isNotEmpty)
                    Text(
                      folder,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: tokens.textMuted),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

/// A centred message with an optional action, for every state that is not
/// the form.
class ChangeRequestMessage extends StatelessWidget {
  const ChangeRequestMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 36, color: tokens.textMuted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textMuted),
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Which step of the submit is running.
class SubmitProgressView extends StatelessWidget {
  const SubmitProgressView({required this.progress, super.key});

  final SubmitProgress? progress;

  @override
  Widget build(BuildContext context) {
    final SubmitProgress? p = progress;
    final String label = p == null
        ? 'Starting…'
        : p.stage == SubmitStage.uploading && p.total > 0
            ? '${p.stage.label}… ${p.done} of ${p.total}'
            : '${p.stage.label}…';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

/// The request was opened: its address, with copy and share.
class ChangeRequestDone extends StatelessWidget {
  const ChangeRequestDone({
    required this.result,
    required this.noun,
    super.key,
  });

  final ChangeRequestResult result;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final TextStyle? muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: tokens.textMuted);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.check_circle, size: 40, color: tokens.success),
            const SizedBox(height: 12),
            Text(
              '${noun[0].toUpperCase()}${noun.substring(1)} opened',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            SelectableText(
              result.url,
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.accent),
            ),
            const SizedBox(height: 8),
            Text(
              'Branch "${result.branch}"'
              '${result.viaFork ? ', on your fork — you cannot push to this '
                  'repository directly' : ''}.\n'
              'The files in this folder are unchanged. Merging happens on the '
              'website.',
              textAlign: TextAlign.center,
              style: muted,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              children: <Widget>[
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy link'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: result.url));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied')),
                      );
                    }
                  },
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: const Text('Share'),
                  onPressed: () =>
                      createShareService().shareText(result.url, subject: noun),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
