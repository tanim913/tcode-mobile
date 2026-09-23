/// The app bar's edit toggle.
///
/// The rule under test throughout: the lock may only ever *add* read-only. A
/// document the loader already restricted must stay restricted however the
/// toggle is set, or the button would promise something the app cannot do.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/models/text_format.dart';
import 'package:pocket_code/features/editor/application/edit_lock.dart';
import 'package:pocket_code/features/editor/presentation/toolbars/bottom_toolbar.dart';
import 'package:pocket_code/features/shell/presentation/editor_shell.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/language/language_registry.dart';

import '../../support/fake_file_system.dart';
import '../../support/harness.dart';

OpenTab tabWith(DocumentRestriction restriction) => OpenTab(
      node: const FileNode(
        id: '/workspace/main.dart',
        name: 'main.dart',
        displayPath: '/workspace/main.dart',
      ),
      rootIndex: 0,
      text: 'void main() {}',
      savedText: 'void main() {}',
      format: const TextFormat(),
      language: LanguageRegistry.plainText,
      indent: const IndentStyle.fallback(),
      restriction: restriction,
    );

FakeFileSystemProvider seeded() => FakeFileSystemProvider()
  ..seed(<String, String>{'/workspace/main.dart': 'void main() {}\n'});

Future<ProviderContainer> pumpShell(WidgetTester tester) async {
  final FakeFileSystemProvider provider = seeded();
  final repo = await fakeSettingsRepository();

  tester.view.physicalSize = TestSizes.phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final ProviderContainer container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      initialSettingsProvider.overrideWithValue(const AppSettings()),
      workspaceProvider.overrideWith(
        () => FixedWorkspaceController(workspaceFor(provider)),
      ),
    ],
  );
  addTearDown(container.dispose);

  await container.read(tabsProvider.notifier).open(
        const FileNode(
          id: '/workspace/main.dart',
          name: 'main.dart',
          displayPath: '/workspace/main.dart',
        ),
        0,
      );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.dark(), home: const EditorShell()),
    ),
  );
  await tester.pump();
  return container;
}

Future<void> disposeShell(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  group('isTabEditable', () {
    test('an unrestricted, unlocked tab is editable', () {
      expect(
        isTabEditable(tabWith(DocumentRestriction.none), const <String>{}),
        isTrue,
      );
    });

    test('the lock makes an otherwise editable tab read-only', () {
      final OpenTab tab = tabWith(DocumentRestriction.none);
      expect(isTabEditable(tab, <String>{tab.key}), isFalse);
    });

    test('the lock is per tab, not global', () {
      final OpenTab tab = tabWith(DocumentRestriction.none);
      expect(isTabEditable(tab, const <String>{'9:other.dart'}), isTrue,
          reason: 'locking one file must not lock every file');
    });

    test('a restricted document stays read-only whether locked or not', () {
      for (final DocumentRestriction restriction in <DocumentRestriction>[
        DocumentRestriction.binary,
        DocumentRestriction.image,
        DocumentRestriction.tooLargeToEdit,
      ]) {
        final OpenTab tab = tabWith(restriction);
        expect(isTabEditable(tab, const <String>{}), isFalse,
            reason: '$restriction is read-only on its own');
        expect(isTabEditable(tab, <String>{tab.key}), isFalse,
            reason: 'and the toggle cannot unlock it');
      }
    });

    test('a long-line document is still editable', () {
      // longLines only disables highlighting; it does not restrict editing.
      expect(
        isTabEditable(tabWith(DocumentRestriction.longLines), const <String>{}),
        isTrue,
      );
    });
  });

  group('canToggleEditing', () {
    test('is false with no file open', () {
      expect(canToggleEditing(null), isFalse);
    });

    test('is false for a document the toggle could not unlock', () {
      expect(canToggleEditing(tabWith(DocumentRestriction.binary)), isFalse,
          reason: 'a button that cannot change anything must be disabled');
    });

    test('is true for an ordinary document', () {
      expect(canToggleEditing(tabWith(DocumentRestriction.none)), isTrue);
    });
  });

  group('EditLock', () {
    test('toggles on and back off', () {
      final ProviderContainer c = ProviderContainer();
      addTearDown(c.dispose);
      final EditLock lock = c.read(editLockProvider.notifier);

      expect(lock.isLocked('0:a.dart'), isFalse);
      lock.toggle('0:a.dart');
      expect(lock.isLocked('0:a.dart'), isTrue);
      lock.toggle('0:a.dart');
      expect(lock.isLocked('0:a.dart'), isFalse);
    });
  });

  group('in the shell', () {
    testWidgets('the toggle starts editable and flips to locked', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await pumpShell(tester);

      expect(find.byTooltip('Editing on — tap to lock'), findsOneWidget);

      await tester.tap(find.byTooltip('Editing on — tap to lock'));
      await tester.pump();

      expect(find.byTooltip('Editing off — tap to unlock'), findsOneWidget);
      expect(c.read(editLockProvider), hasLength(1));
      await disposeShell(tester);
    });

    testWidgets('locking disables the editing actions in the toolbar', (
      WidgetTester tester,
    ) async {
      await pumpShell(tester);

      IconButton indentButton() => tester.widget<IconButton>(
            find.descendant(
              of: find.byType(EditorBottomToolbar),
              matching:
                  find.widgetWithIcon(IconButton, Icons.format_indent_increase),
            ),
          );

      expect(indentButton().onPressed, isNotNull);

      await tester.tap(find.byTooltip('Editing on — tap to lock'));
      await tester.pump();

      expect(indentButton().onPressed, isNull,
          reason: 'every editing surface must agree the buffer is locked');
      await disposeShell(tester);
    });

    testWidgets('locking does not disable saving unsaved work', (
      WidgetTester tester,
    ) async {
      final ProviderContainer c = await pumpShell(tester);

      // Edit first, then lock: the changes still have to be savable, or the
      // toggle would trap work in the buffer.
      c
          .read(tabsProvider.notifier)
          .controllerFor(c.read(tabsProvider).active!)
          .text = 'edited';
      await tester.pump();

      await tester.tap(find.byTooltip('Editing on — tap to lock'));
      await tester.pump();

      final IconButton save = tester.widget<IconButton>(
        find.descendant(
          of: find.byType(EditorBottomToolbar),
          matching: find.widgetWithIcon(IconButton, Icons.save_outlined),
        ),
      );
      expect(save.onPressed, isNotNull);
      await disposeShell(tester);
    });
  });
}
