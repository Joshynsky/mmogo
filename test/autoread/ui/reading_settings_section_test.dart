@Tags(['autoread'])
library;

import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/ui/consent_sheet.dart';
import 'package:mmogo/autoread/ui/reading_settings_section.dart';
import 'package:mmogo/autoread/ui/settings_autoread_copy.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../logic/reading_fakes.dart';

class _Rig {
  _Rig({bool consent = false, FakeReadingBridge? bridge})
      : b = bridge ?? FakeReadingBridge(),
        p = FakeReadingPrefs(),
        s = FakeGenerationStore() {
    if (consent) {
      p.data[kReadingConsentKey] = kReadingConsentVersion;
      b.kotlinConsent = kReadingConsentVersion;
    }
    c = ReadingController(bridge: b, store: s, prefs: p);
  }
  final FakeReadingBridge b;
  final FakeReadingPrefs p;
  final FakeGenerationStore s;
  late final ReadingController c;
}

void _size(WidgetTester t, double w, [double h = 900]) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, h);
  addTearDown(t.view.reset);
}

Future<void> _pump(WidgetTester t, _Rig r, {double w = 390, double scale = 1.0}) async {
  _size(t, w);
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.theme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(body: ListView(children: [ReadingSettingsSection(controller: r.c)])),
  ));
  await t.pumpAndSettle();
  r.b.calls.clear(); // the first state read is not what the tests look at
}

final _switch = find.byKey(const Key('readingSwitch'));
final _readSwitch = find.descendant(of: _switch, matching: find.byType(Switch));
final _parseRow = find.byKey(const Key('parseSwitch'));
final _parseSwitch = find.descendant(of: _parseRow, matching: find.byType(Switch));
final _settingsAutostart = find.byKey(const Key('settingsAutostart'));
final _fix = find.byKey(const Key('readingFixRow'));
final _deleteHeld = find.byKey(const Key('readingDeleteHeld'));
final _helpRow = find.byKey(const Key('readingHelpRow'));

