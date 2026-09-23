/// Shown instead of the editor for a binary file.
///
/// The brief is explicit that a binary file must not be loaded into the text
/// editor: rendering it is meaningless, and saving it would corrupt the file.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/file_node.dart';

class BinaryViewer extends StatelessWidget {
  const BinaryViewer({required this.node, super.key});

  final FileNode node;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return ColoredBox(
      color: tokens.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.memory_outlined, size: 34, color: tokens.textMuted),
              const SizedBox(height: 12),
              Text(
                '${node.name} is a binary file',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  'It is not shown as text, because rendering it would be '
                  'meaningless and saving it could corrupt the file. Use the '
                  'file menu in the explorer to share it or open it in another '
                  'app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
