// T21 fix round 1, Analytics-only items:
//  - F7: leaving the Parties view never throws (the card is built from the
//    view snapshot, not from state the handler already cleared);
//  - F2: the empty-chart state (no y scale, one muted line, no average);
//  - F3: pickers and sub-sheets opened from Analytics use the page's Ocean
//    & Sun palette (light or dark), never the old green;
//  - F4: the Custom range can't be backwards.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/counterparty/counterparty_key.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>>? rows,
  Object? args,
  Brightness brightness = Brightness.light,
}) async {
  tester.view.physicalSize = const Size(400, 2600);
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

Future<void> _pickFromMenu(WidgetTester tester, Key button, String item) async {
  await tester.tap(find.byKey(button));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

String _pillValue(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text)))
    .data!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('F7: leaving the recipient (Paid to) view', () {
    final maryKey = deriveCounterpartyKey(
      sourceType: SmsSourceType.sendMoney,
      counterpartyLabel: 'MARY WANJIKU',
      counterpartyPhone: '0712345678',
    );

    testWidgets('the close button, frame by frame, throws nothing', (tester) async {
      await _pump(tester, args: AnalyticsRouteArgs(type: 'SEND_MONEY', partyKey: maryKey));
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsPartyClose')));
      // The frame straight after the tap (before the re-query lands) is the
      // one that used to hit the null check.
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
      expect(_pillValue(tester), '18–24 Sep');
    });
  });

  group('F2: the empty chart', () {
    testWidgets('an empty Day (today): no scale, "No spending yet today"', (tester) async {
      await _pump(tester, rows: []);
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Day');
      expect(_pillValue(tester), 'Today');
      expect(find.byKey(const Key('analyticsChartPaintEmpty')), findsOneWidget);
      expect(find.byKey(const Key('analyticsChartPaint')), findsNothing);
      expect(find.text('No spending yet today'), findsOneWidget);
    });

    testWidgets('an empty Week: no scale, "No spending in this period"', (tester) async {
      await _pump(tester, rows: []);
      expect(find.byKey(const Key('analyticsChartPaintEmpty')), findsOneWidget);
      expect(find.text('No spending in this period'), findsOneWidget);
    });

    testWidgets('an empty earlier Day says "No spending in this period"', (tester) async {
      // Only today has spending, so yesterday's Day is empty.
      await _pump(tester, rows: [fakeTx(id: 1, at: DateTime(2026, 9, 24, 9), label: 'A', amountCents: 1000)]);
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Day');
      await tester.tap(find.byKey(const Key('analyticsPrev')));
      await tester.pumpAndSettle();
      expect(find.text('No spending in this period'), findsOneWidget);
    });

    testWidgets('a non-empty chart is unchanged: the scale, no empty line', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('analyticsChartPaint')), findsOneWidget);
      expect(find.byKey(const Key('analyticsChartEmpty')), findsNothing);
    });

    test('analyticsChartIsEmpty', () {
      expect(analyticsChartIsEmpty([
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]), isTrue);
      expect(analyticsChartIsEmpty([
        [0, 0, 0, 0],
        [0, 5, 0, 0],
      ]), isFalse);
    });
  });

  group('F3: pickers follow the page theme', () {
    for (final (brightness, palette) in [(Brightness.light, AppPalette.light), (Brightness.dark, AppPalette.dark)]) {
      testWidgets('${brightness.name}: the Custom date picker is Ocean, ${brightness.name}', (tester) async {
        await _pump(tester, brightness: brightness);
        await tester.tap(find.byKey(const Key('analyticsCalendar')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('analyticsCustomFrom')));
        await tester.pumpAndSettle();
        final theme = Theme.of(tester.element(find.byType(DatePickerDialog)));
        expect(theme.colorScheme.primary, palette.primary);
        expect(theme.colorScheme.brightness, brightness);
        expect(theme.colorScheme.primary, isNot(AppColors.primary), reason: 'never the old green');
      });

      testWidgets('${brightness.name}: the edit form date and time pickers are Ocean', (tester) async {
        await _pump(tester, brightness: brightness);
        await tester.tap(find.byKey(const Key('analyticsRow-1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('editDateTimeChangeLink')));
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.byType(DatePickerDialog))).colorScheme.primary, palette.primary);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.byType(TimePickerDialog))).colorScheme.primary, palette.primary);
      });
    }

    test('analyticsPickerTheme: the palette primary and brightness', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final t = analyticsPickerTheme(p);
        expect(t.colorScheme.primary, p.primary);
        expect(t.colorScheme.onPrimary, p.onPrimary);
        expect(t.brightness, p.brightness);
      }
    });
  });

  group('F4: the Custom range cannot be backwards', () {
    final today = DateTime(2026, 9, 24);
    final first = DateTime(2025, 1, 1);

    test('From: first date .. today; To: the chosen From .. today', () {
      final from = DateTime(2026, 9, 10);
      expect(customRangePickerBounds(from: from, today: today, firstDate: first, pickingFrom: true), (first, today));
      expect(customRangePickerBounds(from: from, today: today, firstDate: first, pickingFrom: false), (from, today));
    });

    testWidgets('the To picker starts at From; the upper bound stays today', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsCalendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsCustomTo')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(dialog.firstDate, DateTime(2026, 9, 18));
      expect(dialog.lastDate, today);
    });

    testWidgets('moving From past To moves To with it', (tester) async {
      await _pump(tester);
      await tester.tap(find.byKey(const Key('analyticsCalendar')));
      await tester.pumpAndSettle();
      // Custom sheet: 18 Sep .. 24 Sep. First make To 20 Sep.
      await tester.tap(find.byKey(const Key('analyticsCustomTo')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('20 Sep 2026'), findsOneWidget);
      // Now move From to 22 Sep, past To.
      await tester.tap(find.byKey(const Key('analyticsCustomFrom')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(dialog.lastDate, today);
      await tester.tap(find.text('22'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('22 Sep 2026'), findsNWidgets(2), reason: 'From and To are both 22 Sep');
      await tester.tap(find.byKey(const Key('analyticsCustomShow')));
      await tester.pumpAndSettle();
      expect(_pillValue(tester), '22–22 Sep'); // Custom's existing one-day label
    });
  });
}
