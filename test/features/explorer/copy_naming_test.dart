import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/features/explorer/application/copy_naming.dart';

void main() {
  group('splitting a name', () {
    test('a normal file splits at the last dot', () {
      expect(CopyNaming.split('main.dart'), ('main', '.dart'));
    });

    test('a double extension keeps only the last part as the extension', () {
      expect(CopyNaming.split('archive.tar.gz'), ('archive.tar', '.gz'));
    });

    test('a dotfile has no extension', () {
      // ' copy.gitignore' would be wrong and would change the file's identity.
      expect(CopyNaming.split('.gitignore'), ('.gitignore', ''));
    });

    test('an extensionless name has no extension', () {
      expect(CopyNaming.split('Makefile'), ('Makefile', ''));
    });

    test('a trailing dot is treated as the extension boundary', () {
      expect(CopyNaming.split('weird.'), ('weird', '.'));
    });
  });

  group('first copy', () {
    test('inserts "copy" before the extension', () {
      expect(
        CopyNaming.nextCopyName('main.dart', <String>{'main.dart'}),
        'main copy.dart',
      );
    });

    test('appends to a dotfile rather than prefixing it', () {
      expect(
        CopyNaming.nextCopyName('.gitignore', <String>{'.gitignore'}),
        '.gitignore copy',
      );
    });

    test('appends to an extensionless name', () {
      expect(
        CopyNaming.nextCopyName('Makefile', <String>{'Makefile'}),
        'Makefile copy',
      );
    });

    test('folders behave like extensionless files', () {
      expect(
        CopyNaming.nextCopyName('screens', <String>{'screens'}),
        'screens copy',
      );
    });

    test('a double extension keeps both parts', () {
      expect(
        CopyNaming.nextCopyName('archive.tar.gz', <String>{'archive.tar.gz'}),
        'archive.tar copy.gz',
      );
    });
  });

  group('numbered copies', () {
    test('the second copy is numbered 2, not 1', () {
      expect(
        CopyNaming.nextCopyName(
          'main.dart',
          <String>{'main.dart', 'main copy.dart'},
        ),
        'main copy 2.dart',
      );
    });

    test('numbering continues past gaps without reusing a taken name', () {
      expect(
        CopyNaming.nextCopyName('main.dart', <String>{
          'main.dart',
          'main copy.dart',
          'main copy 2.dart',
          'main copy 3.dart',
        }),
        'main copy 4.dart',
      );
    });

    test('duplicating a copy does not stack the word "copy"', () {
      // VS Code gives "main copy 2.dart" here, not "main copy copy.dart".
      expect(
        CopyNaming.nextCopyName(
          'main copy.dart',
          <String>{'main.dart', 'main copy.dart'},
        ),
        'main copy 2.dart',
      );
    });

    test('duplicating a numbered copy continues the same series', () {
      expect(
        CopyNaming.nextCopyName(
          'main copy 2.dart',
          <String>{'main.dart', 'main copy.dart', 'main copy 2.dart'},
        ),
        'main copy 3.dart',
      );
    });

    test('a name merely containing "copy" is not treated as a suffix', () {
      // "copyright.txt" must not become "right copy.txt".
      expect(
        CopyNaming.nextCopyName('copyright.txt', <String>{'copyright.txt'}),
        'copyright copy.txt',
      );
    });
  });

  group('keep both', () {
    test('a free name is used unchanged', () {
      expect(
        CopyNaming.uniqueName('main.dart', <String>{'other.dart'}),
        'main.dart',
        reason: 'Keep Both must not rename a file that does not collide',
      );
    });

    test('a taken name gets the copy treatment', () {
      expect(
        CopyNaming.uniqueName('main.dart', <String>{'main.dart'}),
        'main copy.dart',
      );
    });
  });

  group('never returns a taken name', () {
    test('across a range of awkward inputs', () {
      const List<String> names = <String>[
        'main.dart',
        '.env',
        'Makefile',
        'a.tar.gz',
        'copy.txt',
        'x copy.txt',
      ];
      for (final String name in names) {
        final Set<String> taken = <String>{name, '$name copy'};
        final String result = CopyNaming.nextCopyName(name, taken);
        expect(
          taken.contains(result),
          isFalse,
          reason: 'returning a taken name for "$name" would overwrite a file',
        );
      }
    });
  });
}
