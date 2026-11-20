@Tags(['autoread'])
library;

// 0.2.1 slice 12: "Hide details after". The default stays 15; the choice
// is for the alert only, never for how long a held message is kept.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/ui/alert_minutes_dialog.dart';
import 'package:mmogo/autoread/ui/consent_details_copy.dart';
import 'package:mmogo/autoread/ui/reading_settings_section.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../logic/reading_fakes.dart';

const _kt = 'android/app/src/autoread/kotlin/app/mmogo/autoread';

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
  test('default is 15 and matches the signed copy; held window is untouched', () async {
    expect(kAlertMinutesDefault, kDetailsAlertMinutes);
    expect(kAlertMinutesChoices, [0, 5, 15, 30, 60]);
    expect(kAlertMinutesChoices, contains(kAlertMinutesDefault));
    expect((await _ctl(FakeReadingBridge()).state()).alertMinutes, 15);
    expect(kHeldWindow, const Duration(hours: 24));
  });

  test('controller stores a choice, refuses a number that is not offered', () async {
    final b = FakeReadingBridge();
    final c = _ctl(b);
    expect(await c.setAlertMinutes(30), isTrue);
    expect((await c.state()).alertMinutes, 30);
    expect(await c.setAlertMinutes(0), isTrue); // Never
    expect((await c.state()).alertMinutes, kAlertMinutesNever);
    expect(await c.setAlertMinutes(7), isFalse);
    expect(b.calls.where((x) => x.startsWith('setAlertMinutes')), ['setAlertMinutes:30', 'setAlertMinutes:0']);
    b.alertMinutes = 999; // an odd stored value reads back as 15
    expect((await c.state()).alertMinutes, 15);
  });

  test('Kotlin holds the same list and default, applies it to the alert only', () {
    final at = File('$_kt/AlertText.kt').readAsStringSync();
    expect(at, contains('DETAILS_MINUTES_CHOICES: List<Int> = listOf(0, 5, 15, 30, 60)'));
    expect(at, contains('DETAILS_MINUTES_DEFAULT = $kAlertMinutesDefault'));
    expect(at, contains('if (generic) heldWindowMs else cleanMinutes(detailsMinutes)'));
    final sw = File('$_kt/AutoReadSwitch.kt').readAsStringSync();
    expect(sw, contains('"alert_details_minutes"'));
    // the held store is not given the setting
    for (final f in ['HeldWindow.kt', 'HeldStore.kt']) {
      final p = File('$_kt/$f');
      if (p.existsSync()) expect(p.readAsStringSync(), isNot(contains('alertMinutes')));
    }
  });

  test('the preference is not in the backup', () {
    final src = Directory('lib/data/backup')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.readAsStringSync())
        .join();
    expect(src, isNot(contains('alert_details_minutes')));
    expect(src, isNot(contains('alertMinutes')));
  });

  test('words: plain, no dashes', () {
    for (final w in allAlertMinutesCopy()) {
      expect(w, isNot(contains('—')));
      expect(w, isNot(contains('–')));
    }
    expect(alertMinutesText(60), '1 hour');
    expect(alertMinutesText(5), '5 minutes');
    expect(alertMinutesText(0), 'Never');
  });

  testWidgets('row is hidden while alerts are Generic', (t) async {
    await _pump(t, _ctl(FakeReadingBridge()));
    expect(find.byKey(const Key('alertMinutesRow')), findsNothing);
  });

  testWidgets('row shows 15 minutes, the picker stores 30', (t) async {
    final b = FakeReadingBridge()..alertDetails = true;
    await _pump(t, _ctl(b));
    final row = find.byKey(const Key('alertMinutesRow'));
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.text('15 minutes')), findsOneWidget);
    await t.tap(row);
    await t.pumpAndSettle();
    for (final m in kAlertMinutesChoices) {
      expect(find.byKey(Key('alertMinutes-$m')), findsOneWidget);
    }
    expect(find.text(kAlertMinutesNote), findsOneWidget);
    await t.tap(find.byKey(const Key('alertMinutes-30')));
    await t.pumpAndSettle();
    expect(b.alertMinutes, 30);
    expect(find.descendant(of: row, matching: find.text('30 minutes')), findsOneWidget);
  });
}
