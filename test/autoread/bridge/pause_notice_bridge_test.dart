@Tags(['autoread'])
library;

// 0.2.2 item 2 slice B-PAUSE: the Dart side of the pinned paused notice's own channel. show sends the three texts and
// answers Kotlin's bool; cancel sends no argument; every failure is swallowed (false / nothing).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/pause_notice_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(kPauseNoticeChannel);
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  void answer(Object? Function(MethodCall c) f) => messenger.setMockMethodCallHandler(channel, (c) async {
        calls.add(c);
        return f(c);
      });

  test('the channel name is the Kotlin one', () {
    expect(kPauseNoticeChannel, 'app.mmogo/pause_notice');
  });

  test('show sends title, resume and channel name; true only when Kotlin says true', () async {
    answer((_) => true);
    final b = MethodChannelPauseNoticeBridge();
    expect(await b.show(title: 'T', resume: 'R', channelName: 'C'), isTrue);
    expect(calls.single.method, 'show');
    expect(calls.single.arguments, {'title': 'T', 'resume': 'R', 'channelName': 'C'});
    answer((_) => false);
    expect(await b.show(title: 'T', resume: 'R', channelName: 'C'), isFalse);
    answer((_) => 'odd');
    expect(await b.show(title: 'T', resume: 'R', channelName: 'C'), isFalse);
  });

  test('cancel sends no argument', () async {
    answer((_) => null);
    await MethodChannelPauseNoticeBridge().cancel();
    expect(calls.single.method, 'cancel');
    expect(calls.single.arguments, isNull);
  });

  test('failures are swallowed: no handler (standard build / no engine) and a platform error', () async {
    final b = MethodChannelPauseNoticeBridge();
    expect(await b.show(title: 'T', resume: 'R', channelName: 'C'), isFalse); // MissingPluginException
    await b.cancel();
    answer((_) => throw PlatformException(code: 'x'));
    expect(await b.show(title: 'T', resume: 'R', channelName: 'C'), isFalse);
    await b.cancel();
  });
}
