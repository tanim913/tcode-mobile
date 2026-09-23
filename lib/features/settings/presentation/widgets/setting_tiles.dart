/// The handful of control shapes every setting is built from.
///
/// Keeping the shapes here rather than in each section means the touch target
/// floor, the semantics and the text-scale behaviour are decided once. The
/// tiles lay out vertically (label above, control below) wherever the control
/// is wider than a switch, because a side-by-side row is what overflows first
/// at a large system text scale.
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// Shared frame: title, description, an optional trailing control and an
/// optional full-width control underneath.
class SettingTileFrame extends StatelessWidget {
  const SettingTileFrame({
    required this.title,
    required this.description,
    super.key,
    this.trailing,
    this.below,
    this.onTap,
  });

  final String title;
  final String description;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AppColorTokens tokens = theme.extension<AppColorTokens>()!;

    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(title, style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 12),
                trailing!,
              ],
            ],
          ),
          if (below != null) ...<Widget>[
            const SizedBox(height: 10),
            below!,
          ],
        ],
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppSizes.primaryTouchTarget,
      ),
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, child: content),
    );
  }
}

/// An on/off setting.
class SettingSwitchTile extends StatelessWidget {
  const SettingSwitchTile({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    void toggle() => onChanged(!value);

    // One semantics node for the whole row: the label, the explanation and the
    // state read as a single sentence instead of three fragments.
    return Semantics(
      container: true,
      label: title,
      hint: description,
      toggled: value,
      onTap: toggle,
      child: ExcludeSemantics(
        child: SettingTileFrame(
          title: title,
          description: description,
          onTap: toggle,
          trailing: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}

/// One option in a [SettingChoiceTile].
@immutable
class SettingChoice<T> {
  const SettingChoice(this.value, this.label);

  final T value;
  final String label;
}

/// A small set of mutually exclusive options, shown as wrapping chips so a
/// large text scale pushes them onto more rows instead of clipping them.
class SettingChoiceTile<T> extends StatelessWidget {
  const SettingChoiceTile({
    required this.title,
    required this.description,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String description;
  final T value;
  final List<SettingChoice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingTileFrame(
      title: title,
      description: description,
      below: SettingChoiceRow<T>(
        groupLabel: title,
        value: value,
        choices: choices,
        onChanged: onChanged,
      ),
    );
  }
}

/// The chip row on its own, for tiles that pair it with another control.
class SettingChoiceRow<T> extends StatelessWidget {
  const SettingChoiceRow({
    required this.groupLabel,
    required this.value,
    required this.choices,
    required this.onChanged,
    super.key,
  });

  final String groupLabel;
  final T value;
  final List<SettingChoice<T>> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: groupLabel,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final SettingChoice<T> choice in choices)
            ChoiceChip(
              label: Text(choice.label),
              selected: choice.value == value,
              // Padded keeps the chip's hit area at the 48dp floor even though
              // the chip itself is drawn compactly.
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (bool selected) {
                if (selected) {
                  onChanged(choice.value);
                }
              },
            ),
        ],
      ),
    );
  }
}

/// A continuous value, with the current reading shown as text next to the
/// title so nothing depends on reading the slider position alone.
class SettingSliderTile extends StatelessWidget {
  const SettingSliderTile({
    required this.title,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.valueLabel,
    required this.onChanged,
    super.key,
    this.below,
  });

  final String title;
  final String description;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  /// Extra control rendered above the slider, e.g. the font size presets.
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SettingTileFrame(
      title: title,
      description: description,
      trailing: Text(valueLabel, style: theme.textTheme.labelLarge),
      below: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (below != null) ...<Widget>[below!, const SizedBox(height: 4)],
          Semantics(
            container: true,
            label: title,
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: valueLabel,
              semanticFormatterCallback: (double _) => valueLabel,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting whose control is bespoke — the accent palette, the exclude list.
class SettingCustomTile extends StatelessWidget {
  const SettingCustomTile({
    required this.title,
    required this.description,
    required this.child,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SettingTileFrame(
      title: title,
      description: description,
      below: child,
    );
  }
}
