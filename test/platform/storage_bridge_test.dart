// B12: the Dart side of the storage bridge, over a mocked MethodChannel, plus
// the fake's own behaviour and the static guard on openUrl callers.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_constants.dart';
import 'package:mmogo/platform/method_channel_storage_bridge.dart';
import 'package:mmogo/platform/storage_bridge.dart';

import '../support/fake_storage_bridge.dart';

typedef _Handler = Future<Object?>? Function(MethodCall call);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.mmogo/storage');
  late MethodChannelStorageBridge bridge;
  late List<MethodCall> seen;

  void mock(_Handler h) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      seen.add(call);
      return h(call);
    });
  }

  setUp(() {
    bridge = MethodChannelStorageBridge();
    seen = [];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> expectCode(Future<Object?> Function() call, StorageErrorCode code) async {
    await expectLater(
      call(),
      throwsA(isA<StorageException>().having((e) => e.code, 'code', code)),
    );
  }

  group('method_channel calls', () {
    test('pickFolder returns uri and name', () async {
      mock((_) async => {'uri': 'content://tree/1', 'name': 'Backups'});
      final f = await bridge.pickFolder();
      expect(f!.uri, 'content://tree/1');
      expect(f.name, 'Backups');
      expect(seen.single.method, 'pickFolder');
    });

    test('pickFolder cancelled (null reply) returns null', () async {
      mock((_) async => null);
      expect(await bridge.pickFolder(), isNull);
    });

    test('pickFolder cancelled (cancelled code) returns null', () async {
      mock((_) async => throw PlatformException(code: 'cancelled'));
      expect(await bridge.pickFolder(), isNull);
    });

    test('pickFolder malformed reply is io', () async {
      mock((_) async => {'name': 'x'});
      await expectCode(bridge.pickFolder, StorageErrorCode.io);
    });

    test('hasWriteGrant sends the uri and returns the bool', () async {
      mock((_) async => true);
      expect(await bridge.hasWriteGrant('content://tree/1'), isTrue);
      expect(seen.single.method, 'hasWriteGrant');
      expect(seen.single.arguments, {'treeUri': 'content://tree/1'});
    });

    test('hasWriteGrant null reply is false', () async {
      mock((_) async => null);
      expect(await bridge.hasWriteGrant('t'), isFalse);
    });

    test('granted-but-revoked folder: hasWriteGrant false, createFile grantLost', () async {
      mock((call) async {
        if (call.method == 'hasWriteGrant') return false;
        throw PlatformException(code: 'grantLost', message: 'folder access is gone');
      });
      expect(await bridge.hasWriteGrant('t'), isFalse);
      await expectCode(() => bridge.createFile('t', 'a.json', Uint8List(1)), StorageErrorCode.grantLost);
      await expectCode(() => bridge.listFiles('t'), StorageErrorCode.grantLost);
    });

    test('releaseGrant sends the uri', () async {
      mock((_) async => null);
      await bridge.releaseGrant('t');
      expect(seen.single.method, 'releaseGrant');
      expect(seen.single.arguments, {'treeUri': 't'});
    });

    test('createFile sends bytes and returns the authoritative uri', () async {
      mock((_) async => 'content://tree/1/doc/9');
      final uri = await bridge.createFile('t', 'a.json', Uint8List.fromList([1, 2, 3]));
      expect(uri, 'content://tree/1/doc/9');
      final args = seen.single.arguments as Map;
      expect(args['treeUri'], 't');
      expect(args['name'], 'a.json');
      expect(args['bytes'], Uint8List.fromList([1, 2, 3]));
    });

    test('createFile empty reply is io', () async {
      mock((_) async => null);
      await expectCode(() => bridge.createFile('t', 'a', Uint8List(0)), StorageErrorCode.io);
    });

    test('listFiles parses rows', () async {
      mock((_) async => [
            {'name': 'a.json', 'uri': 'u1', 'size': 10, 'lastModified': 1000},
            {'name': 'b.json', 'uri': 'u2'},
          ]);
      final files = await bridge.listFiles('t');
      expect(files.length, 2);
      expect(files[0].name, 'a.json');
      expect(files[0].uri, 'u1');
      expect(files[0].size, 10);
      expect(files[0].lastModified, DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true));
      expect(files[1].size, 0);
    });

    test('listFiles empty folder gives an empty list', () async {
      mock((_) async => <Object?>[]);
      expect(await bridge.listFiles('t'), isEmpty);
    });

    test('listFiles malformed row is io', () async {
      mock((_) async => [
            {'name': 5}
          ]);
      await expectCode(() => bridge.listFiles('t'), StorageErrorCode.io);
    });

    test('deleteFile sends the doc uri', () async {
      mock((_) async => null);
      await bridge.deleteFile('d');
      expect(seen.single.method, 'deleteFile');
      expect(seen.single.arguments, {'docUri': 'd'});
    });

    test('pickFile sends maxBytes and returns name and bytes', () async {
      mock((_) async => {'name': 'b.json', 'bytes': Uint8List.fromList([7, 8])});
      final f = await bridge.pickFile(maxBytes: 100);
      expect(f!.name, 'b.json');
      expect(f.bytes, Uint8List.fromList([7, 8]));
      expect(seen.single.arguments, {'maxBytes': 100});
    });

    test('picker cancelled: pickFile returns null (null and cancelled code)', () async {
      mock((_) async => null);
      expect(await bridge.pickFile(maxBytes: 1), isNull);
      mock((_) async => throw PlatformException(code: 'cancelled'));
      expect(await bridge.pickFile(maxBytes: 1), isNull);
    });

    test('pickFile without bytes is io', () async {
      mock((_) async => {'name': 'x'});
      await expectCode(() => bridge.pickFile(maxBytes: 1), StorageErrorCode.io);
    });

    test('openUrl passes an allowed constant and returns the bool', () async {
      mock((_) async => true);
      expect(await bridge.openUrl(AppConstants.siteUrl), isTrue);
      expect(seen.single.arguments, {'url': AppConstants.siteUrl});
    });

    test('openUrl null reply is false', () async {
      mock((_) async => null);
      expect(await bridge.openUrl(AppConstants.issuesUrl), isFalse);
    });

    test('openUrl refuses anything else without calling the channel', () async {
      mock((_) async => true);
      expect(await bridge.openUrl('https://example.com'), isFalse);
      expect(await bridge.openUrl('${AppConstants.siteUrl}x'), isFalse);
      expect(await bridge.openUrl(''), isFalse);
      expect(seen, isEmpty);
    });
  });

  group('method_channel_maps_platform_exception_codes', () {
    const wire = {
      'cancelled': StorageErrorCode.cancelled,
      'tooLarge': StorageErrorCode.tooLarge,
      'grantLost': StorageErrorCode.grantLost,
      'io': StorageErrorCode.io,
    };
    for (final e in wire.entries) {
      test('${e.key} maps to ${e.value.name} (non-picker call)', () async {
        mock((_) async => throw PlatformException(code: e.key, message: 'm'));
        await expectCode(() => bridge.deleteFile('d'), e.value);
      });
    }

    test('tooLarge from pickFile is thrown, not swallowed', () async {
      mock((_) async => throw PlatformException(code: 'tooLarge'));
      await expectCode(() => bridge.pickFile(maxBytes: 1), StorageErrorCode.tooLarge);
    });

    test('grantLost and io from pickFolder are thrown', () async {
      mock((_) async => throw PlatformException(code: 'grantLost'));
      await expectCode(bridge.pickFolder, StorageErrorCode.grantLost);
      mock((_) async => throw PlatformException(code: 'io'));
      await expectCode(bridge.pickFolder, StorageErrorCode.io);
    });

    test('unknown platform code maps to io and keeps the message', () async {
      mock((_) async => throw PlatformException(code: 'weird', message: 'boom'));
      await expectLater(
        bridge.deleteFile('d'),
        throwsA(isA<StorageException>()
            .having((e) => e.code, 'code', StorageErrorCode.io)
            .having((e) => e.message, 'message', 'boom')),
      );
    });

    test('missing plugin maps to io', () async {
      // No handler installed: the channel reports MissingPluginException.
      await expectCode(() => bridge.deleteFile('d'), StorageErrorCode.io);
    });

    test('every method maps a platform error (none leaks PlatformException)', () async {
      mock((_) async => throw PlatformException(code: 'io'));
      final calls = <Future<Object?> Function()>[
        () => bridge.hasWriteGrant('t'),
        () => bridge.releaseGrant('t'),
        () => bridge.createFile('t', 'n', Uint8List(0)),
        () => bridge.listFiles('t'),
        () => bridge.deleteFile('d'),
        () => bridge.pickFile(maxBytes: 1),
        () => bridge.openUrl(AppConstants.siteUrl),
      ];
      for (final c in calls) {
        await expectCode(c, StorageErrorCode.io);
      }
    });

    test('StorageErrorCode.fromWire', () {
      expect(StorageErrorCode.fromWire('tooLarge'), StorageErrorCode.tooLarge);
      expect(StorageErrorCode.fromWire(null), StorageErrorCode.io);
      expect(StorageErrorCode.fromWire('nope'), StorageErrorCode.io);
    });
  });

  group('fake_bridge_revoke_and_fail_modes', () {
    late FakeStorageBridge fake;
    const tree = 'content://tree/1';

    setUp(() {
      fake = FakeStorageBridge();
      fake.folderPicks.add(const PickedFolder(uri: tree, name: 'Backups'));
    });

    test('pick, write, list, delete round trip and call log', () async {
      final picked = await fake.pickFolder();
      expect(picked!.uri, tree);
      expect(await fake.hasWriteGrant(tree), isTrue);
      final uri = await fake.createFile(tree, 'a.json', Uint8List.fromList([1]));
      expect((await fake.listFiles(tree)).map((f) => f.name), ['a.json']);
      expect(fake.bytesOf(uri), Uint8List.fromList([1]));
      await fake.deleteFile(uri);
      expect(await fake.listFiles(tree), isEmpty);
      expect(fake.calls.first, 'pickFolder');
      expect(fake.calls, contains('createFile:a.json'));
    });

    test('never overwrites: a clashing name gets a new name and uri', () async {
      await fake.pickFolder();
      final u1 = await fake.createFile(tree, 'a.json', Uint8List.fromList([1]));
      final u2 = await fake.createFile(tree, 'a.json', Uint8List.fromList([2]));
      expect(u1, isNot(u2));
      expect(fake.bytesOf(u1), Uint8List.fromList([1]));
      expect((await fake.listFiles(tree)).map((f) => f.name).toSet().length, 2);
    });

    test('revoked grant: hasWriteGrant false, write and list throw grantLost', () async {
      await fake.pickFolder();
      fake.revokeGrant(tree);
      expect(await fake.hasWriteGrant(tree), isFalse);
      await expectCode(() => fake.createFile(tree, 'a.json', Uint8List(1)), StorageErrorCode.grantLost);
      await expectCode(() => fake.listFiles(tree), StorageErrorCode.grantLost);
    });

    test('released grant behaves like a revoked one; picking again restores it', () async {
      await fake.pickFolder();
      await fake.releaseGrant(tree);
      expect(await fake.hasWriteGrant(tree), isFalse);
      fake.folderPicks.add(const PickedFolder(uri: tree, name: 'Backups'));
      await fake.pickFolder();
      expect(await fake.hasWriteGrant(tree), isTrue);
    });

    test('failWrites throws io and stores nothing', () async {
      await fake.pickFolder();
      fake.failWrites = true;
      await expectCode(() => fake.createFile(tree, 'a.json', Uint8List(1)), StorageErrorCode.io);
      expect(await fake.listFiles(tree), isEmpty);
      fake.failWrites = false;
      await fake.createFile(tree, 'a.json', Uint8List(1));
      expect(await fake.listFiles(tree), hasLength(1));
    });

    test('picker cancelled and picker error', () async {
      expect(await fake.pickFolder(), isNotNull);
      expect(await fake.pickFolder(), isNull);
      expect(await fake.pickFile(maxBytes: 10), isNull);
      fake.nextPickError = const StorageException(StorageErrorCode.io);
      await expectCode(() => fake.pickFile(maxBytes: 10), StorageErrorCode.io);
      expect(await fake.pickFile(maxBytes: 10), isNull);
    });

    test('pickFile over the limit throws tooLarge', () async {
      fake.filePicks.add(PickedFile(name: 'big', bytes: Uint8List(11)));
      await expectCode(() => fake.pickFile(maxBytes: 10), StorageErrorCode.tooLarge);
    });

    test('openUrl records only the two constants', () async {
      expect(await fake.openUrl(AppConstants.siteUrl), isTrue);
      expect(await fake.openUrl(AppConstants.issuesUrl), isTrue);
      expect(await fake.openUrl('https://example.com'), isFalse);
      expect(fake.openedUrls, [AppConstants.siteUrl, AppConstants.issuesUrl]);
    });

    test('StorageBridge.instance is replaceable', () {
      final old = StorageBridge.instance;
      addTearDown(() => StorageBridge.instance = old);
      StorageBridge.instance = fake;
      expect(identical(StorageBridge.instance, fake), isTrue);
    });
  });

  test('open_url_called_only_with_constants (static scan of lib/)', () {
    final call = RegExp(r'\bopenUrl\s*\(([^)]*)\)');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll('\\', '/');
      if (!path.endsWith('.dart') || path.contains('lib/platform/')) continue;
      for (final m in call.allMatches(f.readAsStringSync())) {
        final arg = m.group(1)!.trim();
        if (arg != 'AppConstants.siteUrl' && arg != 'AppConstants.issuesUrl') bad.add('$path: openUrl($arg)');
      }
    }
    expect(bad, isEmpty);
  });

  test('Kotlin openUrl allowlist equals the Dart constants', () {
    final kt = File('android/app/src/main/kotlin/app/mmogo/StorageBridge.kt').readAsStringSync();
    expect(kt, contains('"${AppConstants.siteUrl}"'));
    expect(kt, contains('"${AppConstants.issuesUrl}"'));
    // "w" (write open) appears only inside createFile.
    final w = RegExp(r'"w"').allMatches(kt).length;
    expect(w, 1);
  });
}
