/// The folder a Find in Folder search is confined to.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/services/search/search_scope.dart';

SearchScope scope(
  String relativePath, {
  String name = 'x',
  String id = '/w/x',
}) => SearchScope(
  rootIndex: 0,
  folderId: id,
  relativePath: relativePath,
  name: name,
);

void main() {
  group('label', () {
    test('a nested folder shows its path with a trailing slash', () {
      // The slash is what makes it read as a folder next to file names.
      expect(scope('DMND/music').label, 'DMND/music/');
    });

    test('a top-level folder shows its name', () {
      expect(scope('lib', name: 'lib').label, 'lib/');
    });

    test('the root itself falls back to its name', () {
      expect(scope('', name: 'Valar_Morghulis').label, 'Valar_Morghulis/');
    });
  });

  group('identity', () {
    test('two scopes on the same folder are equal', () {
      expect(scope('lib', id: '/w/lib'), scope('lib', id: '/w/lib'));
    });

    test('the same path in a different root is a different scope', () {
      const SearchScope a = SearchScope(
        rootIndex: 0,
        folderId: '/a',
        relativePath: 'lib',
        name: 'lib',
      );
      const SearchScope b = SearchScope(
        rootIndex: 1,
        folderId: '/a',
        relativePath: 'lib',
        name: 'lib',
      );
      expect(a, isNot(b));
    });
  });
}
