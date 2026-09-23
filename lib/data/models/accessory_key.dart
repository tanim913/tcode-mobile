/// The keys shown on the coding accessory bar above the soft keyboard.
///
/// A phone keyboard has no `{`, `}`, `(`, `)`, `[`, `]` or `;` within reach,
/// which is the single biggest obstacle to writing code on one. This model
/// describes what the bar offers, and is persisted so the set and order stay
/// configurable per the brief.
///
/// Keys are inserted through the editor controller, never by synthesising
/// platform key events — that is what keeps the bar working with every Android
/// and iOS keyboard and stops it fighting autocorrect.
library;

import 'package:flutter/foundation.dart';

/// What pressing a key does.
enum AccessoryKeyKind {
  /// Inserts [AccessoryKey.text] at the cursor.
  insert,

  /// Inserts one indent level, or outdents when Shift is held.
  tab,

  /// Sticky modifier: while held, arrows extend the selection and Tab outdents.
  shift,

  arrowLeft,
  arrowRight,
  arrowUp,
  arrowDown,
}

@immutable
class AccessoryKey {
  const AccessoryKey(this.kind, {this.text, this.label, this.semanticsLabel});

  /// A character key, the common case.
  const AccessoryKey.char(String character)
      : kind = AccessoryKeyKind.insert,
        text = character,
        label = character,
        semanticsLabel = null;

  final AccessoryKeyKind kind;

  /// Inserted text, for [AccessoryKeyKind.insert].
  final String? text;

  /// What is drawn on the key. Falls back to [text].
  final String? label;

  /// Spoken name, for keys whose glyph does not read aloud usefully — a screen
  /// reader saying "left brace" is far clearer than the character itself.
  final String? semanticsLabel;

  String get displayLabel => label ?? text ?? '';

  /// Encoded as a short token so the persisted layout stays human-readable and
  /// editable, rather than an opaque index into an enum.
  String get token => switch (kind) {
        AccessoryKeyKind.insert => 'c:${text ?? ''}',
        AccessoryKeyKind.tab => 'tab',
        AccessoryKeyKind.shift => 'shift',
        AccessoryKeyKind.arrowLeft => 'left',
        AccessoryKeyKind.arrowRight => 'right',
        AccessoryKeyKind.arrowUp => 'up',
        AccessoryKeyKind.arrowDown => 'down',
      };

  /// Returns null for an unrecognised token, so a layout written by a newer
  /// version degrades to "that one key is missing" instead of failing to load.
  static AccessoryKey? fromToken(String token) {
    switch (token) {
      case 'tab':
        return const AccessoryKey(
          AccessoryKeyKind.tab,
          label: 'Tab',
          semanticsLabel: 'Indent',
        );
      case 'shift':
        return const AccessoryKey(
          AccessoryKeyKind.shift,
          label: 'Shift',
          semanticsLabel: 'Shift, extends selection',
        );
      case 'left':
        return const AccessoryKey(
          AccessoryKeyKind.arrowLeft,
          semanticsLabel: 'Move cursor left',
        );
      case 'right':
        return const AccessoryKey(
          AccessoryKeyKind.arrowRight,
          semanticsLabel: 'Move cursor right',
        );
      case 'up':
        return const AccessoryKey(
          AccessoryKeyKind.arrowUp,
          semanticsLabel: 'Move cursor up',
        );
      case 'down':
        return const AccessoryKey(
          AccessoryKeyKind.arrowDown,
          semanticsLabel: 'Move cursor down',
        );
      default:
        if (token.startsWith('c:') && token.length > 2) {
          return AccessoryKey.char(token.substring(2));
        }
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AccessoryKey && other.token == token;

  @override
  int get hashCode => token.hashCode;
}

abstract final class AccessoryKeyLayouts {
  /// Default layout, in the order the brief specifies: navigation first, since
  /// it is reached most often, then the characters code needs and a phone
  /// keyboard hides behind two taps.
  static const List<AccessoryKey> standard = <AccessoryKey>[
    AccessoryKey(AccessoryKeyKind.tab, label: 'Tab', semanticsLabel: 'Indent'),
    AccessoryKey(
      AccessoryKeyKind.shift,
      label: 'Shift',
      semanticsLabel: 'Shift, extends selection',
    ),
    AccessoryKey(AccessoryKeyKind.arrowLeft, semanticsLabel: 'Move cursor left'),
    AccessoryKey(AccessoryKeyKind.arrowRight, semanticsLabel: 'Move cursor right'),
    AccessoryKey(AccessoryKeyKind.arrowUp, semanticsLabel: 'Move cursor up'),
    AccessoryKey(AccessoryKeyKind.arrowDown, semanticsLabel: 'Move cursor down'),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '{',
      semanticsLabel: 'Left brace',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '}',
      semanticsLabel: 'Right brace',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '(',
      semanticsLabel: 'Left parenthesis',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: ')',
      semanticsLabel: 'Right parenthesis',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '[',
      semanticsLabel: 'Left bracket',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: ']',
      semanticsLabel: 'Right bracket',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '<',
      semanticsLabel: 'Less than',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '>',
      semanticsLabel: 'Greater than',
    ),
    AccessoryKey.char('/'),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: r'\',
      semanticsLabel: 'Backslash',
    ),
    AccessoryKey.char('='),
    AccessoryKey(AccessoryKeyKind.insert, text: ':', semanticsLabel: 'Colon'),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: ';',
      semanticsLabel: 'Semicolon',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '"',
      semanticsLabel: 'Double quote',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: "'",
      semanticsLabel: 'Single quote',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '`',
      semanticsLabel: 'Backtick',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '_',
      semanticsLabel: 'Underscore',
    ),
    AccessoryKey(AccessoryKeyKind.insert, text: '-', semanticsLabel: 'Minus'),
    AccessoryKey(AccessoryKeyKind.insert, text: '+', semanticsLabel: 'Plus'),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '*',
      semanticsLabel: 'Asterisk',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '&',
      semanticsLabel: 'Ampersand',
    ),
    AccessoryKey(AccessoryKeyKind.insert, text: '|', semanticsLabel: 'Pipe'),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '!',
      semanticsLabel: 'Exclamation mark',
    ),
    AccessoryKey(
      AccessoryKeyKind.insert,
      text: '?',
      semanticsLabel: 'Question mark',
    ),
    AccessoryKey(AccessoryKeyKind.insert, text: r'$', semanticsLabel: 'Dollar'),
    AccessoryKey(AccessoryKeyKind.insert, text: '#', semanticsLabel: 'Hash'),
  ];

  static List<String> toTokens(List<AccessoryKey> keys) =>
      keys.map((AccessoryKey k) => k.token).toList();

  /// Decodes a persisted layout, dropping tokens this version does not know.
  /// An empty or fully unrecognised list falls back to [standard], because a bar
  /// with no keys would be worse than ignoring the stored preference.
  static List<AccessoryKey> fromTokens(List<String> tokens) {
    final List<AccessoryKey> keys = <AccessoryKey>[];
    for (final String token in tokens) {
      final AccessoryKey? key = AccessoryKey.fromToken(token);
      if (key != null) {
        keys.add(key);
      }
    }
    return keys.isEmpty ? standard : keys;
  }
}
