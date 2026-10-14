// 0.1.2 S6b on the Analytics screen: the change pill and its progress cue, Month
// by weeks / days (tooltip on the first tap, the whole week on the second, the
// "Week crosses into" line), Year quarter / month lines, All time five-year
// blocks with Previous / Next, and the legend. Same fake-db approach as
// analytics_screen_test.dart. "Now" is Thu 24 Sep 2026 unless a test says so.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics/parts.dart';
import 'package:mmogo/ui/screens/analytics/swipe_chart.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  DateTime? now,
  List<Map<String, Object?>>? rows,
}) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(rows ?? analyticsSampleRows());
  await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => now ?? analyticsTestNow)));
  await tester.pumpAndSettle();
  return db;
}

Future<void> _pick(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('analyticsGranularity')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

String _pillValue(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text))).data!;
String _pillGran(WidgetTester t) =>
    t.widget<Text>(find.descendant(of: find.byKey(const Key('analyticsGranularity')), matching: find.byType(Text))).data!;
String _title(WidgetTester t) => t.widget<Text>(find.byKey(const Key('analyticsChartTitle'))).data!;
ChartSpec _spec(WidgetTester t) => t.widget<AnalyticsSwipeChart>(find.byType(AnalyticsSwipeChart)).spec;
AnalyticsSwipeChart _chart(WidgetTester t) => t.widget<AnalyticsSwipeChart>(find.byType(AnalyticsSwipeChart));
String _pill(WidgetTester t) => t.widget<Text>(find.descendant(of: find.byKey(const Key('analyticsChange')), matching: find.byType(Text))).data!;
bool _enabled(WidgetTester t, String key) => t.widget<AnalyticsRoundButton>(find.byKey(Key(key))).onTap != null;

