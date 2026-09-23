/// Managing the snippet library, reached from Settings › Editor.
///
/// A full screen rather than an inline list: a snippet has a multi-line body,
/// which a settings row cannot show. The settings entry stays a searchable row
/// that summarises and pushes here, following the `customEntry` pattern.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/snippet.dart';
import 'package:pocket_code/data/repositories/snippets_repository.dart';
import 'package:pocket_code/features/snippets/application/snippets_controller.dart';
import 'package:pocket_code/features/snippets/presentation/snippet_dialog.dart';

/// The row shown in the settings list.
class SnippetsSummary extends ConsumerWidget {
  const SnippetsSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Snippet> snippets = ref.watch(snippetsProvider);
    final bool available =
        ref.watch<SnippetsRepository?>(snippetsRepositoryProvider) != null;
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    if (!available) {
      return Text(
        'Snippets need app storage, which is not available on this device.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: tokens.textMuted),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: const Icon(Icons.short_text, size: 16),
        label: Text(
          snippets.isEmpty
              ? 'Add a snippet'
              : '${snippets.length} snippet${snippets.length == 1 ? '' : 's'}',
        ),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) => const SnippetsScreen(),
          ),
        ),
      ),
    );
  }
}

class SnippetsScreen extends ConsumerWidget {
  const SnippetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Snippet> snippets = ref.watch(snippetsProvider);
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Scaffold(
      backgroundColor: tokens.background,
      appBar: AppBar(title: const Text('Snippets')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: snippets.isEmpty
          ? _Empty(tokens: tokens)
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: snippets.length,
              itemBuilder: (BuildContext context, int i) => _Row(
                snippet: snippets[i],
                tokens: tokens,
                onEdit: () => _edit(context, ref, snippets[i]),
                onDelete: () => ref
                    .read(snippetsProvider.notifier)
                    .remove(snippets[i].id),
              ),
            ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Snippet? existing,
  ) async {
    final Snippet? result = await showSnippetDialog(
      context,
      existing: existing,
      others: ref.read(snippetsProvider),
    );
    if (result == null) {
      return;
    }
    final SnippetsController controller = ref.read(snippetsProvider.notifier);
    if (existing == null) {
      await controller.add(
        prefix: result.prefix,
        body: result.body,
        description: result.description,
        languageIds: result.languageIds,
      );
    } else {
      await controller.update(result);
    }
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tokens});

  final AppColorTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.short_text, size: 34, color: tokens.textMuted),
            const SizedBox(height: 12),
            Text(
              'No snippets yet',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            // No hidden starter set: an empty library is empty, and anything
            // the app added quietly would be something the user could not find
            // to change.
            Text(
              'A snippet is a piece of text you insert by name. Add one, then '
              'reach it from the command palette or while typing.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.snippet,
    required this.tokens,
    required this.onEdit,
    required this.onDelete,
  });

  final Snippet snippet;
  final AppColorTokens tokens;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String languages = snippet.appliesToAll
        ? 'All languages'
        : snippet.languageIds.join(', ');

    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${snippet.prefix}, $languages',
      child: InkWell(
        onTap: onEdit,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        snippet.prefix,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet.description.isEmpty
                            ? languages
                            : '${snippet.description} · $languages',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.delete_outline, size: 18, color: tokens.danger),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
