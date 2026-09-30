// T21 — how Analytics is reached (lib/ui/screens/analytics_screen.dart):
//  - from a Home row (a plain int id): the Day of that transaction, the row
//    scrolled to about a third of the way down and lit in the `hl` colour
//    for about 1.8 s. (Replaces T9's "the rolling week containing it" test,
//    analytics_home_handoff_test.dart. Home still passes tx.id — asserted in
//    home_screen_test.dart, unchanged.)
//  - from Paid to (type + partyKey; T22, was Parties): one recipient on Paid
//    to's period (all time when none is passed), the party header card AND
//    the period pill (T22: visible, stepping allowed); ✕ returns to the
//    state before;
//  - from Paid to's unnamed / type-only shortcut (type alone): that period
//    (all time when none, F8) with the type filter on, plus the
//    classification filter too when one is given (T26: both together).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/domain/analytics/analytics_period.dart';
import 'package:mymog/domain/counterparty/counterparty_key.dart';
import 'package:mymog/domain/parsing/parsed_sms_fields.dart';
import 'package:mymog/ui/screens/analytics_screen.dart';
import 'package:mymog/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

const _phone = Size(392, 850);

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  required List<Map<String, Object?>> rows,
  Object? args,
  Brightness brightness = Brightness.light,
  bool failLookup = false,
}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final db = FakeAnalyticsDb(rows, failLookup: failLookup);
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => AnalyticsScreen(db: db, clock: () => analyticsTestNow),
      ),
    ),
  );
  // Load, lay the rows out, then let the 300ms scroll-into-view run (well
  // inside the 1.8s highlight).
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 400));
  return db;
}

Finder _t(String text) => find.text(text, skipOffstage: false);

Color? _rowColor(WidgetTester tester, String name) {
  final c = tester.widget<AnimatedContainer>(
    find.ancestor(of: _t(name), matching: find.byType(AnimatedContainer, skipOffstage: false)).first,
  );
  return (c.decoration as BoxDecoration?)?.color;
}

