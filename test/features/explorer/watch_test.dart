/// The explorer's file-watcher subscription.
///
/// Built long ago on the provider interface and never listened to until now, so
/// what matters here is that it subscribes only to visible folders, coalesces
/// bursts, and never leaks a subscription.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/app/providers.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/features/explorer/application/tree_controller.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/file_system_provider.dart';

import '../../support/fake_file_system.dart';
import '../../support/harness.dart';

FakeFileSystemProvider seeded({bool canWatch = true}) {
  return FakeFileSystemProvider()
    ..canWatch = canWatch
    ..seed(<String, String>{
      '/workspace/lib/main.dart': 'void main() {}',
      '/workspace/README.md': '# hi',
    });
}

Future<ProviderContainer> pumpTree(FakeFileSystemProvider provider) async {
  final repo = await fakeSettingsRepository();
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
  container.listen(treeProvider, (TreeState? _, TreeState _) {});
  // Let the deferred root load finish.
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

TreeRow rowFor(ProviderContainer c, String name) =>
    c.read(treeProvider).rows.firstWhere((TreeRow r) => r.node.name == name);

void main() {
  test('watches the root once it is listed', () async {
    final FakeFileSystemProvider provider = seeded();
    await pumpTree(provider);

    expect(provider.watcherCount, 1,
        reason: 'the root is visible from the start');
  });

  test('a provider that cannot watch is never subscribed to', () async {
    // SAF and the browser are both in this position; the tree must fall back
    // to refresh rather than holding a dead subscription.
    final FakeFileSystemProvider provider = seeded(canWatch: false);
    await pumpTree(provider);

    expect(provider.watcherCount, 0);
  });

  test('expanding a folder watches it, collapsing stops', () async {
    final FakeFileSystemProvider provider = seeded();
    final ProviderContainer c = await pumpTree(provider);

    await c.read(treeProvider.notifier).toggle(rowFor(c, 'lib'));
    expect(provider.watcherCount, 2, reason: 'root plus the expanded folder');

    await c.read(treeProvider.notifier).toggle(rowFor(c, 'lib'));
    expect(provider.watcherCount, 1,
        reason: 'a collapsed folder is not visible, so nothing must watch it');
  });

  test('collapse all releases every watcher but the roots', () async {
    final FakeFileSystemProvider provider = seeded();
    final ProviderContainer c = await pumpTree(provider);

    await c.read(treeProvider.notifier).toggle(rowFor(c, 'lib'));
    expect(provider.watcherCount, 2);

    c.read(treeProvider.notifier).collapseAll();
    expect(provider.watcherCount, 1);
  });

  test('a change event re-reads the folder', () async {
    final FakeFileSystemProvider provider = seeded();
    final ProviderContainer c = await pumpTree(provider);

    expect(
      c.read(treeProvider).rows.map((TreeRow r) => r.node.name),
      isNot(contains('added.txt')),
    );

    // Another app writes into the folder.
    provider.fs.file('/workspace/added.txt').writeAsStringSync('new');
    provider.emitChange(
      '/workspace',
      const FileChangeEvent(kind: FileChangeKind.created, id: '/workspace/added.txt'),
    );

    // Past the debounce, plus a beat for the listing.
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(
      c.read(treeProvider).rows.map((TreeRow r) => r.node.name),
      contains('added.txt'),
      reason: 'the watcher exists precisely so this does not need a manual refresh',
    );
  });

  test('a burst of events causes one re-read, not one each', () async {
    final FakeFileSystemProvider provider = seeded();
    await pumpTree(provider);
    provider.listCalls = 0;

    for (int i = 0; i < 5; i++) {
      provider.emitChange(
        '/workspace',
        const FileChangeEvent(kind: FileChangeKind.modified, id: '/workspace/x'),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(provider.listCalls, 1,
        reason: 'one save can emit several events; listing per event thrashes');
  });

  test('closing the workspace releases every watcher', () async {
    final FakeFileSystemProvider provider = seeded();
    final ProviderContainer c = await pumpTree(provider);
    await c.read(treeProvider.notifier).toggle(rowFor(c, 'lib'));
    expect(provider.watcherCount, 2);

    c.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(provider.watcherCount, 0,
        reason: 'a disposed tree must not keep file handles open');
  });
}
