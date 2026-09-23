/// The settings screen: grouped, searchable, and saved as you go.
///
/// There is no Save button. Every control writes through `settingsProvider`,
/// which persists immediately, so a change survives the app being killed one
/// second later. That is also why the only confirmation on this screen is for
/// "reset to defaults" — it is the one action that cannot be undone by simply
/// flipping the control back.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/sections/accounts_section.dart';
import 'package:pocket_code/features/settings/presentation/sections/appearance_section.dart';
import 'package:pocket_code/features/settings/presentation/sections/editor_section.dart';
import 'package:pocket_code/features/settings/presentation/sections/explorer_section.dart';
import 'package:pocket_code/features/settings/presentation/sections/general_sections.dart';
import 'package:pocket_code/features/settings/presentation/widgets/reset_confirmation.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reset(SettingsGroup group) async {
    if (await confirmGroupReset(context, group.title)) {
      await group.onReset();
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(settingsProvider);
    final List<SettingsGroup> groups = <SettingsGroup>[
      buildEditorGroup(ref, settings.editor),
      buildAppearanceGroup(ref, settings),
      buildExplorerGroup(ref, settings),
      buildKeyboardGroup(ref, settings),
      buildBehaviourGroup(ref, settings),
      buildPerformanceGroup(ref, settings),
      if (ref.watch(credentialsRepositoryProvider) != null)
        buildAccountsGroup(ref),
    ];
    final List<SettingsGroup> visible = filterSettings(groups, _query);
    final bool searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: <Widget>[
          _SearchField(
            controller: _search,
            onChanged: (String value) => setState(() => _query = value),
          ),
          if (searching)
            _ResultSummary(count: countSettings(visible), query: _query.trim()),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? _NoResults(query: _query.trim())
                : _SettingsList(
                    groups: visible,
                    showHeaders: !searching,
                    onReset: _reset,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Flattens the groups into one scrolling list.
///
/// A single [ListView] rather than nested scrollables: only the rows on screen
/// are built, which matters because the editor preview is a real editor.
class _SettingsList extends StatelessWidget {
  const _SettingsList({
    required this.groups,
    required this.showHeaders,
    required this.onReset,
  });

  final List<SettingsGroup> groups;

  /// The editor preview is hidden while searching — a filtered list is a list
  /// of answers, and a preview in the middle of it is noise.
  final bool showHeaders;

  final Future<void> Function(SettingsGroup) onReset;

  @override
  Widget build(BuildContext context) {
    final List<Widget> rows = <Widget>[];
    for (final SettingsGroup group in groups) {
      rows.add(
        _GroupHeader(
          key: ValueKey<String>('group.${group.id}'),
          group: group,
          onReset: () => onReset(group),
        ),
      );
      if (showHeaders && group.header != null) {
        rows.add(group.header!);
      }
      for (final SettingEntry entry in group.entries) {
        rows.add(KeyedSubtree(key: ValueKey<String>(entry.id), child: entry.control));
      }
      rows.add(const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Divider(height: 1),
      ));
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length,
      itemBuilder: (BuildContext context, int index) => rows[index],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.onReset, super.key});

  final SettingsGroup group;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  group.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  group.description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSizes.primaryTouchTarget,
            ),
            child: TextButton(
              onPressed: onReset,
              child: Semantics(
                label: 'Reset ${group.title} settings to defaults',
                child: const ExcludeSemantics(child: Text('Reset')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Semantics(
        textField: true,
        label: 'Search settings',
        hint: 'Matches setting names and their descriptions.',
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search settings',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (BuildContext context, TextEditingValue value, Widget? _) {
                if (value.text.isEmpty) {
                  return const SizedBox.shrink();
                }
                return IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({required this.count, required this.query});

  final int count;
  final String query;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    final String text = count == 1
        ? '1 setting matches "$query"'
        : '$count settings match "$query"';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tokens.textMuted),
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.search_off, size: 32, color: tokens.textMuted),
            const SizedBox(height: 12),
            Text(
              'No settings match "$query"',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a shorter word, or a word from the description — '
              '"wrap", "indent", "theme" and "save" all find something.',
              textAlign: TextAlign.center,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
