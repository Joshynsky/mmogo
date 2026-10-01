// T21 — the reworked Analytics screen (lib/ui/screens/analytics_screen.dart),
// built to the approved analytics mock (v4, view B).
//
// Replaces T9's tests of the Week-tab tap/double-tap escalation and the
// "Month · Custom" link, which T21 removed. Driven through the screen's
// `db:` / `clock:` seams with FakeAnalyticsDb (a real sqflite Database hangs
// inside testWidgets here); "now" is Thu 24 Sep 2026, 13:30 with the mock's
// sample data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? rows,
  Object? args,
  Brightness brightness = Brightness.light,
  Size size = const Size(400, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final db = FakeAnalyticsDb(rows ?? analyticsSampleRows());
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => AnalyticsScreen(db: db, clock: () => analyticsTestNow),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return db;
}

Finder _rich(String text) => find.text(text, findRichText: true);

String _pillGranularity(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsGranularity')), matching: find.byType(Text)))
    .data!;

String _pillValue(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text)))
    .data!;

String _total(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).data!;

String _chartTitle(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('analyticsChartTitle'))).data!;

Future<void> _pickFromMenu(WidgetTester tester, Key button, String item) async {
  await tester.tap(find.byKey(button));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('from the nav bar: the last 7 days', () {
    testWidgets('pill, total, change pill and facts match the mock', (tester) async {
      await _pump(tester);
      expect(_pillGranularity(tester), 'Week');
      expect(_pillValue(tester), '18–24 Sep');
      expect(find.byKey(const Key('analyticsSpentLabel')), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(_total(tester), '4,050.00');
      expect(find.text('Ksh'), findsOneWidget);
      // 4,050 vs 2,300 the week before.
      expect(find.text('▲ 76% vs prior week'), findsOneWidget);
      expect(_rich('4 transactions'), findsOneWidget);
      expect(_rich('avg Ksh 579/day'), findsOneWidget);
      expect(_rich('fees Ksh 37'), findsOneWidget);
      expect(_chartTitle(tester), 'BY DAY');
      expect(find.text('Tap a day to open it · swipe for other weeks'), findsOneWidget);
    });

    testWidgets('transactions grouped by day, newest first, with day totals, meta and fees', (tester) async {
      await _pump(tester);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Sun, 20 Sep'), findsOneWidget);
      expect(find.text('Ksh 2,350.00'), findsOneWidget); // today's day total
      final john = tester.getTopLeft(find.text('JOHN KAMAU'));
      final naivas = tester.getTopLeft(find.text('NAIVAS SUPERMARKET'));
      expect(naivas.dy, lessThan(john.dy), reason: '11:00 before 09:00');
      expect(find.text('Family/Friends · 09:00 · CODE1'), findsOneWidget);
      expect(find.text('+ Ksh 22 fee'), findsOneWidget);
      // Cash: no code, no fee line.
      expect(find.text('Cash — Groceries'), findsOneWidget);
      expect(find.text('Groceries · 17:00'), findsOneWidget);
      // Out of the period.
      expect(find.text('MARY WANJIKU'), findsNothing);
      expect(find.text('Swipe a row right to edit, left to delete'), findsNothing, reason: 'the tour says it now');
    });

    testWidgets('the whole data window (period, prior, chart bars) comes from one real-DAO query', (tester) async {
      final db = await _pump(tester);
      final (start, end) = db.windows.last;
      expect(DateTime.fromMillisecondsSinceEpoch(start!), DateTime(2026, 9, 11));
      expect(DateTime.fromMillisecondsSinceEpoch(end!), DateTime(2026, 9, 24, 23, 59, 59, 999));
    });
  });

  group('the period pill', () {
    testWidgets('left half: the length menu; Month shows this month and clears filters', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsTypeTile-PAYBILL')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);

      await tester.tap(find.byKey(const Key('analyticsGranularity')));
      await tester.pumpAndSettle();
      for (final item in ['All time', 'Year', 'Month', 'Day']) {
        expect(find.text(item), findsOneWidget);
      }
      await tester.tap(find.text('Month'));
      await tester.pumpAndSettle();
      expect(_pillGranularity(tester), 'Month');
      expect(_pillValue(tester), 'Sep 2026');
      expect(_total(tester), '6,990.00'); // everything in September
      expect(find.text('▲ 299% vs last month'), findsOneWidget); // vs August's 1,750
      expect(_chartTitle(tester), 'BY MONTH');
      expect(
        find.byKey(const Key('analyticsFilterChipType')),
        findsNothing,
        reason: 'a period change clears filters',
      );
    });

    testWidgets('right half: pick another week from the list', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsPeriodValue')));
      await tester.pumpAndSettle();
      expect(find.text('last 7 days'), findsOneWidget);
      await tester.tap(find.text('11 Sep – 17 Sep'));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '11–17 Sep');
      expect(_total(tester), '2,300.00');
      expect(find.text('MARY WANJIKU'), findsOneWidget);
    });

    testWidgets('All time: no change pill, "since Aug 2026", bars by month since you started', (tester) async {
      await _pump(tester);
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'All time');
      expect(_pillValue(tester), 'since Aug 2026');
      expect(_total(tester), '8,740.00');
      expect(find.byKey(const Key('analyticsChange')), findsNothing);
      expect(_chartTitle(tester), 'BY MONTH SINCE YOU STARTED');
    });

    testWidgets('Day: no avg fact; "vs day before"; 6 time-of-day bars', (tester) async {
      await _pump(tester);
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Day');
      expect(_pillValue(tester), 'Today');
      expect(_total(tester), '2,350.00');
      expect(find.text('▲ 96% vs day before'), findsOneWidget); // vs 1,200 yesterday
      expect(find.byKey(const Key('analyticsFactAvg')), findsNothing);
      expect(_chartTitle(tester), 'BY TIME OF DAY');
      expect(find.byKey(const Key('analyticsBar-5')), findsOneWidget);
      expect(find.byKey(const Key('analyticsBar-6')), findsNothing);
    });

    testWidgets('the calendar opens the Custom sheet; Show applies the dates', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsCalendar')));
      await tester.pumpAndSettle();
      expect(find.text('Custom dates'), findsOneWidget);
      expect(find.text('18 Sep 2026'), findsOneWidget);
      expect(find.text('24 Sep 2026'), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsCustomShow')));
      await tester.pumpAndSettle();
      expect(_pillGranularity(tester), 'Custom');
      expect(_pillValue(tester), '18–24 Sep');
      expect(find.text('▲ 76% vs previous 7 days'), findsOneWidget);
      // On Custom the right half reopens the sheet.
      await tester.tap(find.byKey(const Key('analyticsPeriodValue')));
      await tester.pumpAndSettle();
      expect(find.text('Custom dates'), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsCustomCancel')));
      await tester.pumpAndSettle();
      expect(find.text('Custom dates'), findsNothing);
    });
  });

  group('the chart', () {
    testWidgets('‹ steps back, › is disabled at the present', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsNext')));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '18–24 Sep', reason: 'Next is disabled');
      await tester.tap(find.byKey(const Key('analyticsPrev')));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '11–17 Sep');
      await tester.tap(find.byKey(const Key('analyticsNext')));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '18–24 Sep');
    });

    testWidgets('swipe right = earlier, left = later; a short drag does nothing', (tester) async {
      await _pump(tester);
      final chart = find.byKey(const Key('analyticsChart'));
      await tester.drag(chart, const Offset(30, 0));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '18–24 Sep');
      await tester.drag(chart, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '11–17 Sep');
      await tester.drag(chart, const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '18–24 Sep');
    });

    testWidgets('tapping a day bar opens that Day', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsBar-5'))); // Wed 23 Sep
      await tester.pumpAndSettle();
      expect(_pillGranularity(tester), 'Day');
      expect(_pillValue(tester), 'Yesterday');
      expect(_total(tester), '1,200.00');
    });
  });

  group('By type | Where it went, type and category together (T26)', () {
    testWidgets('a type tile filters the list, shows its own chip, fades the others; ✕ clears', (tester) async {
      await _pump(tester);
      expect(find.text('37%'), findsOneWidget); // Send Money 1,500 of 4,050
      await tester.tap(find.byKey(const Key('analyticsTypeTile-BUY_GOODS')));
      await tester.pumpAndSettle();
      expect(find.text('Buy Goods · Ksh 850'), findsOneWidget);
      expect(find.text('JOHN KAMAU'), findsNothing);
      expect(find.text('NAIVAS SUPERMARKET'), findsOneWidget);
      final faded = tester.widget<Opacity>(
        find.descendant(of: find.byKey(const Key('analyticsTypeTile-CASH')), matching: find.byType(Opacity)).first,
      );
      expect(faded.opacity, 0.5);
      await tester.tap(find.byKey(const Key('analyticsFilterChipType')));
      await tester.pumpAndSettle();
      expect(find.text('JOHN KAMAU'), findsOneWidget);
      expect(find.byKey(const Key('analyticsFilterChipType')), findsNothing);
    });

    testWidgets('a class row filters the list across types; ✕ clears', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      // Shopping = Paybill 1,200 + Buy Goods 850, one merged row.
      expect(find.byKey(const Key('analyticsWhere-Shopping')), findsOneWidget);
      expect(find.text('Ksh 2,050.00'), findsOneWidget);
      expect(find.textContaining('2×', findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsWhere-Shopping')));
      await tester.pumpAndSettle();
      expect(find.text('Shopping · Ksh 2,050'), findsOneWidget);
      expect(find.text('DSTV KENYA'), findsOneWidget);
      expect(find.text('NAIVAS SUPERMARKET'), findsOneWidget);
      expect(find.text('JOHN KAMAU'), findsNothing);
      await tester.tap(find.byKey(const Key('analyticsFilterChipClass')));
      await tester.pumpAndSettle();
      expect(find.text('JOHN KAMAU'), findsOneWidget);
      expect(find.byKey(const Key('analyticsFilterChipClass')), findsNothing);
    });

    testWidgets("Where it went respects an active type filter: only that type's classifications", (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsTypeTile-CASH')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      // Only Cash's own classification (Groceries, Ksh 500) shows; Shopping
      // (Paybill + Buy Goods) is excluded by the Cash type filter.
      expect(find.byKey(const Key('analyticsWhere-Groceries')), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const Key('analyticsWhere-Groceries')), matching: find.text('Ksh 500.00')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('analyticsWhere-Shopping')), findsNothing);
    });

    testWidgets('By type respects an active class filter: amounts within that class', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsWhere-Shopping')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsTabType')));
      await tester.pumpAndSettle();
      // Shopping-only: Buy Goods 850 (21% of the 4,050 week) and Paybill
      // 1,200 (30%); Send Money and Cash have no Shopping spend.
      expect(find.text('21%'), findsOneWidget);
      expect(find.text('30%'), findsOneWidget);
      expect(find.text('Ksh 0.00'), findsNWidgets(2));
    });

    testWidgets('a type tile then a class row combine (AND); each chip ✕ clears only its own filter', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsTypeTile-BUY_GOODS')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsWhere-Shopping')));
      await tester.pumpAndSettle();

      expect(find.text('Buy Goods · Ksh 850'), findsOneWidget);
      expect(find.text('Shopping · Ksh 850'), findsOneWidget);
      expect(find.text('NAIVAS SUPERMARKET'), findsOneWidget);
      expect(find.text('DSTV KENYA'), findsNothing, reason: 'Paybill is excluded by the Buy Goods type filter');
      expect(find.text('JOHN KAMAU'), findsNothing);

      // The type chip's ✕ clears only the type filter; the class filter
      // (and its chip) stays, now matching Shopping across every type.
      await tester.tap(find.byKey(const Key('analyticsFilterChipType')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsFilterChipType')), findsNothing);
      expect(find.byKey(const Key('analyticsFilterChipClass')), findsOneWidget);
      expect(find.text('DSTV KENYA'), findsOneWidget);
      expect(find.text('NAIVAS SUPERMARKET'), findsOneWidget);
    });

    testWidgets('Where it went shows the top 4, then Show all N / Show fewer', (tester) async {
      final rows = [
        for (var i = 0; i < 6; i++)
          fakeTx(id: 50 + i, at: DateTime(2026, 9, 22, 8 + i), amountCents: 10000 * (i + 1), classification: 'C$i'),
      ];
      await _pump(tester, rows: rows);
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsWhere-C5')), findsOneWidget);
      expect(find.byKey(const Key('analyticsWhere-C1')), findsNothing);
      expect(find.text('Show all 6'), findsOneWidget);
      await tester.tap(find.text('Show all 6'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsWhere-C0')), findsOneWidget);
      expect(find.text('Show fewer'), findsOneWidget);
    });

    testWidgets('an empty period: the mock empty states', (tester) async {
      await _pump(tester, rows: const []);
      expect(find.text('No transactions in this period.'), findsOneWidget);
      expect(find.text('no spending'), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsTabWhere')));
      await tester.pumpAndSettle();
      expect(find.text('Nothing to break down in this period.'), findsOneWidget);
    });
  });

  group('pull to refresh = back to now', () {
    testWidgets('from an older week: back to the last 7 days, filters cleared', (tester) async {
      await _pump(tester, size: const Size(400, 900));
      await tester.tap(find.byKey(const Key('analyticsPrev')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsTypeTile-SEND_MONEY')));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '11–17 Sep');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);

      await tester.fling(find.byKey(const Key('analyticsScroll')), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '18–24 Sep');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsNothing);
    });
  });

  group('Ocean & Sun, light and dark', () {
    for (final (brightness, palette) in [(Brightness.light, AppPalette.light), (Brightness.dark, AppPalette.dark)]) {
      testWidgets('${brightness.name} phone -> ${brightness.name} tokens', (tester) async {
        await _pump(tester, brightness: brightness);
        expect(tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor, palette.background);
        expect(tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).style!.color, palette.ink);
        expect(tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).style!.fontSize, 32);
        final change = tester.widget<Container>(find.byKey(const Key('analyticsChange')));
        expect((change.decoration! as BoxDecoration).color, palette.diffUp.withValues(alpha: 0.12));
        final granularity = tester.widget<Material>(
          find.ancestor(of: find.byKey(const Key('analyticsGranularity')), matching: find.byType(Material)).first,
        );
        expect(granularity.color, palette.primary);
      });
    }
  });
}
