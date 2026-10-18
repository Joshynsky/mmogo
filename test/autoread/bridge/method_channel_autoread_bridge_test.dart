import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _id2 = 'fedcba9876543210fedcba9876543210';
const _channel = MethodChannel('app.mmogo/autoread');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Object? Function(MethodCall)? reply;
  var genCalls = 0;
  late MethodChannelAutoReadBridge bridge;

  setUp(() {
    calls = [];
    reply = null;
    genCalls = 0;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      final r = reply;
      return r == null ? null : r(call);
    });
    bridge = MethodChannelAutoReadBridge(generation: () async {
      genCalls++;
      return 7;
    });
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<void> push(String method, Object? args) async {
    await messenger.handlePlatformMessage(
      'app.mmogo/autoread',
      const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
      (_) {},
    );
  }

  test('peekHeld sends method and args, parses the result', () async {
    reply = (_) => {'id': _id, 'body': 'hello', 'receivedAtMs': 1000};
    final m = await bridge.peekHeld(_id);
    expect(calls.single.method, 'peekHeld');
    expect(calls.single.arguments, {'id': _id});
    expect(m!.id, _id);
    expect(m.body, 'hello');
    expect(m.heldAt, DateTime.fromMillisecondsSinceEpoch(1000));
    expect(m.toString().contains('hello'), isFalse);
  });

  test('peekHeld null result is null', () async {
    expect(await bridge.peekHeld(_id), isNull);
  });

  test('peekHeld rejects a mismatched id', () async {
    reply = (_) => {'id': _id2, 'body': 'x', 'receivedAtMs': 1};
    expect(await bridge.peekHeld(_id), isNull);
  });

  test('peekHeld rejects wrong field types', () async {
    for (final bad in <Object?>[
      {'id': _id, 'body': 5, 'receivedAtMs': 1},
      {'id': _id, 'body': 'x', 'receivedAtMs': '1'},
      {'id': 3, 'body': 'x', 'receivedAtMs': 1},
      {'id': _id, 'receivedAtMs': 1},
      'not a map',
    ]) {
      reply = (_) => bad;
      expect(await bridge.peekHeld(_id), isNull, reason: '$bad');
    }
  });

  test('claim, release, ackHeld send exact calls', () async {
    reply = (c) => c.method == 'claim' ? true : null;
    expect(await bridge.claim(_id), isTrue);
    await bridge.release(_id);
    await bridge.ackHeld(_id, generation: 42);
    expect(calls.map((c) => c.method).toList(), ['claim', 'release', 'ackHeld']);
    expect(calls[0].arguments, {'id': _id});
    expect(calls[1].arguments, {'id': _id});
    expect(calls[2].arguments, {'id': _id, 'generation': 42});
  });

  test('claim false result and non-bool result are false', () async {
    reply = (_) => false;
    expect(await bridge.claim(_id), isFalse);
    reply = (_) => 'yes';
    expect(await bridge.claim(_id), isFalse);
  });

  test('invalid ids make no channel call', () async {
    for (final bad in ['', 'abc', _id.toUpperCase(), '${_id}0', 'g' * 32]) {
      expect(await bridge.peekHeld(bad), isNull);
      expect(await bridge.claim(bad), isFalse);
      await bridge.release(bad);
      await bridge.ackHeld(bad, generation: 1);
    }
    expect(calls, isEmpty);
  });

  test('listHeldIds sends no args and drops invalid ids', () async {
    reply = (_) => [_id, 'bad', 5, _id.toUpperCase(), _id2];
    expect(await bridge.listHeldIds(), [_id, _id2]);
    expect(calls.single.method, 'listHeldIds');
    expect(calls.single.arguments, isNull);
    reply = (_) => 'nope';
    expect(await bridge.listHeldIds(), isEmpty);
  });

  test('readGeneration uses the injected function, no channel call', () async {
    expect(await bridge.readGeneration(), 7);
    expect(genCalls, 1);
    expect(calls, isEmpty);
  });

  test('PlatformException becomes a code-only exception', () async {
    reply = (_) => throw PlatformException(code: 'failed', message: 'SECRET-BODY-TEXT', details: 'SECRET-BODY-TEXT');
    try {
      await bridge.claim(_id);
      fail('should throw');
    } on AutoReadBridgeException catch (e) {
      expect(e.code, 'failed');
      expect(e.toString(), 'AutoReadBridgeException(failed)');
      expect(e.toString().contains('SECRET'), isFalse);
    }
  });

  test('MissingPluginException becomes not_available', () async {
    messenger.setMockMethodCallHandler(_channel, null);
    // no mock handler: the engine answers missing plugin
    await expectLater(
      bridge.listHeldIds(),
      throwsA(isA<AutoReadBridgeException>().having((e) => e.code, 'code', 'not_available')),
    );
  });

  test('onTapped valid id reaches tapped; invalid or missing is dropped', () async {
    final got = <String>[];
    final sub = bridge.tapped.listen(got.add);
    await push('onTapped', {'id': _id});
    await push('onTapped', {'id': 'bad'});
    await push('onTapped', {'id': 5});
    await push('onTapped', <String, Object?>{});
    await push('onTapped', null);
    await push('somethingElse', {'id': _id2});
    await pumpEventQueue();
    expect(got, [_id]);
    await sub.cancel();
  });

  test('taps with no listener are not buffered', () async {
    await push('onTapped', {'id': _id});
    await pumpEventQueue();
    final got = <String>[];
    final sub = bridge.tapped.listen(got.add);
    await pumpEventQueue();
    expect(got, isEmpty);
    await sub.cancel();
  });

  test('getState parses and rejects malformed', () async {
    reply = (_) => {'enabled': true, 'smsGranted': false, 'notifGranted': true, 'heldCount': 3};
    final s = await bridge.getState();
    expect(calls.single.method, 'getState');
    expect(calls.single.arguments, isNull);
    expect([s.enabled, s.smsGranted, s.notifGranted, s.heldCount], [true, false, true, 3]);
    for (final bad in <Object?>[
      null,
      'x',
      {'enabled': true, 'smsGranted': false, 'notifGranted': true},
      {'enabled': 1, 'smsGranted': false, 'notifGranted': true, 'heldCount': 3},
      {'enabled': true, 'smsGranted': false, 'notifGranted': true, 'heldCount': '3'},
    ]) {
      reply = (_) => bad;
      await expectLater(
        bridge.getState(),
        throwsA(isA<AutoReadBridgeException>().having((e) => e.code, 'code', 'failed')),
        reason: '$bad',
      );
    }
  });

  test('requestPermissions parses and rejects malformed', () async {
    reply = (_) => {'smsGranted': true, 'notifGranted': false};
    final p = await bridge.requestPermissions();
    expect(calls.single.method, 'requestPermissions');
    expect(calls.single.arguments, isNull);
    expect([p.smsGranted, p.notifGranted], [true, false]);
    for (final bad in <Object?>[null, {'smsGranted': true}, {'smsGranted': 1, 'notifGranted': true}]) {
      reply = (_) => bad;
      await expectLater(
        bridge.requestPermissions(),
        throwsA(isA<AutoReadBridgeException>().having((e) => e.code, 'code', 'failed')),
      );
    }
  });

  test('setEnabled sends the map and returns the state; non-bool fails', () async {
    reply = (_) => true;
    expect(await bridge.setEnabled(true), isTrue);
    reply = (_) => false;
    expect(await bridge.setEnabled(false), isFalse);
    expect(calls[0].method, 'setEnabled');
    expect(calls[0].arguments, {'enabled': true});
    expect(calls[1].arguments, {'enabled': false});
    reply = (_) => null;
    await expectLater(
      bridge.setEnabled(true),
      throwsA(isA<AutoReadBridgeException>().having((e) => e.code, 'code', 'failed')),
    );
  });

  test('takeLaunchId returns a valid id or null', () async {
    reply = (_) => _id;
    expect(await bridge.takeLaunchId(), _id);
    expect(calls.single.method, 'takeLaunchId');
    expect(calls.single.arguments, isNull);
    reply = (_) => 'bad';
    expect(await bridge.takeLaunchId(), isNull);
    reply = (_) => null;
    expect(await bridge.takeLaunchId(), isNull);
  });

  test('deleteAllHeld and openAppSettings send bare calls', () async {
    await bridge.deleteAllHeld();
    await bridge.openAppSettings();
    expect(calls.map((c) => c.method).toList(), ['deleteAllHeld', 'openAppSettings']);
    expect(calls.every((c) => c.arguments == null), isTrue);
  });
}
