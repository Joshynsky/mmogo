@Tags(['autoread'])
library;

// 0.2.0 S10: the "What alerts show" row. The default must stay Generic until the
// Judge/Security note J1 is signed; a flip is stored through the bridge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/ui/reading_settings_section.dart';
import 'package:mmogo/autoread/ui/settings_autoread_copy.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../logic/reading_fakes.dart';

ReadingController _ctl(FakeReadingBridge b) =>
    ReadingController(bridge: b, store: FakeGenerationStore(), prefs: FakeReadingPrefs());

Future<void> _pump(WidgetTester t, ReadingController c) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(390, 900);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.theme,
    home: Scaffold(body: ListView(children: [ReadingSettingsSection(controller: c)])),
  ));
  await t.pumpAndSettle();
}

void main() {
  test('DEFAULT is Generic everywhere (binding until J1 is signed)', () async {
    expect(kAlertDetailsDefault, isFalse);
    expect(const AutoReadState(enabled: false, smsGranted: false, notifGranted: false, heldCount: 0).alertDetails, isFalse);
    expect(ReadingState.unavailable.alertDetails, isFalse);
    expect((await _ctl(FakeReadingBridge()).state()).alertDetails, isFalse);
  });

  test('controller stores the choice and reads it back', () async {
    final b = FakeReadingBridge();
    final c = _ctl(b);
    expect(await c.setAlertDetails(true), isTrue);
    expect((await c.state()).alertDetails, isTrue);
    expect(await c.setAlertDetails(false), isTrue);
    expect((await c.state()).alertDetails, isFalse);
    expect(b.calls, containsAllInOrder(['setAlertDetails:true', 'setAlertDetails:false']));
  });

  testWidgets('row shows Generic by default, the dialog flips to Show details', (t) async {
    final b = FakeReadingBridge();
    await _pump(t, _ctl(b));
    final row = find.byKey(const Key('alertsRow'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(kAlertsLabel)), findsOneWidget);
    expect(find.descendant(of: row, matching: find.text(kAlertsGeneric)), findsOneWidget);
    // no allow-pop-up switch (PM answer 7)
    expect(find.textContaining('pop-up', findRichText: true), findsNothing);

    await t.tap(row);
    await t.pumpAndSettle();
    expect(find.text(kAlertsLockNote), findsOneWidget);
    await t.tap(find.byKey(const Key('alertsDetails')));
    await t.pumpAndSettle();
    expect(b.alertDetails, isTrue);
    expect(find.descendant(of: row, matching: find.text(kAlertsDetails)), findsOneWidget);

    await t.tap(row);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertsGeneric')));
    await t.pumpAndSettle();
    expect(b.alertDetails, isFalse);
    expect(find.descendant(of: row, matching: find.text(kAlertsGeneric)), findsOneWidget);
  });

  testWidgets('a failed store leaves the row as it was', (t) async {
    final b = _StuckBridge();
    await _pump(t, _ctl(b));
    await t.tap(find.byKey(const Key('alertsRow')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('alertsDetails')));
    await t.pumpAndSettle();
    final row = find.byKey(const Key('alertsRow'));
    expect(find.descendant(of: row, matching: find.text(kAlertsGeneric)), findsOneWidget);
  });
}

class _StuckBridge extends FakeReadingBridge {
  @override
  Future<bool> setAlertDetails(bool on) async => false; // Kotlin kept the old value
}
