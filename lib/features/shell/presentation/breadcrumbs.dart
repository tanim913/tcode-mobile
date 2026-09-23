/// Path of the open file, relative to its workspace root.
///
/// Horizontally scrollable and reversed-aligned, so on a narrow phone the part
/// that matters — the file name — stays visible and the leading folders scroll
/// off to the left.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

class Breadcrumbs extends StatelessWidget {
  const Breadcrumbs({
    required this.segments,
    required this.onTapSegment,
    super.key,
  });

  /// Root name first, file name last.
  final List<String> segments;

  /// Called with the index of a tapped folder segment. The file itself, the
  /// last segment, is not tappable — it is already open.
  final void Function(int index) onTapSegment;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;
    if (segments.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: AppSizes.breadcrumbHeight,
      decoration: BoxDecoration(
        color: tokens.background,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < segments.length; i++) ...<Widget>[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Icon(
                    Icons.chevron_right,
                    size: 13,
                    color: tokens.textMuted,
                  ),
                ),
              _Segment(
                label: segments[i],
                isLast: i == segments.length - 1,
                tokens: tokens,
                onTap: i == segments.length - 1 ? null : () => onTapSegment(i),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isLast,
    required this.tokens,
    required this.onTap,
  });

  final String label;
  final bool isLast;
  final AppColorTokens tokens;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget text = Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isLast ? tokens.textPrimary : tokens.textSecondary,
            fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
          ),
    );
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: text,
      );
    }
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: text,
      ),
    );
  }
}
