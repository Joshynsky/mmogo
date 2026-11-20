// Widget tests for the two Auto-record airtime switches, which live on the
// Remembered page's second tab (Settings > Remembered > Recorded automatically).
// Invented data only; no database. The controller is the real one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/airtime_kind_copy.dart';
import 'package:mmogo/autoread/ui/levels/airtime_switches.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

Widget _host(Widget child) => AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(home: Scaffold(body: child)),
    );

bool _value(WidgetTester t, String key) => t.widget<Switch>(find.byKey(Key(key))).value;

/// A controller whose switch callbacks record the call, then move the state.
AirtimeAutoController _controller(List<String> calls) {
  late AirtimeAutoController c;
  c = AirtimeAutoController(
    onSwitch: (v) async {
      calls.add('mine:$v');
      c.setOn(v);
    },
    onSwitchOther: (v) async {
      calls.add('other:$v');
      c.setOnOther(v);
    },
    onUndo: (_) async {},
  );
  return c;
}

void main() {
  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(390, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('two switches with the kind labels, both default off, no Hard line', (t) async {
    phone(t);
    await t.pumpWidget(_host(AirtimeSwitches(controller: _controller([]))));
    expect(find.text(kAirKindMyselfLabel), findsOneWidget);
    expect(find.text(kAirKindOtherLabel), findsOneWidget);
    expect(find.text('For myself'), findsOneWidget);
    expect(find.text('For another number'), findsOneWidget);
    expect(find.textContaining('Hard comes'), findsNothing);
    expect(_value(t, 'autoRecordMyselfSwitch'), isFalse);
    expect(_value(t, 'autoRecordOtherSwitch'), isFalse);
  });

  testWidgets('other switch default off even when the first one is on', (t) async {
    phone(t);
    final c = _controller([])..setOn(true);
    await t.pumpWidget(_host(AirtimeSwitches(controller: c)));
    expect(_value(t, 'autoRecordMyselfSwitch'), isTrue);
    expect(_value(t, 'autoRecordOtherSwitch'), isFalse);
  });

  testWidgets('two switches are independent and each reports its own tap', (t) async {
    phone(t);
    final calls = <String>[];
    final c = _controller(calls);
    await t.pumpWidget(_host(AirtimeSwitches(controller: c)));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(c.onOther, isTrue);
    expect(c.on, isFalse);
    expect(_value(t, 'autoRecordMyselfSwitch'), isFalse);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    expect(c.on, isTrue);
    expect(c.onOther, isTrue);
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(c.onOther, isFalse);
    expect(c.on, isTrue);
    expect(calls, ['other:true', 'mine:true', 'other:false']);
  });
}
