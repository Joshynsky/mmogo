// Widget tests for the two Auto-record airtime switches (WBS row 17, slice B).
// Invented data only; no database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/airtime_kind_copy.dart';
import 'package:mmogo/autoread/ui/auto_airtime_card.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

Widget _host(Widget child) => AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child))),
    );

bool _value(WidgetTester t, String key) => t.widget<Switch>(find.byKey(Key(key))).value;

void main() {
  testWidgets('two switches with the mock labels, Hard greyed note, other switch default off', (t) async {
    await t.pumpWidget(_host(AutoAirtimeSwitchCard(on: false, onChanged: (_) {}, onChangedOther: (_) {})));
    expect(find.text(kAirKindMyselfLabel), findsOneWidget);
    expect(find.text(kAirKindOtherLabel), findsOneWidget);
    expect(find.text('For my number'), findsOneWidget);
    expect(find.text('For another number'), findsOneWidget);
    expect(find.text('Hard comes in a later version'), findsOneWidget);
    expect(_value(t, 'autoAirtimeSwitch'), isFalse);
    expect(_value(t, 'autoAirtimeSwitchOther'), isFalse);
  });

  testWidgets('other switch default off even when the first one is on', (t) async {
    await t.pumpWidget(_host(AutoAirtimeSwitchCard(on: true, onChanged: (_) {}, onChangedOther: (_) {})));
    expect(_value(t, 'autoAirtimeSwitch'), isTrue);
    expect(_value(t, 'autoAirtimeSwitchOther'), isFalse);
  });

  testWidgets('two switches are independent and each reports its own tap', (t) async {
    var mine = false, other = false;
    final calls = <String>[];
    await t.pumpWidget(StatefulBuilder(
      builder: (c, set) => _host(AutoAirtimeSwitchCard(
        on: mine,
        onChanged: (v) {
          calls.add('mine:$v');
          set(() => mine = v);
        },
        onOther: other,
        onChangedOther: (v) {
          calls.add('other:$v');
          set(() => other = v);
        },
      )),
    ));
    await t.tap(find.byKey(const Key('autoAirtimeSwitchOther')));
    await t.pump();
    expect(other, isTrue);
    expect(mine, isFalse);
    expect(_value(t, 'autoAirtimeSwitch'), isFalse);
    await t.tap(find.byKey(const Key('autoAirtimeSwitch')));
    await t.pump();
    expect(mine, isTrue);
    expect(other, isTrue);
    await t.tap(find.byKey(const Key('autoAirtimeSwitchOther')));
    await t.pump();
    expect(other, isFalse);
    expect(mine, isTrue);
    expect(calls, ['other:true', 'mine:true', 'other:false']);
  });
}
