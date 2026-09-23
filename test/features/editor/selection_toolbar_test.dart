/// The Cut / Copy / Paste / Select all pill over a selection.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/features/editor/presentation/selection_toolbar.dart';
import 'package:re_editor/re_editor.dart';

/// Mounts whatever the controller's builder produces, so the buttons it offers
/// can be inspected without a live editor.
Future<void> showToolbar(
  WidgetTester tester,
  ToolbarMenuBuilder builder,
  CodeLineEditingController code,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: Builder(
        builder: (BuildContext context) => builder(
          context: context,
          anchors: const TextSelectionToolbarAnchors(
            primaryAnchor: Offset.zero,
          ),
          controller: code,
          onDismiss: () {},
          onRefresh: () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  CodeLineEditingController selected(String text) {
    final CodeLineEditingController c =
        CodeLineEditingController.fromText(text);
    addTearDown(c.dispose);
    c.selection = const CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: 0,
      extentOffset: 3,
    );
    return c;
  }

  testWidgets('read-only is read when the toolbar is shown, not when it is built',
      (WidgetTester tester) async {
    // This is what lets a single controller live for the life of the tab.
    // Capturing the value instead meant rebuilding the controller whenever the
    // edit lock changed — and each new controller could only hide its *own*
    // overlay entry, so the previous pill stayed on screen and they stacked up.
    bool locked = false;
    final ToolbarMenuBuilder toolbar =
        selectionToolbarBuilder(isReadOnly: () => locked);
    final CodeLineEditingController code = selected('abc');

    await showToolbar(tester, toolbar, code);
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);

    locked = true;
    await showToolbar(tester, toolbar, code);

    expect(find.text('Cut'), findsNothing,
        reason: 'the same controller must follow the lock');
    expect(find.text('Paste'), findsNothing);
    expect(find.text('Copy'), findsOneWidget,
        reason: 'a locked file can still be copied from');
    expect(find.text('Select all'), findsOneWidget);
  });

  testWidgets('a collapsed caret offers Paste but not Cut or Copy',
      (WidgetTester tester) async {
    final CodeLineEditingController code =
        CodeLineEditingController.fromText('abc');
    addTearDown(code.dispose);
    code.selection = const CodeLineSelection.collapsed(index: 0, offset: 1);

    await showToolbar(
      tester,
      selectionToolbarBuilder(isReadOnly: () => false),
      code,
    );

    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Cut'), findsNothing,
        reason: 'with nothing selected, Cut would take the whole line');
    expect(find.text('Copy'), findsNothing);
  });
}
