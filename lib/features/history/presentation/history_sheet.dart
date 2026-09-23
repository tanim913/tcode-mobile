/// The list of recorded versions of a file.
///
/// Rows read "Before 14:32" rather than "14:32", and that wording is
/// deliberate: a version is the content that *stopped* being current at that
/// moment, because snapshots are taken before a write rather than after one.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/file_version.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';
import 'package:pocket_code/features/workspace/presentation/recent_list.dart';

/// A size in the shortest form that is still honest.
String formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The time of day, zero-padded.
String clockTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// Shows the versions. Returns the one picked, or null.
Future<FileVersion?> showFileHistory(
  BuildContext context, {
  required String fileName,
  required List<FileVersion> versions,
  required bool available,
}) {
  return showPaletteSheet<FileVersion>(
    context: context,
    builder: (BuildContext context, ScrollController scrollController) =>
        _HistorySheet(
          fileName: fileName,
          versions: versions,
          available: available,
          scrollController: scrollController,
        ),
  );
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({
    required this.fileName,
    required this.versions,
    required this.available,
    required this.scrollController,
  });

  final String fileName;
  final List<FileVersion> versions;
  final bool available;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context)
        .extension<AppColorTokens>()!;

    // The surface is this sheet's own responsibility: `showPaletteSheet` only
    // supplies the modal route, and `PaletteScaffold` — which the other sheets
    // use — is what normally draws the background. Without this the list
    // floated transparently over the editor.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: tokens.borderStrong,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'History of $fileName',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  // The honesty requirement: this is not version control, and
                  // nobody should discover its limits by losing something.
                  'Copies kept by this app each time the file was saved. Not '
                  'version control: no branches, nothing from before you opened '
                  'the file here, and it is removed if the app is uninstalled.',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: versions.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      available
                          ? 'No earlier versions yet. One is kept each time you '
                                'save over this file.'
                          : 'History needs app storage, which is not available '
                                'on this device.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: versions.length,
                    itemBuilder: (BuildContext context, int i) => _VersionRow(
                      version: versions[i],
                      tokens: tokens,
                      onTap: () => Navigator.of(context).pop(versions[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.tokens,
    required this.onTap,
  });

  final FileVersion version;
  final AppColorTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String label = 'Before ${clockTime(version.savedAt)}';
    final String detail =
        '${relativeTime(version.savedAt)} · ${formatSize(version.byteLength)}';

    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: '$label, $detail',
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppSizes.primaryTouchTarget,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.history, size: 16, color: tokens.textMuted),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: tokens.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
