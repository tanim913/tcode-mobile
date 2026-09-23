/// Which folder becomes the workspace.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/workspace/application/workspace_controller.dart';
import 'package:pocket_code/services/filesystem/provider_factory.dart';

import '../../support/fake_file_system.dart';

void main() {
  ProviderContainer containerFor() {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  test('openFolder adopts exactly the folder it is given', () async {
    final FakeFileSystemProvider fs = FakeFileSystemProvider()
      ..seed(<String, String>{
        '/projects/samples/README.md': '# samples',
        '/projects/other/README.md': '# other',
      });
    final ProviderContainer c = containerFor();

    c.read(workspaceProvider.notifier).openFolder(
          PickedRoot(
            provider: fs,
            rootId: '/projects/other',
            displayName: 'other',
          ),
        );

    final OpenWorkspace? open = c.read(workspaceProvider);
    expect(open, isNotNull);
    expect(open!.roots, hasLength(1));
    expect(open.roots.single.root.rootId, '/projects/other');
    expect(open.displayName, 'other');
  });

  test('opening a second folder replaces the first, it does not add to it',
      () async {
    // The repository download bug: the second download appeared to bring the
    // first one back, because the folder being opened was the parent holding
    // every downloaded repository rather than the one just downloaded.
    final FakeFileSystemProvider fs = FakeFileSystemProvider()
      ..seed(<String, String>{
        '/projects/samples/README.md': '# samples',
        '/projects/other/README.md': '# other',
      });
    final ProviderContainer c = containerFor();
    final WorkspaceController workspace = c.read(workspaceProvider.notifier);

    workspace.openFolder(
      PickedRoot(provider: fs, rootId: '/projects/samples', displayName: 'samples'),
    );
    workspace.openFolder(
      PickedRoot(provider: fs, rootId: '/projects/other', displayName: 'other'),
    );

    final OpenWorkspace open = c.read(workspaceProvider)!;
    expect(open.roots, hasLength(1), reason: 'a download is not multi-root');
    expect(open.roots.single.root.rootId, '/projects/other');
    expect(open.isMultiRoot, isFalse);
  });
}
