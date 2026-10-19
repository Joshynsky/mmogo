import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';
import 'package:mmogo/autoread/ui/t1_test_host.dart';

class FakeControls implements T1Controls {
  AutoReadState state = const AutoReadState(
      enabled: false, smsGranted: true, notifGranted: true, heldCount: 0);
  bool grantOnRequest = true;
  String? launchId;
  List<String> held = [];
  Object? failWith;
  final calls = <String>[];
  final tap = StreamController<String>.broadcast();

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<AutoReadState> getState() async {
    calls.add('getState');
    return state;
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    calls.add('setEnabled:$enabled');
    _maybeFail();
    state = AutoReadState(
        enabled: enabled,
        smsGranted: state.smsGranted,
        notifGranted: state.notifGranted,
        heldCount: state.heldCount);
    return enabled;
  }

  @override
  Future<AutoReadPermissions> requestPermissions() async {
    calls.add('requestPermissions');
    _maybeFail();
    state = AutoReadState(
        enabled: state.enabled,
        smsGranted: grantOnRequest,
        notifGranted: state.notifGranted,
        heldCount: state.heldCount);
    return AutoReadPermissions(smsGranted: grantOnRequest, notifGranted: true);
  }

  @override
  Future<String?> takeLaunchId() async => launchId;
  @override
  Stream<String> get tapped => tap.stream;
  @override
  Future<List<String>> listHeldIds() async => held;
  @override
  Future<void> deleteAllHeld() async {
    calls.add('deleteAllHeld');
    _maybeFail();
    held = [];
  }

  @override
  Future<void> openAppSettings() async {
    calls.add('openAppSettings');
    _maybeFail();
  }
}

const _id = 'abcdef0123456789abcdef0123456789';

Widget _app(FakeControls c, GlobalKey<NavigatorState> key,
    {double scale = 1.0, ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    navigatorKey: key,
    themeMode: mode,
    darkTheme: ThemeData.dark(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: T1TestHost(
          controls: c, navigatorKey: key, child: child ?? const SizedBox.shrink()),
    ),
    home: const Scaffold(body: Text('home page')),
  );
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('T1'));
  await t.pumpAndSettle();
}

