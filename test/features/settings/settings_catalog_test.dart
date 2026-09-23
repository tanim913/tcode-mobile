import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/settings/application/settings_catalog.dart';

SettingEntry entry(String id, String title, String description) => SettingEntry(
      id: id,
      title: title,
      description: description,
      control: const SizedBox.shrink(),
    );

SettingsGroup makeGroup(
  String id,
  String title,
  String description,
  List<SettingEntry> entries,
) =>
    SettingsGroup(
      id: id,
      title: title,
      description: description,
      entries: entries,
      onReset: () async {},
    );

List<SettingsGroup> sample() => <SettingsGroup>[
      makeGroup('editor', 'Editor', 'Font, indentation and saving', <SettingEntry>[
        entry('wrap', 'Word wrap', 'Break long lines instead of scrolling'),
        entry('size', 'Font size', 'How large the code text appears'),
      ]),
      makeGroup('appearance', 'Appearance', 'Themes and colours', <SettingEntry>[
        entry('theme', 'App theme', 'Light, dark or follow the system'),
      ]),
    ];

void main() {
  group('filtering', () {
    test('an empty query returns everything untouched', () {
      final List<SettingsGroup> all = sample();
      expect(filterSettings(all, ''), all);
      expect(filterSettings(all, '   '), all);
    });

    test('matches a setting title', () {
      final List<SettingsGroup> result = filterSettings(sample(), 'word wrap');
      expect(result.length, 1);
      expect(result.single.entries.single.id, 'wrap');
    });

    test('matches a setting description, not only its title', () {
      // A user searching for what a setting does should find it even if they
      // never learned the label.
      final List<SettingsGroup> result = filterSettings(sample(), 'long lines');
      expect(result.single.entries.single.id, 'wrap');
    });

    test('matching a group title keeps all of its entries', () {
      final List<SettingsGroup> result = filterSettings(sample(), 'editor');
      expect(result.single.entries.length, 2,
          reason: 'searching a section name should show the whole section');
    });

    test('matching a group description keeps all of its entries', () {
      final List<SettingsGroup> result = filterSettings(sample(), 'colours');
      expect(result.single.id, 'appearance');
      expect(result.single.entries.length, 1);
    });

    test('search is case insensitive', () {
      expect(filterSettings(sample(), 'WORD WRAP').length, 1);
    });

    test('a query matching nothing returns no groups', () {
      expect(filterSettings(sample(), 'bluetooth'), isEmpty);
    });

    test('groups with no matching entries are dropped entirely', () {
      final List<SettingsGroup> result = filterSettings(sample(), 'font');
      expect(result.length, 1);
      expect(result.single.id, 'editor');
    });

    test('filtering does not mutate the input', () {
      final List<SettingsGroup> all = sample();
      filterSettings(all, 'wrap');
      expect(all.first.entries.length, 2);
    });
  });

  group('counting', () {
    test('counts every entry across groups', () {
      expect(countSettings(sample()), 3);
    });

    test('an empty catalogue counts zero', () {
      expect(countSettings(const <SettingsGroup>[]), 0);
    });
  });
}
