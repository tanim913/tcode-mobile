/// Properties (files) and Folder Details (folders).
///
/// Opens immediately with a placeholder rather than waiting for the recursive
/// size walk, because on a large folder that walk is seconds long and a dialog
/// that takes seconds to appear reads as a hang.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/file_details.dart';

Future<void> showPropertiesDialog(
  BuildContext context, {
  required String title,
  required Future<FileMetadata> metadata,
}) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) =>
        _PropertiesDialog(title: title, metadata: metadata),
  );
}

class _PropertiesDialog extends StatelessWidget {
  const _PropertiesDialog({required this.title, required this.metadata});

  final String title;
  final Future<FileMetadata> metadata;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: FutureBuilder<FileMetadata>(
          future: metadata,
          builder: (
            BuildContext context,
            AsyncSnapshot<FileMetadata> snapshot,
          ) {
            final FileMetadata? data = snapshot.data;
            if (data == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _rows(context, data),
              ),
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, FileMetadata data) {
    final bool isFolder = data.node is FolderNode;
    return <Widget>[
      _Row(label: 'Name', value: data.node.name),
      _Row(label: isFolder ? 'Path' : 'Full path', value: data.absolutePath),
      if (data.uri != null) _Row(label: 'URI', value: data.uri!),
      _Row(
        label: 'Size',
        value: data.sizeBytes == null
            ? 'Unknown'
            : formatBytes(data.sizeBytes!),
      ),
      if (isFolder)
        _Row(
          label: 'Contents',
          value: data.fileCount == null
              ? 'Unknown'
              : '${data.fileCount} files, ${data.folderCount} folders',
        ),
      _Row(
        label: 'Modified',
        value: data.node.modified == null
            ? 'Unknown'
            : _formatTime(data.node.modified!),
      ),
      if (data.languageId != null)
        _Row(label: 'Language', value: data.languageId!),
      if (data.encodingLabel != null)
        _Row(label: 'Encoding', value: data.encodingLabel!),
      if (data.lineEndingLabel != null)
        _Row(label: 'Line endings', value: data.lineEndingLabel!),
      if (data.isBinary ?? false)
        const _Row(
          label: 'Content',
          value: 'Binary — this file is not valid UTF-8 text.',
        ),
    ];
  }

  /// Local time, in a form that sorts and reads unambiguously without pulling
  /// in a date-formatting dependency.
  static String _formatTime(DateTime time) {
    final DateTime local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