void main() {
  late FakeControls c;
  late GlobalKey<NavigatorState> key;
  setUp(() {
    c = FakeControls();
    key = GlobalKey<NavigatorState>();
  });

  testWidgets('corner button present, >= 44x44, opens the screen', (t) async {
    await t.pumpWidget(_app(c, key));
    await t.pumpAndSettle();
    expect(find.text('home page'), findsOneWidget);
    final size = t.getSize(find.ancestor(
        of: find.text('T1'), matching: find.byType(SizedBox)).first);
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(find.bySemanticsLabel('Auto-read test screen'), findsOneWidget);
    await _open(t);
    expect(find.text('Auto-read test build'), findsOneWidget);
    expect(
        find.text(
            'Temporary screen for testing on this phone. It is removed before release.'),
        findsOneWidget);
    expect(find.text('No tap yet'), findsOneWidget);
  });

  testWidgets('status lines: off / not allowed / count', (t) async {
    c.state = const AutoReadState(
        enabled: false, smsGranted: false, notifGranted: false, heldCount: 3);
    await t.pumpWidget(_app(c, key));
    await _open(t);
    expect(find.text('Read is off'), findsOneWidget);
    expect(find.text('SMS permission: not allowed'), findsOneWidget);
    expect(find.text('Notifications: not allowed'), findsOneWidget);
    expect(find.text('3 waiting'), findsOneWidget);
  });

  testWidgets('status lines: on / allowed', (t) async {
    c.state = const AutoReadState(
        enabled: true, smsGranted: true, notifGranted: true, heldCount: 0);
    await t.pumpWidget(_app(c, key));
    await _open(t);
    expect(find.text('Read is on'), findsOneWidget);
    expect(find.text('SMS permission: allowed'), findsOneWidget);
    expect(find.text('Notifications: allowed'), findsOneWidget);
    expect(find.text('0 waiting'), findsOneWidget);
  });

  testWidgets('switch ON with SMS not allowed asks first, then enables', (t) async {
    c.state = const AutoReadState(
        enabled: false, smsGranted: false, notifGranted: true, heldCount: 0);
    await t.pumpWidget(_app(c, key));
    await _open(t);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    final i = c.calls.indexOf('requestPermissions');
    expect(i, greaterThanOrEqualTo(0));
    expect(c.calls.indexOf('setEnabled:true'), greaterThan(i));
    expect(find.text('Read is on'), findsOneWidget);
  });

  testWidgets('denied permission leaves it off with a plain line', (t) async {
    c.state = const AutoReadState(
        enabled: false, smsGranted: false, notifGranted: true, heldCount: 0);
    c.grantOnRequest = false;
    await t.pumpWidget(_app(c, key));
    await _open(t);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(c.calls, contains('requestPermissions'));
    expect(c.calls, isNot(contains('setEnabled:true')));
    expect(find.text('SMS permission is not allowed, so Read stays off.'),
        findsOneWidget);
    expect(find.text('Read is off'), findsOneWidget);
  });

  testWidgets('switch OFF calls setEnabled(false); buttons call the controls',
      (t) async {
    c.state = const AutoReadState(
        enabled: true, smsGranted: true, notifGranted: true, heldCount: 1);
    await t.pumpWidget(_app(c, key));
    await _open(t);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(c.calls, contains('setEnabled:false'));
    await t.ensureVisible(find.text('Allow permissions'));
    await t.tap(find.text('Allow permissions'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Open app settings'));
    await t.tap(find.text('Open app settings'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Delete held messages'));
    await t.tap(find.text('Delete held messages'));
    await t.pumpAndSettle();
    expect(c.calls, containsAll(['requestPermissions', 'openAppSettings', 'deleteAllHeld']));
  });

  testWidgets('launch id opens the screen once, shows last six + held yes',
      (t) async {
    c.launchId = _id;
    c.held = [_id];
    await t.pumpWidget(_app(c, key));
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsOneWidget);
    expect(
        find.text('Opened from a notification, id ends …456789. Message still held: yes'),
        findsOneWidget);
  });

  testWidgets('held no when the id is gone', (t) async {
    c.launchId = _id;
    await t.pumpWidget(_app(c, key));
    await t.pumpAndSettle();
    expect(
        find.text('Opened from a notification, id ends …456789. Message still held: no'),
        findsOneWidget);
  });

  testWidgets('a pushed tap opens it; the same id twice opens once', (t) async {
    c.held = [_id];
    await t.pumpWidget(_app(c, key));
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsNothing);
    c.tap.add(_id);
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsOneWidget);
    // Close it, then the same id again must not reopen.
    key.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsNothing);
    c.tap.add(_id);
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsNothing);
  });

  testWidgets('same id twice while open pushes one route', (t) async {
    await t.pumpWidget(_app(c, key));
    await t.pumpAndSettle();
    c.tap.add(_id);
    c.tap.add(_id);
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsOneWidget);
    key.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text('Auto-read test build'), findsNothing);
    expect(find.text('home page'), findsOneWidget);
  });

  test('the controls interface has no body access', () {
    final dynamic d = FakeControls();
    expect(() => d.peekHeld('x'), throwsNoSuchMethodError);
    expect(() => d.claim('x'), throwsNoSuchMethodError);
  });

  testWidgets('errors show the code only', (t) async {
    await t.pumpWidget(_app(c, key));
    await _open(t);
    c.failWith = const AutoReadBridgeException('permission');
    await t.ensureVisible(find.text('Open app settings'));
    await t.tap(find.text('Open app settings'));
    await t.pumpAndSettle();
    expect(find.text('That did not work (permission)'), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('text scale 1.6 at 360 px, $mode: no overflow', (t) async {
      t.view.physicalSize = const Size(360, 640);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      c.launchId = _id;
      c.held = [_id];
      c.failWith = null;
      await t.pumpWidget(_app(c, key, scale: 1.6, mode: mode));
      await t.pumpAndSettle();
      expect(find.text('Auto-read test build'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test('t1HostEnabled: all four combinations', () {
    expect(t1HostEnabled(true, true), isTrue);
    expect(t1HostEnabled(true, false), isFalse);
    expect(t1HostEnabled(false, true), isFalse);
    expect(t1HostEnabled(false, false), isFalse);
  });
}