String? _pillText(WidgetTester tester, String key) {
  final f = find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

/// Lets the highlight run out so no timer is left pending.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// The sample data plus 10 later and 10 earlier rows on 3 Sep, so JAVA
/// HOUSE (08:00) starts below the fold with rows under it too (room to
/// scroll it up to about a third of the way down).
List<Map<String, Object?>> _rowsWithBusyDay() => [
  ...analyticsSampleRows(),
  for (var i = 0; i < 10; i++)
    fakeTx(id: 200 + i, at: DateTime(2026, 9, 3, 12 + i ~/ 2, i), label: 'FILLER $i', amountCents: 1000),
  for (var i = 0; i < 10; i++)
    fakeTx(id: 300 + i, at: DateTime(2026, 9, 3, i ~/ 2, i), label: 'EARLY $i', amountCents: 1000),
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('from a Home row', () {
    for (final (brightness, palette) in [(Brightness.light, AppPalette.light), (Brightness.dark, AppPalette.dark)]) {
      testWidgets('${brightness.name}: opens the Day of that transaction, scrolls it to ~⅓ and lights it', (
        tester,
      ) async {
        final db = await _pump(tester, rows: _rowsWithBusyDay(), args: 7, brightness: brightness);
        expect(db.lookedUpIds, [7]);
        expect(_t('JAVA HOUSE'), findsOneWidget);
        expect(_t('FILLER 0'), findsOneWidget);
        expect(_t('JOHN KAMAU'), findsNothing, reason: 'not on 3 Sep');

        final row = tester.getRect(_t('JAVA HOUSE'));
        expect(row.top, greaterThan(0));
        expect(row.bottom, lessThan(_phone.height - 80));
        expect(row.top, closeTo(_phone.height / 3, 160), reason: 'about a third of the way down');
        expect(_rowColor(tester, 'JAVA HOUSE'), palette.highlight);
        expect(_rowColor(tester, 'FILLER 0'), palette.card);
        expect(palette.highlight, brightness == Brightness.light ? const Color(0xFFFFF4D6) : const Color(0xFF3A3320));

        await _drain(tester);
        expect(_rowColor(tester, 'JAVA HOUSE'), palette.card);

        // Back at the top: the Day pill.
        await tester.drag(find.byKey(const Key('analyticsScroll')), const Offset(0, 3000));
        await tester.pumpAndSettle();
        expect(_pillText(tester, 'analyticsGranularity'), 'Day');
        expect(_pillText(tester, 'analyticsPeriodValue'), 'Thu 3 Sep');
      });
    }

    testWidgets('a transaction from today: Day = Today, lit', (tester) async {
      await _pump(tester, rows: analyticsSampleRows(), args: 1);
      expect(_pillText(tester, 'analyticsPeriodValue'), 'Today');
      expect(_rowColor(tester, 'JOHN KAMAU'), AppPalette.light.highlight);
      expect(_t('DSTV KENYA'), findsNothing);
      await _drain(tester);
    });

    testWidgets('a row soft-deleted in between: the nav-bar default, no highlight', (tester) async {
      final rows = analyticsSampleRows();
      rows.firstWhere((r) => r['id'] == 7)['deleted_at'] = analyticsTestNow.millisecondsSinceEpoch;
      await _pump(tester, rows: rows, args: 7);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_pillText(tester, 'analyticsGranularity'), 'Week');
      expect(_pillText(tester, 'analyticsPeriodValue'), '18–24 Sep');
      expect(_rowColor(tester, 'JOHN KAMAU'), AppPalette.light.card);
    });

    testWidgets('an unknown id or a failing lookup: the nav-bar default, no crash', (tester) async {
      await _pump(tester, rows: analyticsSampleRows(), args: 9999);
      await tester.pumpAndSettle();
      expect(_pillText(tester, 'analyticsPeriodValue'), '18–24 Sep');

      await _pump(tester, rows: analyticsSampleRows(), args: 7, failLookup: true);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(_pillText(tester, 'analyticsPeriodValue'), '18–24 Sep');
    });
  });

  group('from Paid to', () {
    final maryKey = deriveCounterpartyKey(
      sourceType: SmsSourceType.sendMoney,
      counterpartyLabel: 'MARY WANJIKU',
      counterpartyPhone: '0712345678',
    );

    testWidgets('one recipient, no period passed: all time, the card AND the pill, "Paid to them", N payments', (
      tester,
    ) async {
      await _pump(
        tester,
        rows: analyticsSampleRows(),
        args: AnalyticsRouteArgs(type: 'SEND_MONEY', partyKey: maryKey),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      expect(find.text('MARY WANJIKU'), findsOneWidget); // the row (the strip is one rich line)
      expect(find.text('MW'), findsOneWidget);
      expect(find.text('MARY WANJIKU · Send Money'), findsOneWidget); // the pinned strip
      expect(find.text('Paid to them'), findsOneWidget);
      // T22: the pill is visible in the recipient view.
      expect(_pillText(tester, 'analyticsGranularity'), 'All time');
      expect(find.byKey(const Key('analyticsCalendar')), findsOneWidget);
      expect(find.text('1 payment'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).data, '2,000.00');
      expect(find.text('JOHN KAMAU'), findsNothing);

      // ✕ returns to the nav-bar default.
      await tester.tap(find.byKey(const Key('analyticsPartyClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
      expect(_pillText(tester, 'analyticsGranularity'), 'Week');
      expect(_pillText(tester, 'analyticsPeriodValue'), '18–24 Sep');
      expect(find.text('Spent'), findsOneWidget);
    });

    testWidgets('F3: the party strip is pinned: it stays put while the Analytics list scrolls', (tester) async {
      await _pump(
        tester,
        rows: analyticsSampleRows(),
        args: AnalyticsRouteArgs(type: 'SEND_MONEY', partyKey: maryKey),
      );
      await tester.pumpAndSettle();
      final card = find.byKey(const Key('analyticsPartyCard'));
      final topBefore = tester.getTopLeft(card).dy;
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: find.byKey(const Key('analyticsScroll')), matching: find.byType(Scrollable)),
      );
      scrollable.position.jumpTo(300.0.clamp(0, scrollable.position.maxScrollExtent));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, greaterThan(0), reason: 'the list really scrolled');
      expect(card, findsOneWidget);
      expect(tester.getTopLeft(card).dy, topBefore);
      expect(card.hitTestable(), findsOneWidget);
    });

    testWidgets("T22: on Paid to's period with its category; stepping keeps the recipient; close restores", (
      tester,
    ) async {
      await _pump(
        tester,
        rows: analyticsSampleRows(),
        args: AnalyticsRouteArgs(
          type: 'SEND_MONEY',
          partyKey: maryKey,
          partyName: 'MARY WANJIKU',
          period: AnalyticsPeriod.year(2026, today: analyticsTestNow),
          classification: 'Rent',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      expect(_pillText(tester, 'analyticsGranularity'), 'Year');
      expect(_pillText(tester, 'analyticsPeriodValue'), '2026');
      expect(
        find.byKey(const Key('analyticsFilterChipClass')),
        findsOneWidget,
        reason: 'the Paid to category; the party already fixes the type',
      );
      expect(find.byKey(const Key('analyticsFilterChipType')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).data, '2,000.00');

      // Stepping is allowed; the card keeps the name in a period with no
      // payments to them.
      await tester.tap(find.byKey(const Key('analyticsPrev')));
      await tester.pumpAndSettle();
      expect(_pillText(tester, 'analyticsPeriodValue'), '2025');
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      expect(find.text('MARY WANJIKU · Send Money'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('analyticsTotal'))).data, '0.00');

      await tester.tap(find.byKey(const Key('analyticsPartyClose')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
      expect(_pillText(tester, 'analyticsGranularity'), 'Week');
      expect(_pillText(tester, 'analyticsPeriodValue'), '18–24 Sep');
      expect(find.byKey(const Key('analyticsFilterChipClass')), findsNothing);
    });

    testWidgets('T26: an unnamed row: its period with BOTH the type and classification filter on', (tester) async {
      await _pump(
        tester,
        rows: analyticsSampleRows(),
        args: AnalyticsRouteArgs(
          type: 'SEND_MONEY',
          period: AnalyticsPeriod.monthShown(DateTime(2026, 8, 1), today: analyticsTestNow),
          classification: 'Rent',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
      expect(_pillText(tester, 'analyticsGranularity'), 'Month');
      expect(_pillText(tester, 'analyticsPeriodValue'), 'Aug 2026');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);
      expect(find.byKey(const Key('analyticsFilterChipClass')), findsOneWidget);
      expect(_t('PETER OTIENO'), findsOneWidget);
    });

    testWidgets("the type-only shortcut (Cash): All time (F8), not the nav-bar default, with Cash's filter on", (
      tester,
    ) async {
      await _pump(
        tester,
        rows: analyticsSampleRows(),
        args: const AnalyticsRouteArgs(type: 'CASH'),
      );
      await tester.pumpAndSettle();
      expect(_pillText(tester, 'analyticsGranularity'), 'All time');
      expect(_t('JOHN KAMAU'), findsNothing);
      // Both Cash rows (20 Sep and 15 Sep) are in view — only reachable
      // once the period is All time, not the last-7-days default.
      expect(_t('Cash — Groceries'), findsOneWidget);
      expect(_t('Cash — Transport'), findsOneWidget);
    });
  });
}
