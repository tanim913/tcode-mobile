/// The "recently opened" section of the welcome screen.
///
/// Availability is checked lazily, when the list is shown: a folder can vanish
/// between sessions — a removed card, a revoked SAF grant — and an entry that
/// can no longer be opened is shown disabled with Remove rather than failing
/// when it is tapped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/workspace.dart';
import 'package:pocket_code/data/repositories/recents_repository.dart';
import 'package:pocket_code/features/workspace/application/recents_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';
import 'package:pocket_code/services/filesystem/root_resolver.dart';

/// How long ago, in words. Deliberately coarse: to the minute is noise here.
String relativeTime(DateTime then, {DateTime? now}) {
  final Duration gap = (now ?? DateTime.now()).difference(then);
  if (gap.inMinutes < 1) {
    return 'just now';
  }
  if (gap.inHours < 1) {
    return '${gap.inMinutes}m ago';
  }
  if (gap.inDays < 1) {
    return '${gap.inHours}h ago';
  }
  if (gap.inDays < 7) {
    return '${gap.inDays}d ago';
  }
  if (gap.inDays < 365) {
    return '${(gap.inDays / 7).floor()}w ago';
  }
  return '${(gap.inDays / 365).floor()}y ago';
}

class RecentWorkspaceList extends ConsumerStatefulWidget {
  const RecentWorkspaceList({required this.onOpened, super.key});

  /// Called after a workspace is adopted, so the screen can leave.
  final VoidCallback onOpened;

  @override
  ConsumerState<RecentWorkspaceList> createState() =>
      _RecentWorkspaceListState();
}

class _RecentWorkspaceListState extends ConsumerState<RecentWorkspaceList> {
  @override
  void initState() {
    super.initState();
    // After the first frame: this touches storage, and the welcome screen must
    // paint before it waits on anything.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (!mounted) {
      return;
    }
    await ref.read(recentsProvider.notifier).checkAvailability(providerForRoot);
  }

  Future<void> _open(RecentWorkspace entry) async {
    if (entry.roots.isEmpty) {
      return;
    }
    final WorkspaceRoot root = entry.roots.first;
    final FileSystemProvider? provider = await providerForRoot(root);
    if (provider == null || !mounted) {
      return;
    }
    ref.read(workspaceProvider.notifier).openFolder(
          PickedRoot(
            provider: provider,
            rootId: root.rootId,
            displayName: root.name,
          ),
        );
    widget.onOpened();
  }

  @override
  Widget build(BuildContext context) {
    final RecentItems recents = ref.watch(recentsProvider);
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    if (recents.workspaces.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 26),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Recent',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            TextButton(
              onPressed: () => ref.read(recentsProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
          ],
        ),
        for (final RecentWorkspace entry in recents.workspaces.take(6))
          _RecentRow(
            entry: entry,
            tokens: tokens,
            onOpen: entry.available ? () => _open(entry) : null,
            onRemove: () =>
                ref.read(recentsProvider.notifier).removeWorkspace(entry.key),
          ),
      ],
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.entry,
    required this.tokens,
    required this.onOpen,
    required this.onRemove,
  });

  final RecentWorkspace entry;
  final AppColorTokens tokens;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final String subtitle = entry.available
        ? relativeTime(entry.lastOpened)
        : 'Not available now';

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: onOpen != null,
      enabled: onOpen != null,
      label: '${entry.name}, $subtitle',
      child: InkWell(
        onTap: onOpen,
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppSizes.primaryTouchTarget),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
            child: Row(
              children: <Widget>[
                Icon(
                  entry.available
                      ? Icons.folder_outlined
                      : Icons.folder_off_outlined,
                  size: 18,
                  color: entry.available ? tokens.accent : tokens.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: entry.available
                                  ? tokens.textPrimary
                                  : tokens.textMuted,
                            ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove from recent',
                  icon: Icon(Icons.close, size: 16, color: tokens.textMuted),
                  onPressed: onRemove,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
