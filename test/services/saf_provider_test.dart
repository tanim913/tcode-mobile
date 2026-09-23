/// The SAF provider's translation layer.
///
/// The Kotlin side cannot run here, so the channel is mocked: what is under
/// test is the URI arithmetic and the mapping of platform errors onto the app's
/// own failures — which is where the bugs would be.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_code/core/errors/failures.dart';
import 'package:pocket_code/data/models/file_node.dart';
import 'package:pocket_code/services/filesystem/io/saf_file_system_provider.dart';

const String kTree = 'content://com.android.externalstorage.documents/tree/primary%3ACode';
const String kRoot =
    'content://com.android.externalstorage.documents/tree/primary%3ACode/document/primary%3ACode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('dev.tcode.mobile/saf');
  const SafFileSystemProvider provider =
      SafFileSystemProvider(rootName: 'Code');

  final List<MethodCall> calls = <MethodCall>[];

  void respond(Object? Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call);
      return handler(call);
    });
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('capabilities are declared honestly', () {
    test('no watching, and no absolute path', () {
      // SAF genuinely has neither. Claiming otherwise would make the explorer
      // offer Copy Path and a live refresh that silently never fire.
      expect(provider.capabilities.canWatch, isFalse);
      expect(provider.capabilities.canResolveAbsolutePath, isFalse);
      expect(provider.schemeId, 'saf');
    });

    test('watch emits nothing rather than throwing', () async {
      expect(await provider.watch(kRoot).toList(), isEmpty);
    });
  });

  group('identity helpers', () {
    test('childId appends to the document id, not the URI path', () {
      final String child = provider.childId(kRoot, 'main.dart');
      expect(child, endsWith('primary%3ACode%2Fmain.dart'),
          reason: 'the child name belongs inside the encoded document id');
    });

    test('parentOf walks back up one level', () {
      final String child = provider.childId(kRoot, 'lib');
      expect(provider.parentOf(child), kRoot);
    });

    test('parentOf returns null at the root', () {
      expect(provider.parentOf(kRoot), isNull,
          reason: 'the granted folder is the top; there is no parent to show');
    });

    test('nameOf reads the last segment of the document id', () {
      expect(provider.nameOf(provider.childId(kRoot, 'main.dart')), 'main.dart');
    });

    test('childId and nameOf round-trip', () {
      const String name = 'a b+c.dart';
      expect(provider.nameOf(provider.childId(kRoot, name)), name);
    });
  });

  group('listing', () {
    test('maps rows onto file and folder nodes', () async {
      respond((MethodCall call) => <Map<String, Object?>>[
            <String, Object?>{
              'uri': '$kRoot%2Flib',
              'name': 'lib',
              'isDirectory': true,
              'size': 0,
              'modified': 0,
            },
            <String, Object?>{
              'uri': '$kRoot%2Fmain.dart',
              'name': 'main.dart',
              'isDirectory': false,
              'size': 120,
              'modified': 1700000000000,
            },
          ]);

      final List<FileSystemNode> nodes = await provider.list(kRoot);

      expect(nodes, hasLength(2));
      expect(nodes.first, isA<FolderNode>());
      final FileNode file = nodes.last as FileNode;
      expect(file.name, 'main.dart');
      expect(file.size, 120);
      expect(file.modified, isNotNull);
      expect(file.parentId, kRoot,
          reason: 'the tree needs the parent to build its rows');
    });

    test('a zero timestamp becomes null, not 1970', () async {
      respond((MethodCall call) => <Map<String, Object?>>[
            <String, Object?>{
              'uri': '$kRoot%2Fx',
              'name': 'x',
              'isDirectory': false,
              'size': 0,
              'modified': 0,
            },
          ]);

      final List<FileSystemNode> nodes = await provider.list(kRoot);
      expect(nodes.single.modified, isNull);
    });
  });

  group('error mapping', () {
    test('a permission error becomes PermissionDeniedFailure', () async {
      respond((MethodCall call) =>
          throw PlatformException(code: 'permission', message: 'denied'));

      expect(
        () => provider.list(kRoot),
        throwsA(isA<PermissionDeniedFailure>()),
      );
    });

    test('not_found becomes NotFoundFailure', () async {
      respond((MethodCall call) =>
          throw PlatformException(code: 'not_found', message: 'gone'));

      expect(() => provider.stat(kRoot), throwsA(isA<NotFoundFailure>()));
    });

    test('an unknown code keeps the platform message', () async {
      respond((MethodCall call) =>
          throw PlatformException(code: 'io', message: 'disk on fire'));

      await expectLater(
        provider.list(kRoot),
        throwsA(
          isA<UnknownFailure>().having(
            (UnknownFailure f) => f.hint,
            'hint',
            'disk on fire',
          ),
        ),
      );
    });

    test('a missing plugin is reported as unsupported, not a crash', () async {
      // This is a web or desktop build reaching the Android-only channel.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);

      expect(
        () => provider.list(kRoot),
        throwsA(isA<UnsupportedOperationFailure>()),
      );
    });
  });

  group('writing', () {
    test('createFile refuses to clobber an existing name', () async {
      respond((MethodCall call) =>
          call.method == 'exists' ? true : throw StateError('unreachable'));

      expect(
        () => provider.createFile(kRoot, 'main.dart'),
        throwsA(isA<AlreadyExistsFailure>()),
        reason: 'creating over a file would destroy it',
      );
    });

    test('writeBytes sends the bytes to the channel', () async {
      respond((MethodCall call) => null);

      await provider.writeBytes(kRoot, Uint8List.fromList(<int>[1, 2, 3]));

      final MethodCall write =
          calls.firstWhere((MethodCall c) => c.method == 'writeBytes');
      final Map<Object?, Object?> args =
          write.arguments as Map<Object?, Object?>;
      expect(args['uri'], kRoot);
      expect(args['bytes'], <int>[1, 2, 3]);
    });
  });
}