/// How many stripe lines (the 2.5 wide light lines of a part week) the chart paints:
/// the painter is run against a recording canvas.
int _stripeLines(WidgetTester t) {
  final cp = t.widget<CustomPaint>(find.byKey(const Key('analyticsChartPaint')));
  final canvas = TestRecordingCanvas();
  cp.painter!.paint(canvas, const Size(320, 146));
  return canvas.invocations
      .where((i) => i.invocation.memberName == #drawLine && (i.invocation.positionalArguments[2] as Paint).strokeWidth == 2.5)
      .length;
}

Future<void> _tapBar(WidgetTester t, int i) async {
  await t.tap(find.byKey(Key('analyticsBar-$i')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the change pill and the progress cue', () {
    testWidgets('Week day 2 of 7: the cue "2/7" replaces the pill, with its words as label and tooltip', (t) async {
      await _pump(t, now: DateTime(2026, 9, 22, 12));
      expect(_pill(t), '2/7');
      expect(find.textContaining('▲'), findsNothing);
      expect(find.textContaining('vs last week'), findsNothing);
      expect(find.bySemanticsLabel('Day 2 of 7. The change shows from day 4'), findsOneWidget);
      expect(find.byTooltip('Day 2 of 7; the change shows from day 4'), findsOneWidget);
    });

    testWidgets('the cue sits at the far right of the total row, like a pill', (t) async {
      await _pump(t, now: DateTime(2026, 9, 22, 12));
      final pillRight = t.getTopRight(find.byKey(const Key('analyticsChange'))).dx;
      final totalLeft = t.getTopLeft(find.byKey(const Key('analyticsTotal'))).dx;
      expect(pillRight, greaterThan(300), reason: 'right edge of a 400 wide screen minus the card padding');
      expect(pillRight, lessThanOrEqualTo(400 - 14 - 14 + 1));
      expect(totalLeft, lessThan(100));
    });

    testWidgets('Week day 4 shows the change with its caption', (t) async {
      await _pump(t); // Thursday
      expect(_pill(t), '▲ 27% vs last week');
    });

    testWidgets('Month day 8 of 31: "8/31"; the words say from day 16', (t) async {
      await _pump(t, now: DateTime(2026, 8, 8, 12));
      await _pick(t, 'Month');
      expect(_pillValue(t), 'Aug 2026');
      expect(_pill(t), '8/31');
      expect(find.bySemanticsLabel('Day 8 of 31. The change shows from day 16'), findsOneWidget);
    });

    testWidgets('Month from the middle: day 16 of 31 shows the change', (t) async {
      final rows = [...analyticsSampleRows(), fakeTx(id: 98, at: DateTime(2026, 7, 10, 9), amountCents: 100000)];
      await _pump(t, now: DateTime(2026, 8, 16, 12), rows: rows);
      await _pick(t, 'Month');
      expect(_pill(t), '▲ 75% vs last month'); // Aug 1,750 against July 1,000
    });

    testWidgets('Year in May: the month number "5/12"; from July the change', (t) async {
      await _pump(t, now: DateTime(2026, 5, 20, 12));
      await _pick(t, 'Year');
      expect(_pill(t), '5/12');
      expect(find.bySemanticsLabel('Month 5 of 12. The change shows from July'), findsOneWidget);
    });

    testWidgets('a past week shows the change however early the current week is', (t) async {
      await _pump(t, now: DateTime(2026, 9, 22, 12));
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      expect(_pillValue(t), '14–20 Sep');
      expect(_pill(t), 'nothing before to compare', reason: 'a past week shows its pill, not a cue (the week before it holds nothing)');
    });

    testWidgets('All time has no pill', (t) async {
      await _pump(t);
      await _pick(t, 'All time');
      expect(find.byKey(const Key('analyticsChange')), findsNothing);
    });
  });

  group('Month by weeks', () {
    testWidgets('five segments of Sep 2026, the part weeks carry their day counts and are striped, with the legend', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      expect(_title(t), 'BY WEEK OF THE MONTH');
      expect(find.byKey(const Key('analyticsBar-4')), findsOneWidget);
      expect(find.byKey(const Key('analyticsBar-5')), findsNothing);
      expect([for (final b in _spec(t).buckets) b.sub], ['6 days', '', '', '', '3 days']);
      expect([for (final b in _spec(t).buckets) b.part], [true, false, false, false, true]);
      expect(find.text('Striped bar = part week (fewer than 7 days in this month)'), findsOneWidget);
      expect(_stripeLines(t), greaterThan(0), reason: 'the stripes over a part week are painted');
    });

    testWidgets('a month made of whole weeks has no legend and no stripes (Feb 2027)', (t) async {
      final rows = [
        fakeTx(id: 1, at: DateTime(2027, 2, 3, 9), amountCents: 100000),
        fakeTx(id: 2, at: DateTime(2027, 2, 10, 9), amountCents: 200000),
      ];
      await _pump(t, now: DateTime(2027, 2, 20, 12), rows: rows);
      await _pick(t, 'Month');
      expect(_spec(t).buckets, hasLength(4));
      expect(find.textContaining('Striped bar'), findsNothing);
      expect(_stripeLines(t), 0);
    });

    testWidgets('first tap = tooltip, second tap = the WHOLE week; a part week says where it crosses', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await _tapBar(t, 0); // 1-6 Sep, holds the 640 Java House row
      expect(find.byKey(const Key('analyticsChartTip')), findsOneWidget);
      expect(find.text('1-6 Sep · 6 days'), findsOneWidget);
      expect(find.text('Ksh 640 · avg Ksh 107/day'), findsOneWidget);
      expect(find.text('Tap again to open the week'), findsOneWidget);
      expect(_pillGran(t), 'Month', reason: 'the first tap only shows the tooltip');
      await _tapBar(t, 0);
      expect(_pillGran(t), 'Week');
      expect(_pillValue(t), '31 Aug – 6 Sep', reason: 'the whole calendar week, not the part in September');
      expect(find.byKey(const Key('analyticsCrossNote')), findsOneWidget);
      expect(find.text('Week crosses into August'), findsOneWidget);
      // Any other period change clears the line.
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('analyticsCrossNote')), findsNothing);
    });

    testWidgets('a full week inside the month opens with no crossing line', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await _tapBar(t, 3); // 21-27 Sep
      expect(find.text('21-27 Sep · 7 days'), findsOneWidget);
      await _tapBar(t, 3);
      expect(_pillValue(t), '21–27 Sep');
      expect(find.byKey(const Key('analyticsCrossNote')), findsNothing);
    });

    testWidgets('a tapped bar then another: the tooltip moves, nothing opens', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await _tapBar(t, 1);
      await _tapBar(t, 2);
      expect(_pillGran(t), 'Month');
      expect(find.text('14-20 Sep · 7 days'), findsOneWidget);
      expect(find.text('7-13 Sep · 7 days'), findsNothing);
    });

    testWidgets('the tooltip goes away when the chart shows another month', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await _tapBar(t, 1);
      expect(find.byKey(const Key('analyticsChartTip')), findsOneWidget);
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('analyticsChartTip')), findsNothing);
    });

    testWidgets('a segment that has not started cannot be tapped', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await _tapBar(t, 4); // 28-30 Sep, still to come
      expect(find.byKey(const Key('analyticsChartTip')), findsNothing);
      expect(_pillGran(t), 'Month');
    });

    testWidgets('Previous steps one month (August), never a six-month window', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      expect(_pillValue(t), 'Aug 2026');
      expect(_spec(t).buckets.first.label, '1-2');
      expect(_spec(t).buckets, hasLength(6));
    });
  });

  group('Month by days (the preference)', () {
    testWidgets('30 bars for September, the tap shows the day, the second tap opens it', (t) async {
      SharedPreferences.setMockInitialValues({'month_chart_style': 'days'});
      await _pump(t);
      await _pick(t, 'Month');
      expect(_title(t), 'BY DAY');
      expect(_spec(t).buckets, hasLength(30));
      expect(find.byKey(const Key('analyticsBar-29')), findsOneWidget);
      expect(find.text('Striped bar = part week (fewer than 7 days in this month)'), findsNothing);
      await _tapBar(t, 2); // Thu 3 Sep, 640
      expect(find.text('Thu 3 Sep'), findsWidgets);
      expect(find.text('Ksh 640'), findsWidgets);
      expect(find.text('Tap again to open the day'), findsOneWidget);
      expect(_pillGran(t), 'Month');
      await _tapBar(t, 2);
      expect(_pillGran(t), 'Day');
      expect(_pillValue(t), 'Thu 3 Sep');
    });
  });

  group('Year', () {
    testWidgets('quarters (default): one spanning line per three months with the quarter total, none for the empty ones', (t) async {
      await _pump(t);
      await _pick(t, 'Year');
      expect(_title(t), 'BY MONTH');
      final lines = chartAmountLines(_spec(t), _chart(t).bucketCents);
      expect(lines, hasLength(4));
      expect([for (final l in lines) l.label], ['', '', '8740', ''], reason: 'Q3 = Aug 1,750 + Sep 6,990, rounded shillings');
      expect(lines[3].off, isTrue, reason: 'Oct-Dec have not started');
      expect(find.textContaining('Q1'), findsNothing);
    });

    testWidgets('months (the preference): each month has its own line, compact when it must be', (t) async {
      SharedPreferences.setMockInitialValues({'year_view_amounts': 'months'});
      await _pump(t);
      await _pick(t, 'Year');
      final lines = chartAmountLines(_spec(t), _chart(t).bucketCents);
      expect(lines, hasLength(12));
      expect(lines[7].label, '1750'); // Aug
      expect(lines[8].label, '6990'); // Sep
      expect(lines[6].label, '', reason: 'July has no spending');
      expect(lines.sublist(9).every((l) => l.off && l.label.isEmpty), isTrue);
    });

    testWidgets('big figures use the compact form (48k)', (t) async {
      final rows = [fakeTx(id: 1, at: DateTime(2026, 9, 2, 9), amountCents: 4800000)];
      await _pump(t, rows: rows);
      await _pick(t, 'Year');
      expect([for (final l in chartAmountLines(_spec(t), _chart(t).bucketCents)) l.label], ['', '', '48k', '']);
    });

    testWidgets('the chart is taller to make room for the amount lines', (t) async {
      await _pump(t);
      final week = t.getSize(find.byKey(const Key('analyticsChartPaint'))).height;
      await _pick(t, 'Year');
      final year = t.getSize(find.byKey(const Key('analyticsChartPaint'))).height;
      expect(year, greaterThan(week));
    });
  });

  group('All time: five-year blocks', () {
    testWidgets('2026-2030, Previous disabled (nothing before 2026), Next disabled', (t) async {
      await _pump(t);
      await _pick(t, 'All time');
      expect(_title(t), 'BY YEAR, 2026 TO 2030');
      expect([for (final b in _spec(t).buckets) b.label], ['2026', '2027', '2028', '2029', '2030']);
      expect(_enabled(t, 'analyticsPrev'), isFalse);
      expect(_enabled(t, 'analyticsNext'), isFalse);
      expect(find.byKey(const Key('analyticsChange')), findsNothing, reason: 'no comparison between blocks');
    });

    testWidgets('older data: Previous opens 2021-2025, Next comes back and is disabled on the current block', (t) async {
      final rows = [...analyticsSampleRows(), fakeTx(id: 99, at: DateTime(2023, 3, 3, 9), amountCents: 90000)];
      await _pump(t, rows: rows);
      await _pick(t, 'All time');
      expect(_enabled(t, 'analyticsPrev'), isTrue);
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      expect(_title(t), 'BY YEAR, 2021 TO 2025');
      expect(_enabled(t, 'analyticsPrev'), isFalse, reason: 'the first transaction is inside this block');
      expect(_enabled(t, 'analyticsNext'), isTrue);
      expect(_pillGran(t), 'All time');
      await t.tap(find.byKey(const Key('analyticsNext')));
      await t.pumpAndSettle();
      expect(_title(t), 'BY YEAR, 2026 TO 2030');
      expect(_enabled(t, 'analyticsNext'), isFalse);
    });

    testWidgets('a year bar with data opens that Year; one without does nothing', (t) async {
      await _pump(t);
      await _pick(t, 'All time');
      await _tapBar(t, 1); // 2027: nothing
      expect(_pillGran(t), 'All time');
      await _tapBar(t, 0);
      expect(_pillGran(t), 'Year');
      expect(_pillValue(t), '2026');
    });
  });

  group('stepping keeps its anchor (the S6a Q1 test still covers the highlight)', () {
    testWidgets('Month: Previous then Next returns to the same month', (t) async {
      await _pump(t);
      await _pick(t, 'Month');
      await t.tap(find.byKey(const Key('analyticsPrev')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('analyticsNext')));
      await t.pumpAndSettle();
      expect(_pillValue(t), 'Sep 2026');
      expect(_enabled(t, 'analyticsNext'), isFalse);
    });
  });
}
