/// The outline's filtering and the jump it produces.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/document_symbol.dart';
import 'package:pocket_code/features/editor/application/editor_actions.dart';
import 'package:pocket_code/features/outline/presentation/outline_sheet.dart';
import 'package:pocket_code/services/language/symbol_extractor.dart';
import 'package:re_editor/re_editor.dart';

DocumentSymbol sym(String name, int line, {int column = 1, int level = 0}) {
  return DocumentSymbol(
    name: name,
    kind: SymbolKind.function,
    line: line,
    column: column,
    level: level,
  );
}

void main() {
  group('rankSymbols', () {
    final List<DocumentSymbol> symbols = <DocumentSymbol>[
      sym('build', 10),
      sym('initState', 4),
      sym('didChangeDependencies', 7),
    ];

    test('an empty query preserves document order', () {
      final List<RankedSymbol> r = rankSymbols(symbols, '');
      expect(
        r.map((RankedSymbol s) => s.symbol.name),
        <String>['build', 'initState', 'didChangeDependencies'],
        reason: 'an outline is structure; re-sorting it destroys the point',
      );
    });

    test('a query ranks by match quality', () {
      final List<RankedSymbol> r = rankSymbols(symbols, 'init');
      expect(r.first.symbol.name, 'initState');
    });

    test('initials match across camelCase', () {
      final List<RankedSymbol> r = rankSymbols(symbols, 'dcd');
      expect(r.first.symbol.name, 'didChangeDependencies');
    });

    test('reports match indices for highlighting', () {
      final List<RankedSymbol> r = rankSymbols(symbols, 'build');
      expect(r.first.indices, <int>[0, 1, 2, 3, 4]);
    });

    test('drops non-matches', () {
      expect(rankSymbols(symbols, 'zzz'), isEmpty);
    });
  });

  group('honesty about the heuristic', () {
    test('the label and unavailable message are fixed in one place', () {
      // The brief requires the panel to be labelled "Basic outline" and to say
      // so when a language has no patterns.
      expect(SymbolExtractor.outlineLabel, 'Basic outline');
      expect(
        SymbolExtractor.unavailableMessage,
        'Outline not available for this language',
      );
    });

    test('an unsupported language reports as unsupported, not empty', () {
      const SymbolExtractor extractor = RegexSymbolExtractor();
      expect(extractor.supports('json'), isFalse);
      expect(extractor.supports('dart'), isTrue);
    });
  });

  group('EditorActions.goToSymbol', () {
    late CodeLineEditingController controller;

    setUp(() {
      controller = CodeLineEditingController.fromText(
        'class A {\n  void build() {}\n}\n',
      );
    });

    tearDown(() => controller.dispose());

    test('lands the caret on the identifier, not the line start', () {
      // `build` starts at column 8 on line 2.
      final bool moved =
          EditorActions(controller).goToSymbol(sym('build', 2, column: 8));

      expect(moved, isTrue);
      expect(controller.selection.extentIndex, 1);
      expect(controller.selection.extentOffset, 7,
          reason: 'column is 1-based, the buffer offset is not');
    });

    test('clamps a column past the end of the line', () {
      final bool moved =
          EditorActions(controller).goToSymbol(sym('x', 3, column: 99));

      expect(moved, isTrue);
      expect(controller.selection.extentOffset, lessThanOrEqualTo(1),
          reason: 'a stale symbol must not throw or land out of range');
    });

    test('refuses a line outside the buffer', () {
      expect(
        EditorActions(controller).goToSymbol(sym('gone', 999)),
        isFalse,
      );
    });

    test('does not modify the text', () {
      EditorActions(controller).goToSymbol(sym('build', 2, column: 8));
      expect(controller.text, 'class A {\n  void build() {}\n}\n');
    });
  });
}
