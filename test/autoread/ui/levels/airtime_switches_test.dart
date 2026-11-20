// Widget tests for the Remembered page's second tab. Invented data only; the
// controller is the real one, its switch callbacks write the real pref keys
// into mock preferences the way the app's repository does.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_group.dart';
import 'package:mmogo/autoread/ui/airtime_kind_copy.dart';
import 'package:mmogo/autoread/ui/auto_record_copy.dart';
import 'package:mmogo/autoread/ui/levels/airtime_switches.dart';
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
    now: () => DateTime(2026, 11, 13, 10), // the trail window is 24 h: a fixed clock keeps this test stable
  );
  return c;
}

Widget _host(Widget child, {double scale = 1, String mode = 'light'}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );

Widget _tab({double scale = 1, String mode = 'light'}) =>
    _host(SingleChildScrollView(child: AirtimeSwitches(controller: _c)), scale: scale, mode: mode);

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

  testWidgets('starts off: two rows, no explainer text', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    expect(find.text(kAirtimeNameMyselfForTest), findsOneWidget);
    expect(find.text('For another number'), findsOneWidget);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
    expect(_c.on, isFalse);
    expect(_c.onOther, isFalse);
  });

  testWidgets('own number is first, the label comes from the category name', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    final own = t.getTopLeft(find.byKey(const Key('autoRecordMyself'))).dy;
    final other = t.getTopLeft(find.byKey(const Key('autoRecordOther'))).dy;
    expect(own, lessThan(other));
    expect(kAirKindMyselfLabel, 'For myself');
  });

  testWidgets('own switch writes its own key; no panel opens', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kAirtimeAutoPrefKey), isTrue);
    expect(prefs.getBool(kAirtimeAutoOtherPrefKey), isNull);
    expect(find.byKey(const Key('autoRecordMyselfPanel')), findsNothing);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
    expect(find.textContaining('recorded at once'), findsOneWidget); // the ON toast
    PillToast.dismissNow(); // the pill floats over the top row: clear it before the next tap
    await t.pump();
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    expect(prefs.getBool(kAirtimeAutoPrefKey), isFalse);
    expect(find.textContaining('Nothing is recorded for you'), findsOneWidget);
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

  testWidgets('switches and trail agree on one controller; no switch card anywhere', (t) async {
    phone(t);
    await t.pumpWidget(_host(ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Column(children: [
        AutoGroup(_c, DateTime(2026, 11, 13, 9), onChangeInSettings: () {}),
        Expanded(child: SingleChildScrollView(child: AirtimeSwitches(controller: _c))),
      ]),
    )));
    expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(_c.onOther, isTrue);
    expect(_c.on, isFalse);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    // A new record shows on the trail, with its link; still no card.
    _c.add(AutoRecorded(rowId: 5, amountCents: 500, at: DateTime(2026, 11, 13, 9)));
    await t.pumpAndSettle();
    expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
    expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
  });

  testWidgets('switched on: none of the rule paragraphs is on the page (they live in the "?" sheet)', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(find.textContaining('You tap Parse on each message'), findsNothing);
    expect(find.text(kAutoRecordExplainUndo), findsNothing);
    expect(find.text(kAutoRecordExplainLater), findsNothing);
    expect(find.byKey(const Key('autoRecordMyselfExplain')), findsNothing);
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

  testWidgets('spoken labels: rows toggle with name and hint', (t) async {
    phone(t);
    await t.pumpWidget(_tab());
    final row = t.getSemantics(find.byKey(const Key('autoRecordMyself')));
    expect(row.label, kAirKindMyselfLabel);
    expect(row.hint, kAutoRecordMyselfSub);
    expect(row.getSemanticsData().flagsCollection.isToggled != Tristate.none, isTrue);
    expect(row.getSemanticsData().flagsCollection.isToggled == Tristate.isTrue, isFalse);
  });

  for (final mode in ['light', 'dark']) {
    testWidgets('large text 1.3 and $mode: both switches on, no overflow, rows fit the width', (t) async {
      phone(t);
      await t.pumpWidget(_tab(scale: 1.3, mode: mode));
      await t.tap(find.byKey(const Key('autoRecordMyself')));
      await t.tap(find.byKey(const Key('autoRecordOther')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final k in ['autoRecordMyself', 'autoRecordOther']) {
        expect(t.getRect(find.byKey(Key(k))).right, lessThanOrEqualTo(390));
      }
    });
  }
}

// The category name the page uses for the own number, spelled out so a rename
// shows up here.
const String kAirtimeNameMyselfForTest = 'For myself';
