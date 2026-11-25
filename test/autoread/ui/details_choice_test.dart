@Tags(['autoread'])
library;

// 0.2.0 row 16 (J1 B1 to B4): a new consent writes BOTH keys; an old consent-v2
// phone with the details key absent reads Generic and sees the one-time card;
// the card ends when the key is written; the details alert times out after
// 15 minutes in Kotlin (pinned from the Dart side too); the new words are
// tagged DRAFT and carry none of the forbidden claims.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/ui/consent_details_copy.dart';
import 'package:mmogo/autoread/ui/consent_sheet.dart';
import 'package:mmogo/autoread/ui/reading_settings_section.dart';
import 'package:mmogo/autoread/ui/settings_autoread_copy.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../logic/reading_fakes.dart';

const _kt = 'android/app/src/autoread/kotlin/app/mmogo/autoread';

Future<FakeReadingPrefs> _pump(WidgetTester t, FakeReadingBridge b, {bool consent = false}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(390, 1400);
  addTearDown(t.view.reset);
  final p = FakeReadingPrefs();
  if (consent) {
    p.data[kReadingConsentKey] = kReadingConsentVersion;
    b.kotlinConsent = kReadingConsentVersion;
  }
  final c = ReadingController(bridge: b, store: FakeGenerationStore(), prefs: p);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.theme,
    home: Scaffold(body: ListView(children: [ReadingSettingsSection(controller: c)])),
  ));
  await t.pumpAndSettle();
  b.calls.clear();
  return p;
}

