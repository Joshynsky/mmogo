// AutoGroup: the trail shows only with entries, and every trail row carries the
// "Change in Settings" link (it is the only in-page pointer to the switches).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/auto_group.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart' show kHardRecentlyRecorded;
import 'package:mmogo/ui/theme/app_palette_scope.dart';

final _t0 = DateTime(2026, 11, 13, 9);

class _Pushes extends NavigatorObserver {
  final List<RouteSettings> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route.settings);
}

AirtimeAutoController _c() =>
    AirtimeAutoController(
        onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {}, now: () => _t0);

Widget _host(AirtimeAutoController c, _Pushes obs) => AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        navigatorObservers: [obs],
        routes: {'/settings': (_) => const Scaffold(body: Text('SETTINGS'))},
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (context) =>
                  AutoGroup(c, _t0, onChangeInSettings: () => Navigator.of(context).pushNamed('/settings')),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('empty trail draws nothing, with the switches on', (t) async {
    final c = _c()
      ..setOn(true)
      ..setOnOther(true);
    await t.pumpWidget(_host(c, _Pushes()));
    expect(find.text(kHardRecentlyRecorded), findsNothing);
    expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('every trail row has the link; tapping it goes to Settings (fake observer)', (t) async {
    final c = _c()
      ..add(AutoRecorded(rowId: 1, amountCents: 500, at: _t0))
      ..add(AutoRecorded(rowId: 2, amountCents: 1000, at: _t0, airtimeOther: true));
    final obs = _Pushes();
    await t.pumpWidget(_host(c, obs));
    expect(find.text(kHardRecentlyRecorded), findsOneWidget);
    expect(find.text(kAutoRecordedChangeInSettings), findsNWidgets(2));
    expect(find.byType(Switch), findsNothing);
    await t.tap(find.text(kAutoRecordedChangeInSettings).first);
    await t.pumpAndSettle();
    expect(obs.pushed.last.name, '/settings');
  });
}
