// 0.2.2 item 2 slice B-ARR, the channel side: Kotlin's pushed `onArrived` (no argument) reaches `arrived`, is not
// buffered without a listener and never reaches `tapped`; `cancelAlert` sends only a valid id and never throws.
// The fake bridge mirrors both for the repository tests.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';

const _id = '0123456789abcdef0123456789abcdef';
const _channel = MethodChannel('app.mmogo/autoread');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  Object? Function(MethodCall)? reply;
  late MethodChannelAutoReadBridge bridge;

  setUp(() {
    calls = [];
    reply = null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      final r = reply;
      return r == null ? null : r(call);
    });
    bridge = MethodChannelAutoReadBridge(generation: () async => 7);
  });

  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  Future<void> push(String method, Object? args) => messenger.handlePlatformMessage(
        'app.mmogo/autoread',
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) {},
      );

  test('onArrived reaches arrived once per push, whatever its arguments; never tapped', () async {
    var arrived = 0;
    final taps = <String>[];
    final s1 = bridge.arrived.listen((_) => arrived++);
    final s2 = bridge.tapped.listen(taps.add);
    await push('onArrived', null);
    await push('onArrived', {'id': _id});
    await pumpEventQueue();
    expect(arrived, 2);
    expect(taps, isEmpty);
    await s1.cancel();
    await s2.cancel();
  });

  test('arrivals with no listener are not buffered', () async {
    await push('onArrived', null);
    await pumpEventQueue();
    var arrived = 0;
    final s = bridge.arrived.listen((_) => arrived++);
    await pumpEventQueue();
    expect(arrived, 0);
    await s.cancel();
  });

  test('cancelAlert sends the id; an invalid id sends nothing', () async {
    await bridge.cancelAlert(_id);
    await bridge.cancelAlert('bad');
    expect(calls.map((c) => c.method), ['cancelAlert']);
    expect(calls.single.arguments, {'id': _id});
  });

  test('cancelAlert never throws (platform error, older platform side without the call)', () async {
    reply = (_) => throw PlatformException(code: 'failed');
    await expectLater(bridge.cancelAlert(_id), completes);
    messenger.setMockMethodCallHandler(_channel, null); // no handler: MissingPluginException
    await expectLater(bridge.cancelAlert(_id), completes);
  });

  test('the fake: pushArrived reaches arrived; cancelAlert is listed apart from calls, valid ids only', () async {
    final fake = FakeAutoReadBridge(now: DateTime.now);
    var arrived = 0;
    final s = fake.arrived.listen((_) => arrived++);
    fake.pushArrived();
    await pumpEventQueue();
    await fake.cancelAlert(_id);
    await fake.cancelAlert('bad');
    expect(arrived, 1);
    expect(fake.cancelledAlerts, [_id]);
    expect(fake.calls, isEmpty);
    await s.cancel();
  });
}
