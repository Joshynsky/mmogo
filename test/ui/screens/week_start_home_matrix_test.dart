// F5 (0.1.2 corrections, closes finding R33): the week-start proof for HOME.
// The real HomeScreen on a fake clock and a fake database that records every
// window it is asked for, with every first day of the week (7) against a
// "today" on every weekday plus the year and leap-day boundaries (9). Week
// pill: the figure sums exactly the days from the chosen weekday to today and
// "vs last week" asks for the whole week before; Month pill: unmoved by the
// first day. Expected windows come from test/support/week_start_oracle.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';
import '../../support/week_start_home_db.dart';
import '../../support/week_start_oracle.dart';

int _ms(DateTime d, [bool end = false]) =>
    (end ? DateTime(d.year, d.month, d.day, 23, 59, 59, 999) : DateTime(d.year, d.month, d.day)).millisecondsSinceEpoch;

/// One row a day for the 45 days up to [today]: Ksh 100 x (days ago + 1), so
/// every week window has its own sum and a wrong week start shows.
List<Map<String, Object?>> _rows(DateTime today) => [
  for (var k = 0; k < 45; k++)
    fakeTx(
      id: k + 1,
      at: DateTime(today.year, today.month, today.day - k, 10),
      amountCents: 10000 * (k + 1),
      label: 'PARTY $k',
      phone: '07000${1000 + k}',
    ),
];

/// Ksh sum of the rows whose date is in [from]..[to] (oracle dates), by name.
int _kshSum(DateTime today, DateTime from, DateTime to) {
  var t = 0;
  var d = day(today.year, today.month, today.day);
  for (var k = 0; k < 45; k++) {
    final inside = !d.isBefore(from) && !d.isAfter(to);
    if (inside) t += 100 * (k + 1);
    d = prevDay(d);
  }
  return t;
}

String _digits(WidgetTester t) =>
    (t.widget<Text>(find.byKey(const Key('homeTotal'))).data ?? '').replaceAll(RegExp(r'[^0-9]'), '');

Future<WeekStartHomeDb> _pump(WidgetTester tester, DateTime today) async {
  tester.view.physicalSize = const Size(392, 1600) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final db = WeekStartHomeDb(_rows(today));
  await tester.pumpWidget(MaterialApp(home: HomeScreen(db: db, clock: () => today.add(const Duration(hours: 14)), startUpdates: () async {})));
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
  return db;
}

void main() {
  final todays = <DateTime>[
    for (var d = 12; d <= 18; d++) DateTime(2026, 10, d), // Mon .. Sun
    DateTime(2027, 1, 1), // Friday, year boundary
    DateTime(2028, 2, 29), // Tuesday, leap day
  ];

  for (var first = 1; first <= 7; first++) {
    for (final today in todays) {
      testWidgets('first day $first, today ${today.year}-${today.month}-${today.day}: Home Week and Month pills', (tester) async {
        SharedPreferences.setMockInitialValues({'first_day_of_week': first});
        final why = 'first day $first, today $today';
        final db = await _pump(tester, today);
        final t = day(today.year, today.month, today.day);
        final ws = weekStartOf(t, first);
        final prevEnd = prevDay(ws);
        final prevStart = weekStartOf(prevEnd, first);

        // Cycle the pill (Today > This week > This month) to This week.
        for (var i = 0; i < 3 && find.text('This week').evaluate().isEmpty; i++) {
          await tester.tap(find.byKey(const Key('homePeriodButton')));
          await tester.pumpAndSettle();
        }
        chk(find.text('This week').evaluate().length, 1, reason: '$why: on the Week pill');
        // This week: from the chosen weekday 00:00 to the end of today, and
        // the whole week before ("vs last week").
        chk(db.sums.contains((_ms(ws), _ms(today, true))), true, reason: '$why: week window ${db.sums}');
        chk(db.sums.contains((_ms(prevStart), _ms(prevEnd, true))), true, reason: '$why: vs last week window ${db.sums}');
        chk(DateTime.fromMillisecondsSinceEpoch(_ms(ws)).weekday, first, reason: '$why: window starts on the weekday');
        chk(_digits(tester), '${_kshSum(t, ws, t)}00', reason: '$why: the figure sums the days of this week so far');

        // This month: the 1st to the last day, whatever the first day.
        await tester.tap(find.byKey(const Key('homePeriodButton')));
        await tester.pumpAndSettle();
        final monthStart = day(t.year, t.month, 1);
        final monthEnd = day(t.year, t.month, lastDayOfMonth(t.year, t.month));
        chk(db.sums.contains((_ms(monthStart), _ms(monthEnd, true))), true, reason: '$why: month window');
        chk(_digits(tester), '${_kshSum(t, monthStart, monthEnd)}00', reason: '$why: the figure sums the month');
      });
    }
  }
}
