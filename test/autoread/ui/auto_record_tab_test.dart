// Widget tests for the Remembered page's second tab. Invented data only; the
// controller is the real one, its switch callbacks write the real pref keys
// into mock preferences the way the app's repository does.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_airtime_card.dart';
import 'package:mmogo/autoread/ui/airtime_kind_copy.dart';
import 'package:mmogo/autoread/ui/auto_record_copy.dart';
import 'package:mmogo/autoread/ui/auto_record_tab.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

late AirtimeAutoController _c;

Future<void> _put(String key, bool v) async => (await SharedPreferences.getInstance()).setBool(key, v);

AirtimeAutoController _controller() {
  late AirtimeAutoController c;
  c = AirtimeAutoController(
    onSwitch: (v) async {
      await _put(kAirtimeAutoPrefKey, v);
      c.setOn(v);
    },
    onSwitchOther: (v) async {
      await _put(kAirtimeAutoOtherPrefKey, v);
      c.setOnOther(v);
    },
    onUndo: (_) async {},
  );
  return c;
}

Widget _host(Widget child, {double scale = 1, String mode = 'light'}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

Widget _tab({double scale = 1, String mode = 'light'}) =>
    _host(AutoRecordTab(controller: _c), scale: scale, mode: mode);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _c = _controller();
  });

  // A phone-width window (390 by 800) for every test here.
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('starts off: chips, two rows, no panel, no explainer', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    expect(find.text('Airtime'), findsOneWidget);
    for (final code in ['SM', 'PB', 'BG', 'W', 'P']) {
      expect(find.text(code), findsOneWidget);
    }
    expect(find.text(kAirtimeNameMyselfForTest), findsOneWidget);
    expect(find.text('For another number'), findsOneWidget);
    expect(find.byKey(const Key('autoRecordMyselfPanel')), findsNothing);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
    expect(find.text(kAutoRecordLaterTypes), findsOneWidget);
    expect(_c.on, isFalse);
    expect(_c.onOther, isFalse);
  });

  testWidgets('chips sit in one narrow row, muted ones are inert and spoken as coming later', (t) async {
    phone(t);
    final sem = t.ensureSemantics();
    await t.pumpWidget(_tab());
    final keys = ['Airtime', 'SM', 'PB', 'BG', 'W', 'P'].map((c) => Key('autoRecordChip$c')).toList();
    final rects = keys.map((k) => t.getRect(find.byKey(k))).toList();
    for (final r in rects) {
      expect(r.width, lessThan(150), reason: 'chip must not be full width');
      expect(r.height, 44);
      expect((r.top - rects.first.top).abs(), lessThan(1), reason: 'one row');
    }
    for (final code in ['SM', 'PB', 'BG', 'W', 'P']) {
      expect(find.ancestor(of: find.byKey(Key('autoRecordChip$code')), matching: find.byType(InkWell)), findsNothing);
      expect(find.ancestor(of: find.byKey(Key('autoRecordChip$code')), matching: find.byType(GestureDetector)), findsNothing);
    }
    expect(find.bySemanticsLabel('Send money, coming later'), findsOneWidget);
    expect(find.bySemanticsLabel('Paybill, coming later'), findsOneWidget);
    sem.dispose();
  });

  testWidgets('own number is first, the label comes from the category name', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    final own = t.getTopLeft(find.byKey(const Key('autoRecordMyself'))).dy;
    final other = t.getTopLeft(find.byKey(const Key('autoRecordOther'))).dy;
    expect(own, lessThan(other));
    expect(kAirKindMyselfLabel, 'For myself');
  });

  testWidgets('own switch writes its own key; panel opens and closes', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAirtimeAutoPrefKey), isTrue);
    expect(prefs.getBool(kAirtimeAutoOtherPrefKey), isNull);
    expect(find.byKey(const Key('autoRecordMyselfPanel')), findsOneWidget);
    expect(find.byKey(const Key('autoRecordOtherPanel')), findsNothing);
    expect(find.text(autoRecordExplainTap(kAirKindMyselfLabel)), findsOneWidget);
    expect(find.text(kAutoRecordExplainLater), findsOneWidget);
    expect(find.textContaining('recorded at once'), findsOneWidget);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    expect(prefs.getBool(kAirtimeAutoPrefKey), isFalse);
    expect(find.byKey(const Key('autoRecordMyselfPanel')), findsNothing);
    expect(find.textContaining('Nothing is recorded for you'), findsOneWidget);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
  });

  testWidgets('other switch writes the other key only', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAirtimeAutoOtherPrefKey), isTrue);
    expect(prefs.getBool(kAirtimeAutoPrefKey), isNull);
    expect(_c.onOther, isTrue);
    expect(_c.on, isFalse);
    expect(find.text(autoRecordExplainTap(kAirKindOtherLabel)), findsOneWidget);
  });

  testWidgets('no Soft or Hard control anywhere on the tab, open or closed', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(find.text('Soft'), findsNothing);
    expect(find.text('Hard'), findsNothing);
    expect(find.textContaining('Hard comes'), findsNothing);
    expect(find.byKey(const Key('autoRecordMyselfHard')), findsNothing);
    expect(find.byKey(const Key('autoRecordMyselfSoft')), findsNothing);
  });

  testWidgets('the extra tab label carries N and follows the controller', (t) async {
    phone(t);
    final tab = autoRecordExtraTab(_c);
    expect(tab.pageTitle, 'Remembered');
    expect(tab.tabLabel(), 'Recorded automatically · 0');
    var fired = 0;
    tab.listenable.addListener(() => fired++);
    _c.setOn(true);
    _c.setOnOther(true);
    expect(tab.tabLabel(), 'Recorded automatically · 2');
    expect(fired, 2);
    expect(autoRecordTabSpoken(1), 'Recorded automatically, 1 of 2 on');
  });

  testWidgets('flipping here moves the Notifications card; flipping there moves this tab', (t) async {
    phone(t);
    await t.pumpWidget(_host(ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Column(children: [
        AutoAirtimeSwitchCard(on: _c.on, onChanged: _c.onSwitch, onOther: _c.onOther, onChangedOther: _c.onSwitchOther),
        Expanded(child: AutoRecordTab(controller: _c)),
      ]),
    )));
    bool card(String k) => t.widget<Switch>(find.byKey(Key(k))).value;
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(card('autoAirtimeSwitchOther'), isTrue);
    expect(card('autoAirtimeSwitch'), isFalse);
    await t.tap(find.byKey(const Key('autoAirtimeSwitch')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('autoRecordMyselfPanel')), findsOneWidget);
  });

  testWidgets('no digits or phone text anywhere in the open tab', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    for (final w in t.widgetList<Text>(find.byType(Text))) {
      expect(RegExp(r'\d').hasMatch(w.data ?? ''), isFalse, reason: w.data);
    }
  });

  testWidgets('spoken labels: rows toggle with name and hint, chips say coming later', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    final row = t.getSemantics(find.byKey(const Key('autoRecordMyself')));
    expect(row.label, kAirKindMyselfLabel);
    expect(row.hint, kAutoRecordMyselfSub);
    expect(row.getSemanticsData().flagsCollection.isToggled != Tristate.none, isTrue);
    expect(row.getSemanticsData().flagsCollection.isToggled == Tristate.isTrue, isFalse);
    expect(t.getSemantics(find.byKey(const Key('autoRecordChipPB'))).label, 'Paybill, coming later');
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('large text 1.3 and $mode: both rows open, no overflow, block aligned with row text', (t) async {
      phone(t);
      await t.pumpWidget(_tab(scale: 1.3, mode: mode));
      await t.tap(find.byKey(const Key('autoRecordMyself')));
      await t.tap(find.byKey(const Key('autoRecordOther')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final k in ['autoRecordMyself', 'autoRecordOther']) {
        final line1 = find.byKey(Key('${k}Explain'));
        final line2 = find.byKey(Key('${k}ExplainLater'));
        expect(t.getTopLeft(line1).dx, t.getTopLeft(line2).dx);
        expect(t.getTopLeft(line1).dx, 60);
        expect(t.getRect(line1).right, 390 - 14);
        expect(t.getTopLeft(line2).dy, greaterThanOrEqualTo(t.getBottomLeft(line1).dy));
      }
    });
  }
}

// The category name the page uses for the own number, spelled out so a rename
// shows up here.
const String kAirtimeNameMyselfForTest = 'For myself';
