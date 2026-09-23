/// Builders that pair a catalogue entry with its control.
///
/// Every setting needs its title and description twice — once for search, once
/// on screen — and typing them twice is how the two drift apart. These
/// builders take them once and hand them to both.
library;

import 'package:flutter/widgets.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';
import 'package:pocket_code/features/settings/presentation/widgets/setting_tiles.dart';

SettingEntry toggleEntry({
  required String id,
  required String title,
  required String description,
  required bool value,
  required ValueChanged<bool> onChanged,
  List<String> keywords = const <String>[],
}) {
  return SettingEntry(
    id: id,
    title: title,
    description: description,
    keywords: keywords,
    control: SettingSwitchTile(
      title: title,
      description: description,
      value: value,
      onChanged: onChanged,
    ),
  );
}

SettingEntry choiceEntry<T>({
  required String id,
  required String title,
  required String description,
  required T value,
  required List<SettingChoice<T>> choices,
  required ValueChanged<T> onChanged,
  List<String> keywords = const <String>[],
}) {
  return SettingEntry(
    id: id,
    title: title,
    description: description,
    keywords: keywords,
    control: SettingChoiceTile<T>(
      title: title,
      description: description,
      value: value,
      choices: choices,
      onChanged: onChanged,
    ),
  );
}

SettingEntry sliderEntry({
  required String id,
  required String title,
  required String description,
  required double value,
  required double min,
  required double max,
  required int divisions,
  required String valueLabel,
  required ValueChanged<double> onChanged,
  List<String> keywords = const <String>[],
  Widget? below,
}) {
  return SettingEntry(
    id: id,
    title: title,
    description: description,
    keywords: keywords,
    control: SettingSliderTile(
      title: title,
      description: description,
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      valueLabel: valueLabel,
      onChanged: onChanged,
      below: below,
    ),
  );
}

SettingEntry customEntry({
  required String id,
  required String title,
  required String description,
  required Widget child,
  List<String> keywords = const <String>[],
}) {
  return SettingEntry(
    id: id,
    title: title,
    description: description,
    keywords: keywords,
    control: SettingCustomTile(
      title: title,
      description: description,
      child: child,
    ),
  );
}
