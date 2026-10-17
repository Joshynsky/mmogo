// F5 (0.1.2 corrections, closes finding R33): the week-start proof for the
// ROUTES THAT HAND A PERIOD TO ANALYTICS, with every first day of the week (7):
//  R4  Paid to > See in Analytics (Month, recipient filter), several visits,
//      each followed by clearing the filter;
//  R5  restoring the period after the recipient view, app pause and resume,
//      leaving Analytics and coming back (live in the real PrimaryShell);
//  R6  a Home recent-row tap into a Day, then the Week it belongs to;
//  R7  changing the first day in the real Settings while Analytics and Home
//      stay alive in the shell: every view re-anchors with no further action.
// Hand-off periods are deliberately built with ANOTHER first day, so only an
// always-on re-anchor passes. Expected values: test/support/week_start_oracle.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_analytics_db.dart';
import '../../support/fake_delete_data.dart';
import '../../support/week_start_home_db.dart';
import '../../support/week_start_oracle.dart';
import '../../support/week_start_probe.dart';

final _now = DateTime(2026, 10, 17, 12); // Saturday
final _today = day(2026, 10, 17);

List<Map<String, Object?>> _rows() => [
  fakeTx(id: 1, at: DateTime(2026, 10, 16, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 100000),
  fakeTx(id: 2, at: DateTime(2026, 10, 12, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 50000),
  fakeTx(id: 3, at: DateTime(2026, 10, 2, 9), label: 'JOHN KAMAU', phone: '0700000003', amountCents: 20000),
  fakeTx(id: 4, at: DateTime(2026, 9, 15, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 75000),
  fakeTx(id: 5, at: DateTime(2026, 9, 2, 9), label: 'JOHN KAMAU', phone: '0700000003', amountCents: 30000),
];

int _wrongFirstDay(int first) => first % 7 + 1;

AnalyticsRouteArgs _argsBuiltWith(int firstDay) => AnalyticsRouteArgs(
  type: 'SEND_MONEY',
  partyKey: '0712345678',
  partyName: 'MARY WANJIKU',
  period: AnalyticsPeriod.month(DateTime(2026, 10, 1), firstDay: firstDay),
);

/// What a real Paid to hands to Analytics for Mary: the screen, its button, the args.
Future<AnalyticsRouteArgs> _paidToHandOff(WidgetTester tester) async {
  tall(tester);
  AnalyticsRouteArgs? got;
  await tester.pumpWidget(
    MaterialApp(
      home: PaidToScreen(db: FakeAnalyticsDb(_rows()), clock: () => _now),
      onGenerateRoute: (settings) {
        if (settings.name != '/analytics') return null;
        got = settings.arguments! as AnalyticsRouteArgs;
        return MaterialPageRoute(settings: settings, builder: (_) => const Scaffold(body: Text('ANALYTICS')));
      },
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('MARY WANJIKU'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('paidToSheetAnalytics')));
  await tester.tap(find.byKey(const Key('paidToSheetAnalytics')));
  await tester.pumpAndSettle();
  return got!;
}

Future<PrimaryShellController> _pumpShell(WidgetTester t, {required Widget home, required Widget analytics, int index = 1}) async {
  tall(t);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController(),
      child: MaterialApp(
        home: PrimaryShell(
          initialIndex: index,
          pages: {0: home, 1: analytics, 3: const SizedBox(), 4: const SizedBox()},
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return PrimaryShell.active!;
}

void _pauseResume(WidgetTester t) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    t.binding.handleAppLifecycleStateChanged(s);
  }
}

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _ms(DateTime d, [bool end = false]) =>
    (end ? DateTime(d.year, d.month, d.day, 23, 59, 59, 999) : DateTime(d.year, d.month, d.day)).millisecondsSinceEpoch;

void main() {
  late SemanticsHandle semantics;
  setUp(() => useFakeDeleteData());
  setUp(() => semantics = TestWidgetsFlutterBinding.ensureInitialized().ensureSemantics());
  tearDown(() => semantics.dispose());

  for (var first = 1; first <= 7; first++) {
    final why = 'first day $first';

    testWidgets('first day $first, R4: Paid to hand-off (Month, recipient), three visits, each followed by clearing the filter', (t) async {
      setFirstDay(first);
      final args = await _paidToHandOff(t);
      chk(args.period!.firstDay, first, reason: '$why: the hand-off carries the preference');
      for (var visit = 1; visit <= 3; visit++) {
        await pumpAnalytics(t, FakeAnalyticsDb(_rows()), _now, args: args);
        chk(find.byKey(const Key('analyticsPartyCard')).evaluate().length, 1, reason: '$why: recipient view, visit $visit');
        chk(weekBars(t), [for (final s in monthSegments(2026, 10, first)) s.label], reason: '$why: Month weeks, visit $visit');
        await tapKey(t, 'analyticsPartyClose');
        chk(find.byKey(const Key('analyticsPartyCard')).evaluate().length, 0, reason: '$why: filter cleared, visit $visit');
        expectWeekShown(t, _today, first, '$why: restored week after visit $visit');
      }
    });

    testWidgets('first day $first, R4+R5: live shell, hand-offs built with another first day, restore, pause/resume, leave and return', (t) async {
      setFirstDay(first);
      final shell = await _pumpShell(t, home: const SizedBox(), analytics: AnalyticsScreen(db: FakeAnalyticsDb(_rows()), clock: () => _now));

      // A stepped Month view is what Close must bring back.
      await pickGranularity(t, 'Month');
      await tapKey(t, 'analyticsPrev');
      expectMonthShown(t, 2026, 9, first, '$why: September 2026 before the hand-offs');

      for (var run = 1; run <= 3; run++) {
        shell.openAnalytics(_argsBuiltWith(_wrongFirstDay(first)));
        await t.pumpAndSettle();
        chk(weekBars(t), [for (final s in monthSegments(2026, 10, first)) s.label], reason: '$why: recipient Month weeks, run $run');
        await tapKey(t, 'analyticsPartyClose');
        expectMonthShown(t, 2026, 9, first, '$why: restored September after run $run');
      }

      _pauseResume(t);
      await t.pumpAndSettle();
      expectMonthShown(t, 2026, 9, first, '$why: after app pause and resume');

      shell.select(0); // leave Analytics ...
      await t.pumpAndSettle();
      shell.select(1); // ... and come back
      await t.pumpAndSettle();
      expectMonthShown(t, 2026, 9, first, '$why: after leaving and returning');

      await pickGranularity(t, 'Week');
      expectWeekShown(t, day(2026, 9, 30), first, '$why: Week from the restored Month');
    });

    testWidgets('first day $first, R6: Home recent row > Day > Week, two rows', (t) async {
      setFirstDay(first, more: {'tour_seen_home': true});
      // Home's recent list is the newest rows; the ids are k+1 for k days ago.
      final rows = [
        for (var k = 0; k < 12; k++)
          fakeTx(id: k + 1, at: DateTime(2026, 10, 17 - k, 10), amountCents: 10000 * (k + 1), label: 'PARTY $k', phone: '07000${1000 + k}'),
      ];
      final db = WeekStartHomeDb(rows);
      final shell = await _pumpShell(
        t,
        home: HomeScreen(db: db, clock: () => _now, startUpdates: () async {}),
        analytics: AnalyticsScreen(db: db, clock: () => _now),
        index: 0,
      );
      for (final (id, rowDay) in [(2, day(2026, 10, 16)), (5, day(2026, 10, 13))]) {
        shell.select(0);
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(Key('homeRecentRow-$id')));
        await t.tap(find.byKey(Key('homeRecentRow-$id')));
        await t.pumpAndSettle();
        chk(shell.index.value, 1, reason: '$why: Analytics opened for row $id');
        await pickGranularity(t, 'Week');
        expectWeekShown(t, rowDay, first, '$why: Home row $id > Day > Week');
      }
    });
  }

  // Home and Analytics share the period LENGTH (a Week pick on one is a Week
  // on the other), so the chain runs once on the Month length (Analytics) and
  // once on the Week length (Analytics and Home together).
  for (final view in ['Month', 'Week']) {
    testWidgets('R7 ($view): Settings changes the first day (1>2>...>7>1) while Analytics and Home stay alive: both re-anchor, no further action', (t) async {
      setFirstDay(1, more: {'tour_seen_home': true});
      final rows = [
        for (var k = 0; k < 45; k++)
          fakeTx(id: k + 1, at: DateTime(2026, 10, 17 - k, 10), amountCents: 10000 * (k + 1), label: 'PARTY $k', phone: '07000${1000 + k}'),
      ];
      final db = WeekStartHomeDb(rows);
      final shell = await _pumpShell(
        t,
        home: HomeScreen(db: db, clock: () => _now, startUpdates: () async {}),
        analytics: AnalyticsScreen(db: db, clock: () => _now),
        index: 0,
      );
      if (view == 'Week') {
        // Home on the Week pill; Analytics follows when it is first built.
        for (var i = 0; i < 3 && find.text('This week').evaluate().isEmpty; i++) {
          await t.tap(find.byKey(const Key('homePeriodButton')));
          await t.pumpAndSettle();
        }
        shell.select(1);
        await t.pumpAndSettle();
        expectWeekShown(t, _today, 1, 'start: Monday, Analytics Week');
      } else {
        shell.select(1);
        await t.pumpAndSettle();
        await pickGranularity(t, 'Month'); // Analytics now on a Month view (Oct 2026)
        expectMonthShown(t, 2026, 10, 1, 'start: Monday');
      }

      var current = 1;
      for (final next in [2, 3, 4, 5, 6, 7, 1]) {
        // The real Settings, pushed over the shell, then closed.
        Navigator.of(t.element(find.byType(PrimaryShell))).push(
          MaterialPageRoute<void>(builder: (_) => SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {})),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('settingsFirstDayRow')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key('firstDay-$next')));
        await t.pumpAndSettle();
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        current = next;
        final why = 'after changing to first day $current ($view)';

        // Analytics (stayed mounted) re-anchored its chart.
        if (view == 'Month') {
          expectMonthShown(t, 2026, 10, current, '$why: Analytics Month');
        } else {
          expectWeekShown(t, _today, current, '$why: Analytics Week');
          // Home (stayed mounted): its Week window starts on the new weekday.
          shell.select(0);
          await t.pumpAndSettle();
          final ws = weekStartOf(_today, current);
          chk(db.sums.contains((_ms(ws), _ms(_today, true))), true, reason: '$why: Home week window starts ${ws.toIso8601String()}');
          final prevEnd = prevDay(ws);
          chk(db.sums.contains((_ms(weekStartOf(prevEnd, current)), _ms(prevEnd, true))), true, reason: '$why: Home vs last week window');
          shell.select(1);
          await t.pumpAndSettle();
        }
      }

      // A view built after the changes uses the final preference too.
      await pickGranularity(t, view == 'Month' ? 'Week' : 'Month');
      if (view == 'Month') {
        expectWeekShown(t, _today, current, 'end of the chain: Analytics Week');
      } else {
        expectMonthShown(t, 2026, 10, current, 'end of the chain: Analytics Month');
      }
    });
  }
}
