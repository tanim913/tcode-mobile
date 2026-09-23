/// Displays an image file with pinch zoom and pan.
///
/// Loads through the [FileSystemProvider] rather than `Image.file`, because on
/// web there is no file path — only a handle — and the same code must serve
/// both platforms.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({required this.node, required this.rootIndex, super.key});

  final FileNode node;
  final int rootIndex;

  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  Uint8List? _bytes;
  AppFailure? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final LiveRoot? root =
        ref.read(workspaceProvider)?.rootAt(widget.rootIndex);
    if (root == null) {
      return;
    }
    try {
      final Uint8List bytes = await root.provider.readBytes(widget.node.id);
      if (mounted) {
        setState(() => _bytes = bytes);
      }
    } on AppFailure catch (failure) {
      if (mounted) {
        setState(() => _error = failure);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    if (_error != null) {
      return _Centered(
        tokens: tokens,
        icon: Icons.broken_image_outlined,
        title: _error!.message,
        body: _error!.hint,
      );
    }
    final Uint8List? bytes = _bytes;
    if (bytes == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ColoredBox(
      color: tokens.background,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.2,
              maxScale: 8,
              child: Center(
                child: Image.memory(
                  bytes,
                  // Nearest-neighbour keeps pixel art and icons crisp when
                  // zoomed in, which is usually why someone is zooming.
                  filterQuality: FilterQuality.none,
                  errorBuilder: (BuildContext context, Object _, StackTrace? _) =>
                      _Centered(
                    tokens: tokens,
                    icon: Icons.broken_image_outlined,
                    title: 'This image could not be decoded',
                    body: 'The file may be damaged, or use a format this '
                        'device does not support.',
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _Chip(
              tokens: tokens,
              label: '${widget.node.name}  ·  ${_formatBytes(bytes.length)}',
            ),
          ),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.tokens, required this.label});

  final AppColorTokens tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.border),
        borderRadius: const BorderRadius.all(Radius.circular(4)),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.tokens,
    required this.icon,
    required this.title,
    required this.body,
  });

  final AppColorTokens tokens;
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: tokens.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 34, color: tokens.textMuted),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  body,
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