void main() {
  testWidgets('off state: switch with a plain status, no fix row', (t) async {
    final r = _Rig();
    await _pump(t, r);
    expect(find.text(kReadLabel), findsOneWidget);
    expect(find.text(kReadStatusOff), findsOneWidget);
    expect(t.widget<Switch>(_readSwitch).value, isFalse);
    expect(_fix, findsNothing);
  });

  testWidgets('first turn-on shows the consent sheet BEFORE any system dialog', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(find.text(kConsentTitle), findsOneWidget);
    expect(find.text(kConsentReadDesc), findsOneWidget);
    expect(r.b.calls, isEmpty, reason: 'no permission request before Agree');
    expect(r.p.data, isEmpty);
  });

  testWidgets('Not now changes nothing: no consent stored, no calls, still off', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('consentNotNow')));
    await t.pumpAndSettle();
    expect(find.text(kConsentTitle), findsNothing);
    expect(r.b.calls, isEmpty);
    expect(r.p.data, isEmpty);
    expect(r.b.enabled, isFalse);
    expect(find.text(kReadStatusOff), findsOneWidget);
  });

  testWidgets('Allow stores consent, then permissions, then on; consent is not asked twice', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('consentAllow')));
    await t.pumpAndSettle();
    expect(r.p.data[kReadingConsentKey], kReadingConsentVersion);
    expect(r.b.calls, containsAllInOrder(['requestPermissions', 'setEnabled:true']));
    expect(r.b.enabled, isTrue);
    expect(find.text(kReadStatusOn), findsOneWidget);
    // Off, then on again: no sheet this time.
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(r.b.enabled, isFalse);
    r.b.calls.clear();
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(find.text(kConsentTitle), findsNothing);
    expect(r.b.enabled, isTrue);
  });

  testWidgets('a denied permission leaves Read off and says why', (t) async {
    final r = _Rig(consent: true, bridge: FakeReadingBridge()..grantSms = false);
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(r.b.enabled, isFalse);
    expect(find.text(kReadDeniedSms), findsOneWidget);
    expect(t.widget<Switch>(_readSwitch).value, isFalse);
  });

  testWidgets('turning off keeps waiting items and shows no error', (t) async {
    final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 2));
    r.p.data[pendingKey(1)] = 'x';
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(r.b.enabled, isFalse);
    expect(r.b.heldCount, 2);
    expect(r.s.bumps, 0);
    expect(r.p.data.keys.where((k) => k.startsWith('autoread_pending_v1.')).length, 1);
    expect(find.text(kReadStillOn), findsNothing);
  });

  group('capture-fix row', () {
    testWidgets('absent when off, absent when on and healthy', (t) async {
      await _pump(t, _Rig(consent: true));
      expect(_fix, findsNothing);
      await _pump(t, _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true)));
      expect(_fix, findsNothing);
    });

    testWidgets('present when on and a permission is missing, names which', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: true));
      await _pump(t, r);
      expect(_fix, findsOneWidget);
      expect(find.text(kFixLabel), findsOneWidget);
      expect(find.text(kFixSms), findsOneWidget);
    });

    testWidgets('tap runs turn-on again; fixed means the row goes', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: true));
      await _pump(t, r);
      await t.tap(_fix);
      await t.pumpAndSettle();
      expect(r.b.calls, contains('requestPermissions'));
      expect(_fix, findsNothing);
    });

    testWidgets('still blocked: the restricted-settings help opens', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: true)..grantSms = false;
      final r = _Rig(consent: true, bridge: b);
      await _pump(t, r);
      await t.tap(_fix);
      await t.pumpAndSettle();
      expect(find.text(kHelpIntro), findsOneWidget);
      await t.tap(find.byKey(const Key('helpOpenSettings')));
      await t.pumpAndSettle();
      expect(b.calls, contains('openAppSettings'));
    });
  });

  group('delete held messages', () {
    testWidgets('asks first; Cancel deletes nothing; Delete clears', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, heldCount: 3);
      final r = _Rig(consent: true, bridge: b);
      await _pump(t, r);
      expect(find.text(deleteHeldSubtitle(3)), findsOneWidget);
      await t.tap(_deleteHeld);
      await t.pumpAndSettle();
      expect(find.text(kDeleteHeldTitle), findsOneWidget);
      await t.tap(find.byKey(const Key('deleteHeldCancel')));
      await t.pumpAndSettle();
      expect(b.calls, isNot(contains('deleteAllHeld')));
      expect(b.heldCount, 3);
      await t.tap(_deleteHeld);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('deleteHeldConfirm')));
      await t.pumpAndSettle();
      expect(b.calls, contains('deleteAllHeld'));
      expect(b.heldCount, 0);
      expect(find.text(kDeleteHeldDone), findsOneWidget);
      expect(find.text(kDeleteHeldNone), findsOneWidget);
    });

    testWidgets('nothing held: the row is not tappable', (t) async {
      final r = _Rig(consent: true);
      await _pump(t, r);
      await t.tap(_deleteHeld, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(find.text(kDeleteHeldTitle), findsNothing);
    });
  });

  testWidgets('the restricted-settings help is reachable and lists the steps', (t) async {
    final r = _Rig(consent: true);
    await _pump(t, r);
    await t.tap(_helpRow);
    await t.pumpAndSettle();
    expect(find.text(kHelpIntro), findsOneWidget);
    for (final s in kHelpSteps) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.text(kHelpOpen), findsOneWidget);
    await t.tap(find.byKey(const Key('helpOpenSettings')));
    await t.pumpAndSettle();
    expect(r.b.calls, contains('openAppSettings'));
    await t.tap(find.byKey(const Key('helpClose')));
    await t.pumpAndSettle();
    expect(find.text(kHelpIntro), findsNothing);
  });

  group('consent sheet content', () {
    Future<void> open(WidgetTester t, {double scale = 1.0, double w = 390}) async {
      _size(t, w);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Builder(
          builder: (c) => TextButton(onPressed: () => showConsentSheet(c), child: const Text('open')),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('the Android SMS prompt sentence is on the first screen, before Allow / Not now (PM 22-10-2026)', (t) async {
      await open(t);
      // Visible without expanding More details.
      expect(find.text(kConsentAndroidPrompt), findsOneWidget);
      expect(find.byKey(const Key('consentAndroidPrompt')).hitTestable(), findsOneWidget);
      // Above the Allow and Not now buttons.
      final y = t.getTopLeft(find.byKey(const Key('consentAndroidPrompt'))).dy;
      expect(y, lessThan(t.getTopLeft(find.byKey(const Key('consentAllow'))).dy));
      expect(y, lessThan(t.getTopLeft(find.byKey(const Key('consentNotNow'))).dy));
      // Not repeated behind More details.
      await t.tap(find.byKey(const Key('consentMore')));
      await t.pumpAndSettle();
      expect(find.text(kConsentAndroidPrompt, skipOffstage: false), findsOneWidget);
      expect(kConsentDetailLines, isNot(contains(kConsentAndroidPrompt)));
    });

    testWidgets('lead sentence first; detail behind More; every required point is there', (t) async {
      await open(t);
      expect(find.text(kConsentWhatIsRead), findsNothing);
      await t.tap(find.byKey(const Key('consentMore')));
      await t.pumpAndSettle();
      for (final s in kConsentDetailLines) {
        expect(find.text(s, skipOffstage: false), findsOneWidget, reason: s);
      }
      expect(find.textContaining('Joshua Waga', skipOffstage: false), findsOneWidget);
      expect(find.textContaining('@', skipOffstage: false), findsNothing);
      expect(find.textContaining('A forged message can look genuine', skipOffstage: false), findsOneWidget);
    });

    testWidgets('both buttons are 44 px or more, at 360 px and 1.3 text, no overflow', (t) async {
      await open(t, scale: 1.3, w: 360);
      for (final k in ['consentAllow', 'consentNotNow', 'consentMore']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      // The first-screen Android sentence pushes More below the fold at this size: scroll to it.
      await t.ensureVisible(find.byKey(const Key('consentMore')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentMore')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // The buttons stay on screen while the detail scrolls.
      expect(find.byKey(const Key('consentAllow')).hitTestable(), findsOneWidget);
    });

    testWidgets('a double tap on Agree answers once', (t) async {
      var n = 0;
      _size(t, 390);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              if (await showConsentSheet(c) != null) n++;
            },
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.tap(find.byKey(const Key('consentAllow')), warnIfMissed: false);
      await t.pumpAndSettle();
      expect(n, 1);
    });
  });

  group('layout and spoken labels', () {
    for (final w in [360.0, 390.0]) {
      testWidgets('no overflow at $w px and 1.3 text, rows 44 px or more, broken state', (t) async {
        final r = _Rig(
          consent: true,
          bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: false, heldCount: 12),
        );
        await _pump(t, r, w: w, scale: 1.3);
        expect(t.takeException(), isNull);
        for (final f in [_switch, _fix, _deleteHeld, _helpRow]) {
          expect(f, findsOneWidget);
          expect(t.getSize(f).height, greaterThanOrEqualTo(44));
        }
      });
    }

    testWidgets('the switch row is one spoken stop: label, status and on/off', (t) async {
      final h = t.ensureSemantics();
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true));
      await _pump(t, r);
      final node = t.getSemantics(find.bySemanticsLabel(kReadLabel));
      expect(node.label, kReadLabel);
      expect(node.hint, kReadStatusOn);
      expect(node.flagsCollection.isToggled, Tristate.isTrue);
      h.dispose();
    });
  });

  group('consent screen: one switch per consent', () {
    final readSw = find.byKey(const Key('consentReadSwitch'));
    final parseSw = find.byKey(const Key('consentParseSwitch'));
    Finder sw(Finder row) => find.descendant(of: row, matching: find.byType(Switch));
    Finder inSheet(Finder f) => find.descendant(of: find.byType(ConsentSheet), matching: f);

    Future<void> openFirst(WidgetTester t, _Rig r) async {
      await _pump(t, r);
      await t.tap(_switch);
      await t.pumpAndSettle();
    }

    testWidgets('first open: both switches ON, Allow and Not now, the footer line, no master switch', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      expect(t.widget<Switch>(sw(readSw)).value, isTrue);
      expect(t.widget<Switch>(sw(parseSw)).value, isTrue);
      expect(t.widget<Switch>(sw(parseSw)).onChanged, isNotNull);
      expect(find.text(kReadLabel), findsWidgets);
      expect(find.text(kParseLabel), findsWidgets);
      expect(find.text(kConsentReadDesc), findsOneWidget);
      expect(find.text(kConsentParseDesc), findsOneWidget);
      expect(find.text(kConsentFooter), findsOneWidget);
      expect(find.text(kConsentAllow), findsOneWidget);
      expect(find.text(kConsentNotNow), findsOneWidget);
      // Exactly two switches in the sheet (plus the two Settings rows behind it).
      expect(find.descendant(of: find.byType(ConsentSheet), matching: find.byType(Switch)), findsNWidgets(2));
    });

    testWidgets('Read off: the Parse switch is greyed (disabled, shows off) and says why', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      await t.tap(readSw);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(sw(readSw)).value, isFalse);
      expect(t.widget<Switch>(sw(parseSw)).onChanged, isNull);
      expect(t.widget<Switch>(sw(parseSw)).value, isFalse);
      expect(inSheet(find.textContaining(kParseGreyLine)), findsOneWidget);
      // Tapping the greyed row changes nothing.
      await t.tap(parseSw, warnIfMissed: false);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(sw(parseSw)).value, isFalse);
      // Read back on: Parse is live again and kept its ON choice.
      await t.tap(readSw);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(sw(parseSw)).onChanged, isNotNull);
      expect(t.widget<Switch>(sw(parseSw)).value, isTrue);
    });

    testWidgets('Allow with both on: consent stored (Dart and Kotlin), Parse ON, then permissions and Read on', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.pumpAndSettle();
      expect(r.p.data[kReadingConsentKey], kReadingConsentVersion);
      expect(r.b.kotlinConsent, kReadingConsentVersion);
      expect(r.b.parseOn, isTrue);
      expect(r.b.calls, containsAllInOrder(['setConsent:$kReadingConsentVersion', 'setParseOn:true', 'requestPermissions', 'setEnabled:true']));
      expect(r.b.enabled, isTrue);
      expect(t.widget<Switch>(_parseSwitch).value, isTrue);
    });

    testWidgets('Allow with Parse switched off: consent stored, Parse stays OFF, Read on', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      await t.tap(parseSw);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(sw(parseSw)).value, isFalse);
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.pumpAndSettle();
      expect(r.p.data[kReadingConsentKey], kReadingConsentVersion);
      expect(r.b.parseOn, isFalse);
      expect(r.b.enabled, isTrue);
      expect(t.widget<Switch>(_parseSwitch).value, isFalse);
    });

    testWidgets('Allow with Read off turns nothing on and stores nothing (open point for the PM)', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      await t.tap(readSw);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentAllow')));
      await t.pumpAndSettle();
      expect(find.byType(ConsentSheet), findsNothing);
      expect(r.p.data, isEmpty);
      expect(r.b.calls, isEmpty);
      expect(r.b.enabled, isFalse);
      expect(r.b.parseOn, isFalse);
    });

    testWidgets('Not now stores nothing, calls nothing, and the app stays usable', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      await t.tap(find.byKey(const Key('consentNotNow')));
      await t.pumpAndSettle();
      expect(r.p.data, isEmpty);
      expect(r.b.calls, isEmpty);
      expect(r.b.kotlinConsent, 0);
      expect(r.b.parseOn, isFalse);
      // The Settings rows still work: delete-held and help open, and the Read
      // switch asks again.
      await t.tap(_helpRow);
      await t.pumpAndSettle();
      expect(find.text(kHelpIntro), findsOneWidget);
      await t.tap(find.byKey(const Key('helpClose')));
      await t.pumpAndSettle();
      await t.tap(_switch);
      await t.pumpAndSettle();
      expect(find.byType(ConsentSheet), findsOneWidget);
    });

    testWidgets('an existing v1 holder is asked again (sheet shown), not silently turned on', (t) async {
      final b = FakeReadingBridge();
      final r = _Rig(bridge: b);
      r.p.data[kReadingConsentKey] = 1;
      await openFirst(t, r);
      expect(find.byType(ConsentSheet), findsOneWidget);
      expect(b.calls, isEmpty);
    });

    testWidgets('no Autostart row on a phone that is not Xiaomi-family', (t) async {
      final r = _Rig();
      await openFirst(t, r);
      expect(find.byKey(const Key('consentAutostart')), findsNothing);
      expect(find.text(kAutostartButton), findsNothing);
    });

    testWidgets('Autostart row on a Xiaomi-family phone: explanation and a button, NOT a switch; opens only on tap', (t) async {
      final r = _Rig(bridge: FakeReadingBridge(autostartHelp: true));
      await openFirst(t, r);
      expect(find.byKey(const Key('consentAutostart')), findsOneWidget);
      expect(inSheet(find.text(kAutostartBody)), findsOneWidget);
      expect(inSheet(find.text(kAutostartButton)), findsOneWidget);
      expect(find.descendant(of: find.byType(ConsentSheet), matching: find.byType(Switch)), findsNWidgets(2));
      expect(r.b.calls, isNot(contains('openAutostartSettings')), reason: 'never launched automatically');
      await t.tap(inSheet(find.byKey(const Key('autostartOpen'))));
      await t.pumpAndSettle();
      expect(r.b.calls, contains('openAutostartSettings'));
      expect(find.byType(ConsentSheet), findsOneWidget, reason: 'the button does not answer the sheet');
      expect(r.p.data, isEmpty);
    });

    testWidgets('no overflow at 360 px and 1.3 text with the Autostart row; buttons 44 px or more', (t) async {
      final r = _Rig(bridge: FakeReadingBridge(autostartHelp: true));
      _size(t, 360);
      await _pump(t, r, w: 360, scale: 1.3);
      await t.tap(_switch);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final k in ['consentAllow', 'consentNotNow', 'autostartOpen']) {
        expect(t.getSize(inSheet(find.byKey(Key(k)))).height, greaterThanOrEqualTo(44), reason: k);
      }
    });
  });

  group('Settings: Parse from the notification switch', () {
    testWidgets('Read off: the row is greyed, shows off and says why', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(parseOn: true));
      await _pump(t, r);
      expect(find.text(kParseLabel), findsOneWidget);
      expect(find.text(kParseGreyLine), findsOneWidget);
      expect(t.widget<Switch>(_parseSwitch).onChanged, isNull);
      expect(t.widget<Switch>(_parseSwitch).value, isFalse);
    });

    testWidgets('Read on, Parse ON after consent: switch shows on; turning it off and on writes through', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, parseOn: true));
      await _pump(t, r);
      expect(t.widget<Switch>(_parseSwitch).value, isTrue);
      expect(find.text(kConsentParseDesc), findsOneWidget);
      await t.tap(_parseRow);
      await t.pumpAndSettle();
      expect(r.b.parseOn, isFalse);
      expect(r.b.calls, contains('setParseOn:false'));
      expect(t.widget<Switch>(_parseSwitch).value, isFalse);
      expect(r.b.enabled, isTrue, reason: 'Parse does not change Read');
      await t.tap(_parseRow);
      await t.pumpAndSettle();
      expect(r.b.parseOn, isTrue);
      expect(t.widget<Switch>(_parseSwitch).value, isTrue);
    });

    testWidgets('a Parse write that does not take says so and the switch reads back as it was', (t) async {
      final b = FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, parseOn: true)..setParseIgnored = true;
      final r = _Rig(consent: true, bridge: b);
      await _pump(t, r);
      await t.tap(_parseRow);
      await t.pumpAndSettle();
      expect(t.widget<Switch>(_parseSwitch).value, isTrue);
      expect(find.text(kReadFailed), findsOneWidget);
    });

    testWidgets('turning Read off keeps the Parse choice in the prefs', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true, parseOn: true));
      await _pump(t, r);
      await t.tap(_switch);
      await t.pumpAndSettle();
      expect(r.b.enabled, isFalse);
      expect(r.b.parseOn, isTrue);
      expect(t.widget<Switch>(_parseSwitch).onChanged, isNull);
    });

    testWidgets('a missing permission does not switch anything off', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: false, notifGranted: true, parseOn: true));
      await _pump(t, r);
      expect(r.b.enabled, isTrue);
      expect(r.b.parseOn, isTrue);
      expect(t.widget<Switch>(_parseSwitch).value, isTrue);
    });

    testWidgets('Autostart row hidden on a phone that is not Xiaomi-family', (t) async {
      await _pump(t, _Rig(consent: true));
      expect(_settingsAutostart, findsNothing);
      expect(find.text(kAutostartButton), findsNothing);
    });

    testWidgets('Autostart row shown on Xiaomi-family; a button, not a switch; opens only on tap', (t) async {
      final r = _Rig(consent: true, bridge: FakeReadingBridge(autostartHelp: true));
      await _pump(t, r);
      expect(_settingsAutostart, findsOneWidget);
      expect(find.text(kAutostartBody), findsOneWidget);
      expect(find.descendant(of: _settingsAutostart, matching: find.byType(Switch)), findsNothing);
      expect(r.b.calls, isNot(contains('openAutostartSettings')));
      await t.tap(find.text(kAutostartButton));
      await t.pumpAndSettle();
      expect(r.b.calls, contains('openAutostartSettings'));
    });
  });

  testWidgets('no controller set: nothing is drawn', (t) async {
    ReadingControllerHolder.instance = null;
    _size(t, 390);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: const Scaffold(body: ReadingSettingsSection()),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('readingSection')), findsNothing);
  });
}