void main() {
  group('fresh consent writes both keys (B1)', () {
    testWidgets('Allow with all three ticked: Parse and details written ON', (t) async {
      final b = FakeReadingBridge();
      await _pump(t, b);
      await t.tap(find.byKey(const Key('readingSwitch')));
      await t.pumpAndSettle();
      expect(find.text(kConsentDetailsLabel), findsOneWidget);
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.pumpAndSettle();
      expect(b.calls, containsAllInOrder(['setConsent:$kReadingConsentVersion', 'setParseOn:true', 'setAlertDetails:true']));
      expect(b.parseOn, isTrue);
      expect(b.alertDetails, isTrue);
      expect(b.alertDetailsAbsent, isFalse);
    });

    testWidgets('details unticked: the key is still written, as false', (t) async {
      final b = FakeReadingBridge();
      await _pump(t, b);
      await t.tap(find.byKey(const Key('readingSwitch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentDetailsSwitch')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.pumpAndSettle();
      expect(b.calls, contains('setAlertDetails:false'));
      expect(b.alertDetails, isFalse);
      expect(b.alertDetailsAbsent, isFalse);
    });

    testWidgets('the sheet pre-ticks details, and greys it while Read is off', (t) async {
      final b = FakeReadingBridge();
      await _pump(t, b);
      await t.tap(find.byKey(const Key('readingSwitch')));
      await t.pumpAndSettle();
      final sw = find.descendant(of: find.byKey(const Key('consentDetailsSwitch')), matching: find.byType(Switch));
      expect(t.widget<Switch>(sw).value, isTrue);
      await t.tap(find.byKey(const Key('consentReadSwitch')));
      await t.pumpAndSettle();
      expect(t.widget<Switch>(sw).onChanged, isNull);
      expect(t.widget<Switch>(sw).value, isFalse);
    });

    test('ConsentChoice defaults details ON', () {
      expect(const ConsentChoice(parse: false).details, isTrue);
    });
  });

  group('old consent-v2 phone, key absent (B1, B4)', () {
    test('absent reads Generic and asks for the choice only with current consent', () async {
      final p = FakeReadingPrefs();
      final old = FakeReadingBridge()
        ..alertDetailsAbsent = true
        ..kotlinConsent = kReadingConsentVersion;
      final s = await ReadingController(bridge: old, store: FakeGenerationStore(), prefs: p).state();
      expect(s.alertDetails, isFalse);
      expect(s.detailsChoiceNeeded, isTrue);
      final fresh = FakeReadingBridge()..alertDetailsAbsent = true; // no consent
      expect((await ReadingController(bridge: fresh, store: FakeGenerationStore(), prefs: p).state()).detailsChoiceNeeded, isFalse);
      expect((await ReadingController(bridge: FakeReadingBridge(), store: FakeGenerationStore(), prefs: p).state()).detailsChoiceNeeded,
          isFalse);
    });

    testWidgets('the card shows, states the lock-screen limit, and Show details writes the key and ends it', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true)..alertDetailsAbsent = true;
      await _pump(t, b, consent: true);
      expect(find.text(kUpgradeCardTitle), findsOneWidget);
      expect(find.textContaining('the lock screen can show details later unless Android is set to hide sensitive content'), findsOneWidget);
      expect(find.textContaining('always generic'), findsNothing);
      await t.tap(find.byKey(const Key('detailsCardYes')));
      await t.pumpAndSettle();
      expect(b.calls, contains('setAlertDetails:true'));
      expect(b.alertDetails, isTrue);
      expect(find.text(kUpgradeCardTitle), findsNothing);
    });

    testWidgets('Keep generic also writes the key; the card never returns on the next look', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true)..alertDetailsAbsent = true;
      await _pump(t, b, consent: true);
      await t.tap(find.byKey(const Key('detailsCardNo')));
      await t.pumpAndSettle();
      expect(b.calls, contains('setAlertDetails:false'));
      expect(b.alertDetails, isFalse);
      expect(b.alertDetailsAbsent, isFalse);
      expect(find.text(kUpgradeCardTitle), findsNothing);
      // A second Settings visit (a fresh section over the same stored key).
      await _pump(t, b, consent: true);
      expect(find.text(kUpgradeCardTitle), findsNothing);
    });

    testWidgets('a failed write keeps the card (the key is still absent)', (t) async {
      final b = _StuckBridge(enabled: true, smsGranted: true, notifGranted: true)..alertDetailsAbsent = true;
      await _pump(t, b, consent: true);
      await t.tap(find.byKey(const Key('detailsCardYes')));
      await t.pumpAndSettle();
      expect(find.text(kUpgradeCardTitle), findsOneWidget);
    });

    testWidgets('no card when the key is already there', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true);
      await _pump(t, b, consent: true);
      expect(find.text(kUpgradeCardTitle), findsNothing);
    });
  });

  group('Parse row while Read is off (F6, 0.2.2: greyed and shown off)', () {
    testWidgets('stored ON shows OFF, greyed', (t) async {
      final b = FakeReadingBridge(parseOn: true);
      await _pump(t, b, consent: true);
      final sw = find.descendant(of: find.byKey(const Key('parseSwitch')), matching: find.byType(Switch));
      expect(t.widget<Switch>(sw).value, isFalse);
      expect(t.widget<Switch>(sw).onChanged, isNull);
      expect(b.parseOn, isTrue, reason: 'display only: the stored choice is kept');
    });
  });

  group('Kotlin pins read from Dart (B3, B1)', () {
    final alertText = File('$_kt/AlertText.kt').readAsStringSync();
    final notifier = File('$_kt/Notifier.kt').readAsStringSync();

    test('the details timeout is the same number as the copy says', () {
      final m = RegExp(r'DETAILS_TIMEOUT_MS: Long = (\d+)L \* 60L \* 1000L').firstMatch(alertText);
      expect(m, isNotNull);
      expect(int.parse(m!.group(1)!), kDetailsAlertMinutes);
    });

    test('the timeout is chosen by whether the alert is generic; the held window is not used directly', () {
      expect(notifier, contains('setTimeoutAfter(AlertText.timeoutMs(shown.generic, HeldWindow.WINDOW_MS, AutoReadSwitch.alertMinutes(context)))'));
      expect(notifier, isNot(contains('setTimeoutAfter(HeldWindow.WINDOW_MS)')));
    });

    test('the Generic fallback is untouched (J1 B1)', () {
      expect(alertText, contains('const val DEFAULT_SHOW_DETAILS = false'));
      final sw = File('$_kt/AutoReadSwitch.kt').readAsStringSync();
      expect(sw, contains('getBoolean(KEY_PARSE, false)'));
      expect(sw, contains('KEY_ALERT_DETAILS, AlertText.DEFAULT_SHOW_DETAILS)'));
    });
  });

  group('the words', () {
    test('every const in the new copy file carries a DRAFT tag on the line above', () {
      final lines = File('lib/autoread/ui/consent_details_copy.dart').readAsLinesSync();
      var n = 0;
      for (var i = 0; i < lines.length; i++) {
        if (RegExp(r'^(const|String|List)\b').hasMatch(lines[i])) {
          n++;
          final above = i == 0 ? '' : lines[i - 1];
          expect(above.contains('SIGNED') || above.contains('DRAFT'), isTrue, reason: lines[i]);
        }
      }
      expect(n, greaterThanOrEqualTo(8));
    });

    test('no forbidden claim, no dash-style punctuation, lock-screen wording as decided', () {
      final all = [...allConsentDetailsCopy(), kConsentNotification];
      for (final s in all) {
        final low = s.toLowerCase();
        expect(low.contains('no internet permission'), isFalse, reason: s);
        expect(low.contains('nothing leaves'), isFalse, reason: s);
        expect(low.contains('always generic'), isFalse, reason: s);
        expect(low.contains('text-free'), isFalse, reason: s);
        expect(s.contains(String.fromCharCode(0x2014)) || s.contains(String.fromCharCode(0x2013)), isFalse, reason: s);
        expect(low.contains('record'), isFalse, reason: s);
      }
      expect(kLockScreenSentence.contains('generic when the phone is locked as the message arrives'), isTrue);
      expect(kLockScreenSentence.contains('the lock screen can show details later unless Android is set to hide sensitive content'), isTrue);
      expect(kConsentNotification, contains(kLockScreenSentence));
      expect(kUpgradeCardBody, contains(kLockScreenSentence));
      expect(kConsentDetailsDesc, contains(kLockScreenSentence));
    });

    test('no alert text carries a code, a phone number or a balance (Kotlin check is in kotlin_selfcheck)', () {
      expect(File('tool/kotlin_selfcheck/AlertTextSelfCheck.kt').readAsStringSync(), contains('No code, phone number, balance or fee'));
    });

    test('P-002: no comment in the touched Dart files uses the word record, none names the pipeline', () {
      for (final f in [
        'lib/autoread/ui/consent_details_copy.dart',
        'lib/autoread/ui/details_upgrade_card.dart',
        'lib/autoread/ui/consent_sheet.dart',
        'lib/autoread/ui/reading_settings_section.dart',
      ]) {
        for (final l in File(f).readAsLinesSync()) {
          final c = l.trimLeft();
          if (c.startsWith('//')) {
            expect(RegExp(r'\brecord', caseSensitive: false).hasMatch(c), isFalse, reason: '$f: $c');
            expect(c.contains('_pipeline'), isFalse, reason: '$f: $c');
          }
        }
      }
    });
  });
}

class _StuckBridge extends FakeReadingBridge {
  _StuckBridge({super.enabled, super.smsGranted, super.notifGranted});

  @override
  Future<bool> setAlertDetails(bool on) async => alertDetails; // Kotlin kept the old value, key still absent
}
