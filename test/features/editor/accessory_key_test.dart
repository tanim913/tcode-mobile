import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/accessory_key.dart';

void main() {
  group('the standard layout', () {
    test('includes every character the brief specifies', () {
      final Set<String> chars = AccessoryKeyLayouts.standard
          .where((AccessoryKey k) => k.kind == AccessoryKeyKind.insert)
          .map((AccessoryKey k) => k.text!)
          .toSet();

      const List<String> required = <String>[
        '{', '}', '(', ')', '[', ']', '<', '>', '/', r'\',
        '=', ':', ';', '"', "'", '`', '_', '-', '+', '*',
        '&', '|', '!', '?', r'$', '#',
      ];
      for (final String c in required) {
        expect(chars, contains(c), reason: 'missing the "$c" key');
      }
    });

    test('leads with Tab, Shift and the four arrows', () {
      expect(
        AccessoryKeyLayouts.standard.take(6).map((AccessoryKey k) => k.kind),
        <AccessoryKeyKind>[
          AccessoryKeyKind.tab,
          AccessoryKeyKind.shift,
          AccessoryKeyKind.arrowLeft,
          AccessoryKeyKind.arrowRight,
          AccessoryKeyKind.arrowUp,
          AccessoryKeyKind.arrowDown,
        ],
      );
    });

    test('character keys carry a spoken name where the glyph is unclear', () {
      // A screen reader saying "left brace" beats reading the glyph.
      final AccessoryKey brace = AccessoryKeyLayouts.standard
          .firstWhere((AccessoryKey k) => k.text == '{');
      expect(brace.semanticsLabel, 'Left brace');
    });
  });

  group('token round trip', () {
    test('the whole standard layout survives encode and decode', () {
      final List<String> tokens =
          AccessoryKeyLayouts.toTokens(AccessoryKeyLayouts.standard);
      expect(
        AccessoryKeyLayouts.fromTokens(tokens),
        AccessoryKeyLayouts.standard,
      );
    });

    test('an unknown token is dropped, not fatal', () {
      final List<AccessoryKey> keys =
          AccessoryKeyLayouts.fromTokens(<String>['tab', 'sideways', 'c:{']);
      expect(keys.length, 2);
      expect(keys.last.text, '{');
    });

    test('an empty layout falls back to the standard one', () {
      // A bar with no keys would be worse than ignoring the stored value.
      expect(
        AccessoryKeyLayouts.fromTokens(const <String>[]),
        AccessoryKeyLayouts.standard,
      );
    });

    test('a layout of only unknown tokens also falls back', () {
      expect(
        AccessoryKeyLayouts.fromTokens(<String>['nope', 'also-nope']),
        AccessoryKeyLayouts.standard,
      );
    });

    test('a multi-character token decodes as that whole string', () {
      expect(AccessoryKey.fromToken('c:=>')?.text, '=>');
    });
  });
}
