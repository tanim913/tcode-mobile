import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/data/models/app_settings.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/features/explorer/application/tree_state.dart';

FileNode file(String name, {DateTime? modified}) => FileNode(
      id: '/w/$name',
      name: name,
      displayPath: '/w/$name',
      modified: modified,
    );

FolderNode folder(String name, {DateTime? modified}) => FolderNode(
      id: '/w/$name',
      name: name,
      displayPath: '/w/$name',
      modified: modified,
    );

List<String> names(List<FileSystemNode> nodes) =>
    nodes.map((FileSystemNode n) => n.name).toList();

void main() {
  group('natural comparison', () {
    test('numbers sort numerically, not lexically', () {
      expect(TreeOrdering.compareNatural('item2', 'item10'), lessThan(0),
          reason: 'item2 must come before item10, not after');
    });

    test('leading zeros do not change the order', () {
      expect(TreeOrdering.compareNatural('v007', 'v8'), lessThan(0));
    });

    test('comparison is case insensitive', () {
      expect(TreeOrdering.compareNatural('Apple', 'apple'), 0);
      expect(TreeOrdering.compareNatural('apple', 'Banana'), lessThan(0));
    });

    test('a prefix sorts before the longer name', () {
      expect(TreeOrdering.compareNatural('main', 'main_test'), lessThan(0));
    });
  });

  group('sorting', () {
    test('folders always come before files', () {
      final List<FileSystemNode> sorted = TreeOrdering.sort(
        <FileSystemNode>[file('a.txt'), folder('zebra'), file('b.txt')],
        ExplorerSortOrder.name,
      );
      expect(names(sorted), <String>['zebra', 'a.txt', 'b.txt']);
    });

    test('by name uses natural ordering', () {
      final List<FileSystemNode> sorted = TreeOrdering.sort(
        <FileSystemNode>[file('f10.dart'), file('f2.dart'), file('f1.dart')],
        ExplorerSortOrder.name,
      );
      expect(names(sorted), <String>['f1.dart', 'f2.dart', 'f10.dart']);
    });

    test('by type groups extensions, then sorts by name', () {
      final List<FileSystemNode> sorted = TreeOrdering.sort(
        <FileSystemNode>[file('b.dart'), file('a.txt'), file('a.dart')],
        ExplorerSortOrder.type,
      );
      expect(names(sorted), <String>['a.dart', 'b.dart', 'a.txt']);
    });

    test('by modified puts the most recent first', () {
      final List<FileSystemNode> sorted = TreeOrdering.sort(
        <FileSystemNode>[
          file('old.txt', modified: DateTime(2020)),
          file('new.txt', modified: DateTime(2026)),
          file('mid.txt', modified: DateTime(2023)),
        ],
        ExplorerSortOrder.modified,
      );
      expect(names(sorted), <String>['new.txt', 'mid.txt', 'old.txt']);
    });

    test('sorting does not mutate the input list', () {
      final List<FileSystemNode> input = <FileSystemNode>[
        file('b.txt'),
        file('a.txt'),
      ];
      TreeOrdering.sort(input, ExplorerSortOrder.name);
      expect(names(input), <String>['b.txt', 'a.txt']);
    });
  });

  group('filtering', () {
    test('hidden files are removed unless requested', () {
      final List<FileSystemNode> nodes = <FileSystemNode>[
        file('.env'),
        file('main.dart'),
      ];
      expect(
        names(TreeOrdering.filter(nodes,
            showHidden: false, excludePatterns: const <String>[])),
        <String>['main.dart'],
      );
      expect(
        names(TreeOrdering.filter(nodes,
                showHidden: true, excludePatterns: const <String>[]))
            .length,
        2,
      );
    });

    test('default excludes remove build noise', () {
      final List<FileSystemNode> nodes = <FileSystemNode>[
        folder('node_modules'),
        folder('build'),
        folder('lib'),
      ];
      expect(
        names(TreeOrdering.filter(
          nodes,
          showHidden: true,
          excludePatterns: AppSettings.defaultExcludes,
        )),
        <String>['lib'],
      );
    });
  });

  group('exclude patterns', () {
    test('exact names match', () {
      expect(TreeOrdering.isExcluded('build', <String>['build']), isTrue);
      expect(TreeOrdering.isExcluded('builder', <String>['build']), isFalse,
          reason: 'an exact pattern must not match a longer name');
    });

    test('star globs match', () {
      expect(TreeOrdering.isExcluded('debug.log', <String>['*.log']), isTrue);
      expect(TreeOrdering.isExcluded('log.txt', <String>['*.log']), isFalse);
    });

    test('a star in the middle works', () {
      expect(TreeOrdering.isExcluded('test_abc_gen.dart',
          <String>['test_*_gen.dart']), isTrue);
    });

    test('regex metacharacters in a pattern are treated literally', () {
      // Without escaping, "a.txt" would match "axtxt" too.
      expect(TreeOrdering.isExcluded('axtxt', <String>['a.txt*']), isFalse);
      expect(TreeOrdering.isExcluded('a.txt', <String>['a.txt*']), isTrue);
    });

    test('an empty pattern excludes nothing', () {
      expect(TreeOrdering.isExcluded('anything', <String>['']), isFalse);
    });
  });
}
