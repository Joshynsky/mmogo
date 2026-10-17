// F5 (0.1.2 corrections): what the week-start widget tests read off a live
// Analytics screen, shared by the route files. Bars are read from the
// accessibility labels the chart already carries; expected values come from
// week_start_oracle.dart, never from production helpers.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_analytics_db.dart';
import 'week_start_oracle.dart';

/// The mocked first day of the week for the next pump.
void setFirstDay(int first, {Map<String, Object> more = const {}}) =>
    SharedPreferences.setMockInitialValues({'first_day_of_week': first, ...more});

void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A fresh Analytics (a new visit, not an update of the old tree).
Future<void> pumpAnalytics(WidgetTester tester, FakeAnalyticsDb db, DateTime now, {Object? args}) async {
  tall(tester);
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => AnalyticsScreen(db: db, clock: () => now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _label(WidgetTester tester, int i) => tester
    .widget<Semantics>(find.ancestor(of: find.byKey(Key('analyticsBar-$i')), matching: find.byType(Semantics)).first)
    .properties
    .label!;

int barCount() {
  var n = 0;
  while (find.byKey(Key('analyticsBar-$n')).evaluate().isNotEmpty) {
    n++;
  }
  return n;
}

/// The Month chart's bar names reduced to "4-10" (or "1" for a one-day piece).
List<String> weekBars(WidgetTester tester) => [for (var i = 0; i < barCount(); i++) _label(tester, i).split(' ').first];

/// The Week chart's bars: the first two letters of each day.
List<String> dayBars(WidgetTester tester) => [for (var i = 0; i < barCount(); i++) _label(tester, i).substring(0, 2)];

/// Every bar's full accessibility label (the Custom chart's "20 Aug to 22 Aug").
List<String> barNames(WidgetTester tester) => [for (var i = 0; i < barCount(); i++) _label(tester, i)];

String periodValue(WidgetTester t) => t
    .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text)))
    .data!;

Future<void> pickGranularity(WidgetTester t, String label) async {
  await t.tap(find.byKey(const Key('analyticsGranularity')));
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

/// The Week view shows the week holding [anchor]: pill text, seven bars, the
/// first bar on the chosen weekday, then the weekdays in order.
void expectWeekShown(WidgetTester t, DateTime anchor, int first, String why) {
  final days = weekDays(anchor, first);
  chk(periodValue(t), spanText(days.first, days.last), reason: '$why: week pill text');
  chk(dayBars(t), [for (final d in days) kDayInitials[d.weekday - 1]], reason: '$why: week bars');
  chk(dayBars(t).first, kDayInitials[first - 1], reason: '$why: first bar is the chosen weekday');
}

/// The Month view shows month (y, m) cut into weeks on the chosen weekday.
void expectMonthShown(WidgetTester t, int y, int m, int first, String why) {
  chk(periodValue(t), '${kMonthShort[m - 1]} $y', reason: '$why: month pill text');
  chk(weekBars(t), [for (final s in monthSegments(y, m, first)) s.label], reason: '$why: month week bars ($y-$m)');
}
