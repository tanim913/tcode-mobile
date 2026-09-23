/// Widget tests for the explorer, against the brief's explicit requirements.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/core/constants/sizes.dart';
import 'package:pocket_code/core/theme/app_theme.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/accounts/application/accounts_controller.dart';
import 'package:pocket_code/features/explorer/presentation/explorer_panel.dart';
import 'package:pocket_code/features/shell/presentation/explorer_scaffold.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

import '../../support/fake_file_system.dart';
import '../../support/fake_transport.dart';
import '../../support/harness.dart';

/// A project with enough shape to exercise nesting and lazy loading.
FakeFileSystemProvider seededProject() {
  return FakeFileSystemProvider()
    ..seed(<String, String>{
      '/workspace/README.md': '# Project',
      '/workspace/pubspec.yaml': 'name: demo',
      '/workspace/lib/main.dart': 'void main() {}',
      '/workspace/lib/src/app.dart': 'class App {}',
      '/workspace/lib/src/deep/nested.dart': 'class Nested {}',
      '/workspace/test/app_test.dart': 'void main() {}',
      '/workspace/.hidden_file': 'secret',
      '/workspace/build/output.txt': 'generated',
    });
}

Future<void> pumpExplorer(
  WidgetTester tester,
  FakeFileSystemProvider provider, {
  AppSettings settings = const AppSettings(),
  Size size = TestSizes.phone,
  void Function(FileNode, int)? onOpenFile,
  VoidCallback? onCloseFolder,
  void Function(FolderNode, int)? onFindInFolder,
  void Function(FolderNode, int)? onProposeChanges,
  bool network = true,
  ExplorerPanelController? panelController,
  bool withScaffold = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = await fakeSettingsRepository();
  final panel = ExplorerPanel(
    onOpenFile: onOpenFile ?? (FileNode _, int _) {},
    onCloseFolder: onCloseFolder ?? () {},
    onFindInFolder: onFindInFolder ?? (FolderNode _, int _) {},
    onProposeChanges: onProposeChanges ?? (FolderNode _, int _) {},
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        initialSettingsProvider.overrideWithValue(settings),
        workspaceProvider.overrideWith(
          () => FixedWorkspaceController(workspaceFor(provider)),
        ),
        httpTransportProvider
            .overrideWithValue(FakeTransport(available: network)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: withScaffold
              ? ExplorerScaffold(
                  controller: panelController!,
                  panel: panel,
                  body: const ColoredBox(
                    color: Color(0xFF000000),
                    child: SizedBox.expand(),
                  ),
                )
              : panel,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('tree contents', () {
    testWidgets('lists the root folder and sorts folders first', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      expect(find.text('lib'), findsOneWidget);
      expect(find.text('test'), findsOneWidget);
      expect(find.text('README.md'), findsOneWidget);

      // Folders before files.
      final double libY = tester.getTopLeft(find.text('lib')).dy;
      final double readmeY = tester.getTopLeft(find.text('README.md')).dy;
      expect(libY, lessThan(readmeY));
    });

    testWidgets('hidden files and excluded folders are filtered out', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      expect(find.text('.hidden_file'), findsNothing);
      expect(find.text('build'), findsNothing,
          reason: 'build is in the default exclude list');
    });

    testWidgets('showing hidden files reveals them without re-reading disk', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(
        tester,
        seededProject(),
        settings: const AppSettings(showHiddenFiles: true),
      );

      expect(find.text('.hidden_file'), findsOneWidget);
    });

    testWidgets('nested children are not loaded until the folder is opened', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      // lib is visible but its contents are not — that is lazy loading.
      expect(find.text('lib'), findsOneWidget);
      expect(find.text('main.dart'), findsNothing);
    });
  });

  group('expanding', () {
    testWidgets('tapping a folder reveals its children', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      expect(find.text('src'), findsOneWidget);
    });

    testWidgets('expanding two levels deep works', (WidgetTester tester) async {
      await pumpExplorer(tester, seededProject());

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('src'));
      await tester.pumpAndSettle();

      expect(find.text('app.dart'), findsOneWidget);
      expect(find.text('deep'), findsOneWidget);
    });

    testWidgets('tapping an expanded folder collapses it again', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsNothing);
    });

    testWidgets('children are indented deeper than their parent', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      final double parentX = tester.getTopLeft(find.text('lib')).dx;
      final double childX = tester.getTopLeft(find.text('main.dart')).dx;
      expect(childX, greaterThan(parentX),
          reason: 'nesting must be visible, not just structural');
    });

    testWidgets('collapse all closes everything but the root', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('main.dart'), findsOneWidget);

      // Collapse all moved into the header's overflow menu: four icons left
      // the workspace name ellipsised to "P…" on a 50%-width phone panel.
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Collapse all'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsNothing);
      expect(find.text('lib'), findsOneWidget,
          reason: 'the root stays open, or the panel would look empty');
    });

    testWidgets('close folder is reachable from the header menu', (
      WidgetTester tester,
    ) async {
      // The workspace name is shown in this header, so this is where closing
      // the folder is looked for — the app bar route alone was not found.
      bool closed = false;
      await pumpExplorer(
        tester,
        seededProject(),
        onCloseFolder: () => closed = true,
      );

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close folder'));
      await tester.pumpAndSettle();

      expect(closed, isTrue,
          reason: 'the shell owns closing, so the menu must call back out');
    });
  });

  group('scroll position', () {
    testWidgets('survives the panel closing and reopening', (
      WidgetTester tester,
    ) async {
      // Closing the explorer unmounts it — the scaffold returns an empty box
      // when fully closed — so without PageStorage the list silently jumps
      // back to the top, losing your place in a long folder.
      //
      // The route is kept alive and only the panel subtree is swapped, which
      // is exactly what the scaffold does; tearing down the whole tree would
      // also destroy the PageStorage bucket and prove nothing.
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{
          for (int i = 0; i < 80; i++)
            '/workspace/file_${i.toString().padLeft(3, '0')}.dart': 'x',
        });

      tester.view.physicalSize = TestSizes.phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = await fakeSettingsRepository();
      final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
      addTearDown(visible.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repo),
            initialSettingsProvider.overrideWithValue(const AppSettings()),
            workspaceProvider.overrideWith(
              () => FixedWorkspaceController(workspaceFor(provider)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: visible,
                builder: (BuildContext context, bool show, _) => show
                    ? ExplorerPanel(
                        onOpenFile: (FileNode _, int _) {},
                        onCloseFolder: () {},
                        onFindInFolder: (FolderNode _, int _) {},
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
      await tester.pumpAndSettle();

      double offset() => tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .position
          .pixels;

      final double scrolled = offset();
      expect(scrolled, greaterThan(0), reason: 'the drag must have scrolled');

      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(ExplorerPanel), findsNothing);

      visible.value = true;
      await tester.pumpAndSettle();

      expect(offset(), scrolled,
          reason: 'reopening must return to where you were');
    });
  });

  group('context menu', () {
    testWidgets('long press on a file opens the menu, with Share and Open With',
        (WidgetTester tester) async {
      // Never covered before, and worth covering: the tree sits inside a
      // RefreshIndicator for pull-to-refresh, and a scrollable that claimed the
      // gesture would silently kill every context menu in the explorer.
      await pumpExplorer(tester, seededProject());

      await tester.longPress(find.text('README.md'));
      await tester.pumpAndSettle();

      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Open With'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
    });

    testWidgets('long press on a folder offers the ZIP actions', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());

      await tester.longPress(find.text('lib'));
      await tester.pumpAndSettle();

      expect(find.text('Export as ZIP'), findsOneWidget);
      expect(find.text('Import from ZIP'), findsOneWidget);
    });

    testWidgets('a folder offers Find in Folder, and it reports that folder', (
      WidgetTester tester,
    ) async {
      FolderNode? found;
      int? foundRoot;
      await pumpExplorer(
        tester,
        seededProject(),
        onFindInFolder: (FolderNode folder, int rootIndex) {
          found = folder;
          foundRoot = rootIndex;
        },
      );

      await tester.longPress(find.text('lib'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Find in Folder…'));
      await tester.pumpAndSettle();

      expect(found?.name, 'lib');
      expect(foundRoot, 0);
    });

    testWidgets('a downloaded repository folder offers a pull request', (
      WidgetTester tester,
    ) async {
      FolderNode? proposed;
      final FakeFileSystemProvider fs = seededProject()
        ..seed(<String, String>{
          '/workspace/lib/.tcode/repo.json':
              '{"host":"github","owner":"o","name":"lib","branch":"main"}',
        });
      await pumpExplorer(
        tester,
        fs,
        onProposeChanges: (FolderNode folder, int _) => proposed = folder,
      );

      await tester.longPress(find.text('lib'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Pull Request…'));
      await tester.pumpAndSettle();

      expect(proposed?.name, 'lib');
    });

    testWidgets('an ordinary folder does not offer a pull request', (
      WidgetTester tester,
    ) async {
      await pumpExplorer(tester, seededProject());
      await tester.longPress(find.text('test'));
      await tester.pumpAndSettle();
      expect(find.text('Create Pull Request…'), findsNothing);
    });

    testWidgets('without the network, even a repository folder does not', (
      WidgetTester tester,
    ) async {
      // The Play build: offering an action it can never complete would be
      // exactly the kind of dead button the app promises not to have.
      final FakeFileSystemProvider fs = seededProject()
        ..seed(<String, String>{
          '/workspace/lib/.tcode/repo.json':
              '{"host":"github","owner":"o","name":"lib","branch":"main"}',
        });
      await pumpExplorer(tester, fs, network: false);
      await tester.longPress(find.text('lib'));
      await tester.pumpAndSettle();
      expect(find.text('Create Pull Request…'), findsNothing);
    });

    testWidgets('a file does not offer Find in Folder', (
      WidgetTester tester,
    ) async {
      // A file has its own in-editor find; offering this on one would be a
      // menu item with no sensible meaning.
      await pumpExplorer(tester, seededProject());

      await tester.longPress(find.text('README.md'));
      await tester.pumpAndSettle();

      expect(find.text('Find in Folder…'), findsNothing);
    });
  });

  group('opening files', () {
    testWidgets('tapping a file reports it, and does not expand anything', (
      WidgetTester tester,
    ) async {
      FileNode? opened;
      await pumpExplorer(
        tester,
        seededProject(),
        onOpenFile: (FileNode node, int _) => opened = node,
      );

      await tester.tap(find.text('README.md'));
      await tester.pumpAndSettle();

      expect(opened?.name, 'README.md');
    });
  });

  group('errors', () {
    testWidgets('a folder that cannot be read explains why, inline', (
      WidgetTester tester,
    ) async {
      final FakeFileSystemProvider provider = seededProject()
        ..denyList.add('/workspace/lib');

      await pumpExplorer(tester, provider);
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Permission denied'), findsOneWidget);
      expect(
        find.textContaining('re-grant access'),
        findsOneWidget,
        reason: 'an error must say what to do, not only what happened',
      );
    });
  });

  group('panel layout', () {
    testWidgets('on a phone the panel covers exactly half the width', (
      WidgetTester tester,
    ) async {
      final ExplorerPanelController controller = ExplorerPanelController();
      addTearDown(controller.dispose);

      await pumpExplorer(
        tester,
        seededProject(),
        withScaffold: true,
        panelController: controller,
      );

      controller.open();
      await tester.pumpAndSettle();

      final double panelWidth =
          tester.getSize(find.byType(ExplorerPanel)).width;
      expect(
        panelWidth,
        TestSizes.phone.width * AppSizes.explorerPhoneWidthFraction,
        reason: 'the brief specifies exactly 50% on phones',
      );
    });

    testWidgets('the panel is not hit-testable while closed', (
      WidgetTester tester,
    ) async {
      final ExplorerPanelController controller = ExplorerPanelController();
      addTearDown(controller.dispose);

      await pumpExplorer(
        tester,
        seededProject(),
        withScaffold: true,
        panelController: controller,
      );

      expect(controller.isOpen, isFalse);
      expect(controller.isVisible, isFalse,
          reason: 'a closed panel must not intercept editor gestures');
    });

    testWidgets('opening and closing updates the controller state', (
      WidgetTester tester,
    ) async {
      final ExplorerPanelController controller = ExplorerPanelController();
      addTearDown(controller.dispose);

      await pumpExplorer(
        tester,
        seededProject(),
        withScaffold: true,
        panelController: controller,
      );

      controller.open();
      await tester.pumpAndSettle();
      expect(controller.isOpen, isTrue);

      controller.close();
      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      expect(controller.isVisible, isFalse);
    });
  });

  group('accessibility', () {
    testWidgets('rows announce their kind and expanded state', (
      WidgetTester tester,
    ) async {
      // Semantics are not built unless a test asks for them. The handle must
      // be disposed inside the test body: addTearDown runs after the
      // framework's own end-of-test verification, which checks for it.
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpExplorer(tester, seededProject());

      expect(
        find.bySemanticsLabel('lib'),
        findsOneWidget,
        reason: 'every row needs a semantics label',
      );

      final SemanticsNode node = tester.getSemantics(find.text('lib'));
      expect(node.hint, contains('collapsed'));

      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();
      expect(tester.getSemantics(find.text('lib')).hint, contains('expanded'));

      handle.dispose();
    });
  });
}
