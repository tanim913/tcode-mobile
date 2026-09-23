/// The search screen, with and without a folder scope.
///
/// The panel owns no I/O: it hands every query to its callbacks. So these tests
/// record what the callbacks receive, which is exactly the contract that
/// matters — above all, that a scoped replace-all is still scoped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/search/presentation/search_panel.dart';
import 'package:pocket_code/services/search/file_indexer.dart';
import 'package:pocket_code/services/search/search_scope.dart';
import 'package:pocket_code/services/search/workspace_search.dart';

const SearchScope libScope = SearchScope(
  rootIndex: 0,
  folderId: '/w/lib',
  relativePath: 'lib',
  name: 'lib',
);

/// One hit, so replace-all has something to act on.
SearchResults oneHit() => const SearchResults(
  files: <FileMatches>[
    FileMatches(
      file: IndexedFile(
        node: FileNode(
          id: '/w/lib/a.dart',
          name: 'a.dart',
          displayPath: '/w/lib/a.dart',
        ),
        rootIndex: 0,
        relativePath: 'lib/a.dart',
      ),
      matches: <SearchMatch>[
        SearchMatch(line: 1, column: 1, lineText: 'foo', start: 0, length: 3),
      ],
    ),
  ],
  truncated: false,
  filesSearched: 1,
  filesSkipped: 0,
);

class Recorder {
  final List<SearchScope?> searched = <SearchScope?>[];
  final List<SearchScope?> replaced = <SearchScope?>[];
}

Future<Recorder> pumpPanel(WidgetTester tester, {SearchScope? scope}) async {
  final Recorder recorder = Recorder();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: SearchPanel(
        initialScope: scope,
        onSearch: (SearchQuery query, SearchScope? s) async {
          recorder.searched.add(s);
          return oneHit();
        },
        onReplaceAll:
            (SearchQuery query, String replacement, SearchScope? s) async {
              recorder.replaced.add(s);
              return 1;
            },
        onOpenHit: (FileMatches _, SearchMatch _) {},
      ),
    ),
  );
  return recorder;
}

Future<void> search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField).first, text);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('without a scope it searches the workspace', (
    WidgetTester tester,
  ) async {
    final Recorder r = await pumpPanel(tester);

    expect(find.text('Search in workspace'), findsOneWidget);
    expect(find.textContaining('Searching in'), findsNothing);

    await search(tester, 'foo');
    expect(r.searched, <SearchScope?>[null]);
  });

  testWidgets('with a scope it says so, and passes the scope on', (
    WidgetTester tester,
  ) async {
    final Recorder r = await pumpPanel(tester, scope: libScope);

    expect(find.text('Find in folder'), findsOneWidget);
    expect(
      find.text('Searching in lib/'),
      findsOneWidget,
      reason: 'a narrowed search must never look like a full one',
    );

    await search(tester, 'foo');
    expect(r.searched, <SearchScope?>[libScope]);
  });

  testWidgets('clearing the chip widens to the workspace and searches again', (
    WidgetTester tester,
  ) async {
    final Recorder r = await pumpPanel(tester, scope: libScope);
    await search(tester, 'foo');

    await tester.tap(find.byTooltip('Search the whole workspace'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Searching in'), findsNothing);
    expect(r.searched, <SearchScope?>[
      libScope,
      null,
    ], reason: 'the results on screen must match the chip');
  });

  testWidgets('a scoped replace-all is still scoped, and says where', (
    WidgetTester tester,
  ) async {
    // The one place a lost scope would do damage: it would rewrite files the
    // user never saw in the results.
    final Recorder r = await pumpPanel(tester, scope: libScope);
    await search(tester, 'foo');

    await tester.tap(find.byTooltip('Show replace'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace all'));
    await tester.pumpAndSettle();

    expect(find.text('Replace in lib/?'), findsOneWidget);
    // The bar behind the dialog has a "Replace all" button too; confirm the
    // dialog's own.
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Replace all'),
      ),
    );
    await tester.pumpAndSettle();

    expect(r.replaced, <SearchScope?>[libScope]);
  });
}
