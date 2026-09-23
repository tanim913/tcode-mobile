/// Ranking for the command palette and Quick Open.
///
/// Both are pure functions over a list, which is why the ordering rules can be
/// pinned down here rather than by driving a sheet.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/commands/presentation/command_palette.dart';
import 'package:pocket_code/features/commands/presentation/palette_scaffold.dart';
import 'package:pocket_code/features/commands/presentation/quick_open.dart';
import 'package:pocket_code/services/commands/command.dart';
import 'package:pocket_code/services/search/file_indexer.dart';

Command cmd(
  String id,
  String title, {
  CommandCategory category = CommandCategory.edit,
  bool Function()? isEnabled,
}) {
  return Command(
    id: id,
    title: title,
    category: category,
    isEnabled: isEnabled,
    handler: () async {},
  );
}

IndexedFile file(String path) {
  final int cut = path.lastIndexOf('/');
  final String name = cut < 0 ? path : path.substring(cut + 1);
  return IndexedFile(
    node: FileNode(id: '/w/$path', name: name, displayPath: '/w/$path'),
    rootIndex: 0,
    relativePath: path,
  );
}

void main() {
  group('rankCommands', () {
    final List<Command> commands = <Command>[
      cmd('file.save', 'Save', category: CommandCategory.file),
      cmd('file.saveAll', 'Save all', category: CommandCategory.file),
      cmd('edit.undo', 'Undo'),
      cmd('view.toggleWordWrap', 'Toggle word wrap',
          category: CommandCategory.view),
    ];

    test('an empty query keeps registration order', () {
      final List<RankedCommand> r = rankCommands(commands, '');
      expect(
        r.map((RankedCommand c) => c.command.id),
        <String>['file.save', 'file.saveAll', 'edit.undo', 'view.toggleWordWrap'],
        reason: 'registration order groups the catalogue by category',
      );
    });

    test('ranks an exact title above a longer one containing it', () {
      final List<RankedCommand> r = rankCommands(commands, 'save');
      expect(r.first.command.id, 'file.save');
    });

    test('matches initials across words', () {
      // "tww" for "Toggle word wrap" is how people actually search.
      final List<RankedCommand> r = rankCommands(commands, 'tww');
      expect(r.first.command.id, 'view.toggleWordWrap');
    });

    test('a category name finds its commands', () {
      final List<RankedCommand> r = rankCommands(commands, 'file');
      expect(
        r.map((RankedCommand c) => c.command.id),
        containsAll(<String>['file.save', 'file.saveAll']),
        reason: 'people search by area when they do not recall the verb',
      );
    });

    test('reports the matched characters for highlighting', () {
      final List<RankedCommand> r = rankCommands(commands, 'undo');
      expect(r.first.match.indices, <int>[0, 1, 2, 3]);
    });

    test('keeps disabled commands in the list', () {
      final List<Command> withDisabled = <Command>[
        cmd('file.save', 'Save', isEnabled: () => false),
      ];
      final List<RankedCommand> r = rankCommands(withDisabled, 'save');
      expect(r, hasLength(1),
          reason: 'hiding it would read as "this app has no save command"');
      expect(r.first.command.enabled, isFalse);
    });

    test('drops commands that do not match at all', () {
      expect(rankCommands(commands, 'zzzz'), isEmpty);
    });
  });

  group('rankFiles', () {
    final List<IndexedFile> files = <IndexedFile>[
      file('main.dart'),
      file('lib/services/filesystem/file_system_provider.dart'),
      file('lib/features/editor/presentation/editor_pane.dart'),
      file('README.md'),
    ];

    test('an empty query lists the shallowest files first', () {
      final List<RankedFile> r = rankFiles(files, '');
      expect(
        r.take(2).map((RankedFile f) => f.file.relativePath),
        <String>['README.md', 'main.dart'],
        reason: 'root files are the likeliest targets before anything is typed',
      );
    });

    test('initials find a deeply nested file', () {
      final List<RankedFile> r = rankFiles(files, 'fsp');
      expect(
        r.first.file.name,
        'file_system_provider.dart',
        reason: 'boundary bonuses must beat an incidental subsequence',
      );
    });

    test('a folder fragment narrows the list', () {
      final List<RankedFile> r = rankFiles(files, 'editor/');
      expect(r.first.file.relativePath, contains('editor/'));
    });

    test('highlight indices point at the basename, not the path', () {
      final List<RankedFile> r = rankFiles(files, 'main');
      final RankedFile top = r.first;
      expect(top.file.name, 'main.dart');
      expect(top.nameIndices, <int>[0, 1, 2, 3],
          reason: 'the row shows the basename, so indices must index it');
    });

    test('honours the result limit', () {
      final List<IndexedFile> many =
          List<IndexedFile>.generate(500, (int i) => file('f$i.dart'));
      expect(rankFiles(many, 'dart', limit: 10), hasLength(10));
      expect(rankFiles(many, '', limit: 10), hasLength(10));
    });

    test('returns nothing when no file matches', () {
      expect(rankFiles(files, 'qqqq'), isEmpty);
    });
  });

  group('HighlightedText', () {
    testWidgets('splits the label into matched and unmatched runs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HighlightedText(
              text: 'Save all',
              indices: <int>[0, 5],
              highlightColour: Color(0xFF4D9FFF),
            ),
          ),
        ),
      );

      final RichText rich = tester.widget<RichText>(find.byType(RichText));

      // Text.rich nests the runs under a wrapping span, so collect the leaves
      // rather than assuming a flat children list.
      final List<String> runs = <String>[];
      rich.text.visitChildren((InlineSpan span) {
        final String? text = (span as TextSpan).text;
        if (text != null) {
          runs.add(text);
        }
        return true;
      });

      expect(
        runs,
        <String>['S', 'ave ', 'a', 'll'],
        reason: 'each run is one span so only the matches can be styled',
      );
    });

    testWidgets('renders plain text when nothing matched', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HighlightedText(
              text: 'Save',
              indices: <int>[],
              highlightColour: Color(0xFF4D9FFF),
            ),
          ),
        ),
      );
      expect(find.text('Save'), findsOneWidget);
    });
  });
}
