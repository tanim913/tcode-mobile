/// Accent colour swatches, plus the option to hand the choice back to the
/// theme.
///
/// This is the one widget in the app allowed to contain colour literals: a
/// palette of named accents is data the user picks from, not a themed surface,
/// so there is nothing for a token to stand in for. Every other colour here
/// still comes from [AppColorTokens].
library;

import 'package:flutter/material.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_color_tokens.dart';

/// A selectable accent, named so the choice never rests on colour alone.
@immutable
class AccentSwatch {
  const AccentSwatch(this.name, this.color);

  final String name;
  final Color color;
}

// --- The palette ------------------------------------------------------------
// The only colour literals outside core/theme. Chosen to stay legible against
// both the dark and the light app surfaces, since one accent serves both.
const List<AccentSwatch> accentSwatches = <AccentSwatch>[
  AccentSwatch('Blue', Color(0xFF4C8EFF)),
  AccentSwatch('Teal', Color(0xFF19B4A6)),
  AccentSwatch('Green', Color(0xFF3FA65B)),
  AccentSwatch('Amber', Color(0xFFD99A28)),
  AccentSwatch('Orange', Color(0xFFE2703A)),
  AccentSwatch('Red', Color(0xFFE0525F)),
  AccentSwatch('Pink', Color(0xFFD3599C)),
  AccentSwatch('Purple', Color(0xFF9067E0)),
];

class AccentColorPicker extends StatelessWidget {
  const AccentColorPicker({
    required this.selectedValue,
    required this.onSelected,
    required this.onCleared,
    super.key,
  });

  /// Null means "use the theme's own accent".
  final int? selectedValue;

  final ValueChanged<Color> onSelected;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    final AppColorTokens tokens = Theme.of(context).extension<AppColorTokens>()!;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Accent colour',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          ChoiceChip(
            label: const Text('Theme default'),
            selected: selectedValue == null,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (bool selected) {
              if (selected) {
                onCleared();
              }
            },
          ),
          for (final AccentSwatch swatch in accentSwatches)
            _Swatch(
              swatch: swatch,
              selected: selectedValue == swatch.color.toARGB32(),
              tokens: tokens,
              onTap: () => onSelected(swatch.color),
            ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.swatch,
    required this.selected,
    required this.tokens,
    required this.onTap,
  });

  final AccentSwatch swatch;
  final bool selected;
  final AppColorTokens tokens;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: swatch.name,
      selected: selected,
      button: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Tooltip(
          message: swatch.name,
          child: InkWell(
            onTap: onTap,
            borderRadius: const BorderRadius.all(
              Radius.circular(AppSizes.primaryTouchTarget / 2),
            ),
            child: SizedBox(
              width: AppSizes.primaryTouchTarget,
              height: AppSizes.primaryTouchTarget,
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: swatch.color,
                    shape: BoxShape.circle,
                    // A ring rather than a colour change marks the selection,
                    // so the state is visible to a colour-blind user too.
                    border: Border.all(
                      color: selected ? tokens.textPrimary : tokens.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: _contrastOn(swatch.color),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Black or white, whichever stays readable on [background].
///
/// Computed rather than themed because the swatch colour is the user's choice,
/// not a surface the theme knows about.
Color _contrastOn(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF101010);
}

/// Label for the current choice, so the setting reads correctly in search
/// results and to a screen reader without inspecting the swatches.
String accentLabel(int? value) {
  if (value == null) {
    return 'Theme default';
  }
  for (final AccentSwatch swatch in accentSwatches) {
    if (swatch.color.toARGB32() == value) {
      return swatch.name;
    }
  }
  return 'Custom';
}
