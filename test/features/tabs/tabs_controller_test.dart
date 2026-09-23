/// Tests for tab lifecycle, preview behaviour, dirty tracking and saving.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/data/models/open_tab.dart';
import 'package:pocket_code/data/repositories/history_repository.dart';
import 'package:pocket_code/data/repositories/support_storage.dart';
import 'package:pocket_code/features/history/application/history_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_controller.dart';
import 'package:pocket_code/features/tabs/application/tabs_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';

import '../../support/fake_file_system.dart';
import '../../support/harness.dart';

FakeFileSystemProvider seeded() {
  return FakeFileSystemProvider()
    ..seed(<String, String>{
      '/workspace/a.dart': 'void a() {}\n',
      '/workspace/b.dart': 'void b() {}\n',
      '/workspace/c.txt': 'plain text\n',
      '/workspace/crlf.txt': 'one\r\ntwo\r\n',
      '/workspace/README.md': '# Title\n',
    });
}

/// Builds a container with the workspace pinned, avoiding the folder picker.
///
/// [support] enables file history, which otherwise has nowhere to write.
Future<ProviderContainer> containerFor(
  FakeFileSystemProvider provider, {
  AppSettings settings = const AppSettings(),
  SupportStorage? support,
}) async {
  final repo = await fakeSettingsRepository();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repo),
      initialSettingsProvider.overrideWithValue(settings),
      supportStorageProvider.overrideWithValue(support),
      workspaceProvider.overrideWith(
        () => FixedWorkspaceController(workspaceFor(provider)),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SupportStorage supportStorage() {
  final FakeFileSystemProvider fs = FakeFileSystemProvider()
    ..seed(<String, String>{'/support/.keep': ''});
  return SupportStorage(provider: fs, rootId: '/support');
}

FileNode node(String path) => FileNode(
      id: path,
      name: path.split('/').last,
      displayPath: path,
    );

void main() {
  // The tabs controller creates re_editor controllers, which need a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('opening', () {
    test('opening a file adds a tab and makes it active', () async {
      final ProviderContainer c = await containerFor(seeded());
      await c.read(tabsProvider.notifier).open(node('/workspace/a.dart'), 0);

      final TabsState state = c.read(tabsProvider);
      expect(state.tabs.length, 1);
      expect(state.active?.node.name, 'a.dart');
      expect(state.active?.text, 'void a() {}\n');
      expect(state.active?.language.id, 'dart');
    });

    test('reopening an already-open file focuses it rather than duplicating',
        () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);

      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);

      expect(c.read(tabsProvider).tabs.length, 2);
      expect(c.read(tabsProvider).active?.node.name, 'a.dart');
    });

    test('a file that cannot be read reports a typed failure', () async {
      final ProviderContainer c = await containerFor(seeded());
      await c.read(tabsProvider.notifier).open(node('/workspace/ghost.dart'), 0);

      expect(c.read(tabsProvider).error, isNotNull);
      expect(c.read(tabsProvider).tabs, isEmpty);
    });

    test('line endings are detected and preserved on the tab', () async {
      final ProviderContainer c = await containerFor(seeded());
      await c.read(tabsProvider.notifier).open(node('/workspace/crlf.txt'), 0);

      expect(c.read(tabsProvider).active?.format.lineEnding.label, 'CRLF');
      expect(c.read(tabsProvider).active?.text, 'one\ntwo\n',
          reason: 'the buffer is always LF; the format remembers the rest');
    });
  });

  group('preview tabs', () {
    test('a preview tab is replaced by the next previewed file', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);

      await tabs.open(node('/workspace/a.dart'), 0);
      await tabs.open(node('/workspace/b.dart'), 0);

      expect(c.read(tabsProvider).tabs.length, 1,
          reason: 'single-clicking through a folder must not pile up tabs');
      expect(c.read(tabsProvider).active?.node.name, 'b.dart');
    });

    test('a pinned tab is not replaced', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);

      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0);

      expect(c.read(tabsProvider).tabs.length, 2);
    });

    test('editing a preview tab pins it', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);

      await tabs.open(node('/workspace/a.dart'), 0);
      expect(c.read(tabsProvider).active?.isPreview, isTrue);

      tabs.controllerFor(c.read(tabsProvider).active!).text = 'edited';
      await Future<void>.delayed(Duration.zero);

      expect(c.read(tabsProvider).active?.isPreview, isFalse,
          reason: 'the user invested in this file; do not discard it');
    });
  });

  group('dirty tracking', () {
    test('a freshly opened tab is clean', () async {
      final ProviderContainer c = await containerFor(seeded());
      await c.read(tabsProvider.notifier).open(node('/workspace/a.dart'), 0);
      expect(c.read(tabsProvider).active?.isDirty, isFalse);
    });

    test('editing marks it dirty', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);

      tabs.controllerFor(c.read(tabsProvider).active!).text = 'changed';
      await Future<void>.delayed(Duration.zero);

      expect(c.read(tabsProvider).active?.isDirty, isTrue);
    });

    test('typing then undoing back to the original leaves it clean', () async {
      // This is why dirtiness is derived from the text rather than a flag.
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);
      const String original = 'void a() {}\n';

      final controller = tabs.controllerFor(c.read(tabsProvider).active!);
      controller.text = 'changed';
      await Future<void>.delayed(Duration.zero);
      expect(c.read(tabsProvider).active?.isDirty, isTrue);

      controller.text = original;
      await Future<void>.delayed(Duration.zero);
      expect(c.read(tabsProvider).active?.isDirty, isFalse);
    });
  });

  group('saving', () {
    test('save writes the buffer to disk and clears dirty', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);

      tabs.controllerFor(c.read(tabsProvider).active!).text = 'void a() {}\nvoid b() {}\n';
      await Future<void>.delayed(Duration.zero);
      expect(await tabs.save(), isTrue);

      expect(
        provider.fs.file('/workspace/a.dart').readAsStringSync(),
        'void a() {}\nvoid b() {}\n',
      );
      expect(c.read(tabsProvider).active?.isDirty, isFalse);
    });

    test('saving a CRLF file writes CRLF back', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/crlf.txt'), 0);

      tabs.controllerFor(c.read(tabsProvider).active!).text = 'one\ntwo\nthree\n';
      await Future<void>.delayed(Duration.zero);
      await tabs.save();

      expect(
        provider.fs.file('/workspace/crlf.txt').readAsStringSync(),
        'one\r\ntwo\r\nthree\r\n',
        reason: 'editing one line must not rewrite every line ending',
      );
    });

    test('save all writes every dirty tab', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);

      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      tabs.controllerFor(c.read(tabsProvider).tabs[0]).text = 'A';
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      tabs.controllerFor(c.read(tabsProvider).tabs[1]).text = 'B';
      await Future<void>.delayed(Duration.zero);

      expect(await tabs.saveAll(), isTrue);
      // Both source files ended with a newline, so saving puts it back — the
      // final-newline state is part of the format we promise to preserve.
      expect(provider.fs.file('/workspace/a.dart').readAsStringSync(), 'A\n');
      expect(provider.fs.file('/workspace/b.dart').readAsStringSync(), 'B\n');
      expect(c.read(tabsProvider).anyDirty, isFalse);
    });
  });

  group('closing', () {
    test('closing a clean tab succeeds immediately', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);

      expect(tabs.close(0), isTrue);
      expect(c.read(tabsProvider).tabs, isEmpty);
    });

    test('closing a dirty tab asks first', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      tabs.controllerFor(c.read(tabsProvider).active!).text = 'changed';
      await Future<void>.delayed(Duration.zero);

      expect(tabs.close(0), isFalse,
          reason: 'false means the caller must prompt');
      expect(c.read(tabsProvider).tabs.length, 1);

      expect(tabs.close(0, force: true), isTrue);
      expect(c.read(tabsProvider).tabs, isEmpty);
    });

    test('closing the active tab activates its left neighbour', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      await tabs.open(node('/workspace/c.txt'), 0, preview: false);

      tabs.close(2);
      expect(c.read(tabsProvider).active?.node.name, 'b.dart');
    });

    test('close others keeps only the chosen tab', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      await tabs.open(node('/workspace/c.txt'), 0, preview: false);

      tabs.closeOthers(1);
      expect(c.read(tabsProvider).tabs.length, 1);
      expect(c.read(tabsProvider).tabs.single.node.name, 'b.dart');
    });

    test('close to the right leaves the earlier tabs alone', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      await tabs.open(node('/workspace/c.txt'), 0, preview: false);

      tabs.closeToTheRight(0);
      expect(c.read(tabsProvider).tabs.length, 1);
      expect(c.read(tabsProvider).tabs.single.node.name, 'a.dart');
    });

    test('close saved leaves dirty tabs open', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      tabs.controllerFor(c.read(tabsProvider).tabs[1]).text = 'dirty';
      await Future<void>.delayed(Duration.zero);

      tabs.closeSaved();
      expect(c.read(tabsProvider).tabs.length, 1);
      expect(c.read(tabsProvider).tabs.single.node.name, 'b.dart');
    });
  });

  group('reopen closed', () {
    test('reopens the most recently closed tab', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);

      tabs.close(1);
      expect(c.read(tabsProvider).tabs.length, 1);

      await tabs.reopenClosed();
      expect(c.read(tabsProvider).tabs.length, 2);
      expect(c.read(tabsProvider).active?.node.name, 'b.dart');
    });

    test('a deleted file is skipped rather than throwing', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      tabs.close(0);

      provider.fs.file('/workspace/a.dart').deleteSync();
      await tabs.reopenClosed();

      expect(c.read(tabsProvider).tabs, isEmpty);
    });
  });

  group('file history', () {
    test('an explicit save records what was about to be overwritten', () async {
      final FakeFileSystemProvider fs = seeded();
      final SupportStorage support = supportStorage();
      final ProviderContainer c = await containerFor(fs, support: support);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);

      tabs.controllerFor(c.read(tabsProvider).active!).text = 'edited';
      await tabs.save();

      final HistoryFolder? folder =
          await c.read(fileHistoryProvider).versionsFor(
                provider: fs,
                rootId: '/workspace',
                fileId: '/workspace/a.dart',
                name: 'a.dart',
                displayPath: '/workspace/a.dart',
              );
      expect(folder, isNotNull);
      expect(folder!.meta.versions, hasLength(1));
      expect(
        await c.read(fileHistoryProvider).contentOf(
              folder,
              folder.meta.versions.first,
            ),
        'void a() {}',
        reason: 'the snapshot is the buffer that was replaced, not the new '
            'one — and it is the buffer, so the trailing newline lives in '
            'TextFormat and is reapplied on save rather than stored twice',
      );
    });

    test('nothing is recorded when history is switched off', () async {
      final FakeFileSystemProvider fs = seeded();
      final SupportStorage support = supportStorage();
      final ProviderContainer c = await containerFor(
        fs,
        support: support,
        settings: const AppSettings(editor: EditorSettings(fileHistory: false)),
      );
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);
      tabs.controllerFor(c.read(tabsProvider).active!).text = 'edited';
      await tabs.save();

      expect(
        await c.read(fileHistoryProvider).versionsFor(
              provider: fs,
              rootId: '/workspace',
              fileId: '/workspace/a.dart',
              name: 'a.dart',
              displayPath: '/workspace/a.dart',
            ),
        isNull,
      );
    });

    test('saving is unaffected when there is nowhere to record', () async {
      // Support storage can be unavailable; the save must still land.
      final FakeFileSystemProvider fs = seeded();
      final ProviderContainer c = await containerFor(fs);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);
      tabs.controllerFor(c.read(tabsProvider).active!).text = 'edited';

      expect(await tabs.save(), isTrue);
      expect(fs.fs.file('/workspace/a.dart').readAsStringSync(), 'edited\n');
    });
  });

  group('hot exit', () {
    test('a recovered buffer lands in its tab and is marked dirty', () async {
      // This was a silent no-op: the key was built inside a single-quoted
      // string with escaped dollars, so it compared against the literal
      // "$rootIndex:$fileId" and never matched a tab. Every hot-exit restore
      // quietly did nothing.
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);

      tabs.restoreUnsavedBuffer(0, '/workspace/a.dart', 'void a() { recovered; }\n');

      final TabsState state = c.read(tabsProvider);
      expect(state.active?.text, 'void a() { recovered; }\n');
      expect(state.active?.isDirty, isTrue,
          reason: 'the recovered text differs from what is on disk');
      expect(state.active?.savedText, 'void a() {}\n',
          reason: 'the on-disk text is kept, so the change is still visible');
    });

    test('a buffer for a file that is not open is ignored', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0);

      tabs.restoreUnsavedBuffer(0, '/workspace/gone.dart', 'orphan');

      expect(c.read(tabsProvider).tabs.length, 1);
      expect(c.read(tabsProvider).active?.text, 'void a() {}\n');
    });
  });

  group('reordering', () {
    test('moving a tab keeps the same one active', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      await tabs.open(node('/workspace/b.dart'), 0, preview: false);
      await tabs.open(node('/workspace/c.txt'), 0, preview: false);
      tabs.setActive(0);

      tabs.reorder(0, 2);

      expect(
        c.read(tabsProvider).tabs.map((OpenTab t) => t.node.name).toList(),
        <String>['b.dart', 'c.txt', 'a.dart'],
      );
      expect(c.read(tabsProvider).active?.node.name, 'a.dart');
    });
  });

  group('external changes', () {
    test('a clean tab silently reloads', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);

      provider.fs.file('/workspace/a.dart').writeAsStringSync('changed on disk');
      await tabs.onExternalChange('/workspace/a.dart');

      expect(c.read(tabsProvider).active?.text, 'changed on disk');
      expect(c.read(tabsProvider).active?.externallyChanged, isFalse);
    });

    test('a dirty tab is flagged instead of being overwritten', () async {
      final FakeFileSystemProvider provider = seeded();
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);
      tabs.controllerFor(c.read(tabsProvider).active!).text = 'my edits';
      await Future<void>.delayed(Duration.zero);

      provider.fs.file('/workspace/a.dart').writeAsStringSync('their edits');
      await tabs.onExternalChange('/workspace/a.dart');

      expect(c.read(tabsProvider).active?.externallyChanged, isTrue);
      expect(c.read(tabsProvider).active?.text, 'my edits',
          reason: 'unsaved work must never be silently replaced');
    });
  });

  group('path updates after a move', () {
    test('a renamed file updates its tab', () async {
      final ProviderContainer c = await containerFor(seeded());
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/a.dart'), 0, preview: false);

      tabs.onPathChanged('/workspace/a.dart', '/workspace/renamed.dart');

      expect(c.read(tabsProvider).active?.node.name, 'renamed.dart');
      expect(c.read(tabsProvider).active?.node.id, '/workspace/renamed.dart');
    });

    test('a moved folder updates every tab beneath it', () async {
      final FakeFileSystemProvider provider = FakeFileSystemProvider()
        ..seed(<String, String>{
          '/workspace/src/one.dart': '1',
          '/workspace/src/two.dart': '2',
        });
      final ProviderContainer c = await containerFor(provider);
      final TabsController tabs = c.read(tabsProvider.notifier);
      await tabs.open(node('/workspace/src/one.dart'), 0, preview: false);
      await tabs.open(node('/workspace/src/two.dart'), 0, preview: false);

      tabs.onPathChanged('/workspace/src', '/workspace/lib');

      expect(
        c.read(tabsProvider).tabs.map((OpenTab t) => t.node.id).toList(),
        <String>['/workspace/lib/one.dart', '/workspace/lib/two.dart'],
      );
    });
  });
}
