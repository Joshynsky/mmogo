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
    if (consent) p.data[kReadingConsentKey] = kReadingConsentVersion;
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
final _fix = find.byKey(const Key('readingFixRow'));
final _deleteHeld = find.byKey(const Key('readingDeleteHeld'));
final _helpRow = find.byKey(const Key('readingHelpRow'));

void main() {
  testWidgets('off state: switch with a plain status, no fix row', (t) async {
    final r = _Rig();
    await _pump(t, r);
    expect(find.text(kReadLabel), findsOneWidget);
    expect(find.text(kReadStatusOff), findsOneWidget);
    expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(_fix, findsNothing);
  });

  testWidgets('first turn-on shows the consent sheet BEFORE any system dialog', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(find.text(kConsentTitle), findsOneWidget);
    expect(find.text(kConsentLead), findsOneWidget);
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

  testWidgets('Agree stores consent, then permissions, then on; consent is not asked twice', (t) async {
    final r = _Rig();
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('consentAgree')));
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
    expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('turning off removes pending items and shows the plain result', (t) async {
    final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true));
    r.p.data[pendingKey(1)] = 'x';
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(r.b.enabled, isFalse);
    expect(r.s.bumps, 1);
    expect(r.p.data.keys.where((k) => k.startsWith('autoread_pending_v1.')), isEmpty);
  });

  testWidgets('off but could not clear is said plainly (fail closed)', (t) async {
    final r = _Rig(consent: true, bridge: FakeReadingBridge(enabled: true, smsGranted: true, notifGranted: true));
    r.p.data[pendingKey(1)] = 'x';
    r.p.failRemove = true;
    await _pump(t, r);
    await t.tap(_switch);
    await t.pumpAndSettle();
    expect(find.text(kReadOffNotCleared), findsOneWidget);
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
      for (final k in ['consentAgree', 'consentNotNow', 'consentMore']) {
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44), reason: k);
      }
      await t.tap(find.byKey(const Key('consentMore')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // The buttons stay on screen while the detail scrolls.
      expect(find.byKey(const Key('consentAgree')).hitTestable(), findsOneWidget);
    });

    testWidgets('a double tap on Agree answers once', (t) async {
      var n = 0;
      _size(t, 390);
      await t.pumpWidget(MaterialApp(
        theme: AppTheme.theme,
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () async {
              if (await showConsentSheet(c)) n++;
            },
            child: const Text('open'),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('consentAgree')));
      await t.tap(find.byKey(const Key('consentAgree')), warnIfMissed: false);
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
