// T21 fix round 1:
//  - F5: Home, Analytics, Paid to and Settings live in one PrimaryShell and
//    stay alive; a tab switch is instant and keeps each page's state; the
//    Home-row and Paid to hand-offs retarget the live Analytics; back from a
//    non-Home tab goes to Home; a page re-queries when it is shown again.
//  - F6: Home and Analytics share the period LENGTH (last change wins).
//
// T22: the nav order is Home · Analytics · + · Paid to · Settings (indexes
// 0, 1, 3, 4). Paid to is a stub here that calls the shell exactly as
// PaidToScreen's row tap does; Settings is a bare primary page.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/domain/analytics/analytics_period.dart';
import 'package:mpesa_tracker/domain/counterparty/counterparty_key.dart';
import 'package:mpesa_tracker/domain/home/home_period.dart';
import 'package:mpesa_tracker/domain/parsing/parsed_sms_fields.dart';
import 'package:mpesa_tracker/ui/screens/analytics_screen.dart';
import 'package:mpesa_tracker/ui/screens/home_screen.dart';
import 'package:mpesa_tracker/ui/shell/primary_scaffold.dart';
import 'package:mpesa_tracker/ui/shell/primary_shell.dart';
import 'package:mpesa_tracker/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

/// [FakeAnalyticsDb] that also answers Home's dashboard queries.
class _ShellDb extends FakeAnalyticsDb {
  _ShellDb(super.transactions);

  List<Map<String, Object?>> get _live => transactions.where((t) => t['deleted_at'] == null).toList();

  bool _inWindow(Map<String, Object?> t, List<Object?> args) {
    final at = t['transaction_occurred_at'] as int;
    return at >= (args[0] as int) && at <= (args[1] as int);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    final args = arguments ?? const [];
    if (sql.contains('GROUP BY source_type')) {
      final out = <String, (int, int)>{};
      for (final t in _live.where((t) => _inWindow(t, args))) {
        final code = t['source_type'] as String;
        final prev = out[code] ?? (0, 0);
        out[code] = (prev.$1 + (t['amount_cents'] as int), prev.$2 + ((t['transaction_cost_cents'] as int?) ?? 0));
      }
      return [
        for (final e in out.entries) {'source_type': e.key, 'total': e.value.$1, 'cost': e.value.$2},
      ];
    }
    if (sql.contains('SUM(amount_cents)') && !sql.contains('FROM transactions t')) {
      return [
        {'total': _live.where((t) => _inWindow(t, args)).fold<int>(0, (s, t) => s + (t['amount_cents'] as int))},
      ];
    }
    if (sql.contains('LIMIT ?')) {
      final rows = _live
        ..sort((a, b) => (b['transaction_occurred_at'] as int).compareTo(a['transaction_occurred_at'] as int));
      return [
        for (final t in rows.take(args.last as int))
          {
            'id': t['id'],
            'display_code': t['display_code'],
            'source_type': t['source_type'],
            'amount_cents': t['amount_cents'],
            'counterparty_label': t['counterparty_label'],
            'transaction_occurred_at': t['transaction_occurred_at'],
            'classification_name': t['classification_name'],
          },
      ];
    }
    return super.rawQuery(sql, arguments);
  }
}

final _maryKey = deriveCounterpartyKey(
  sourceType: SmsSourceType.sendMoney,
  counterpartyLabel: 'MARY WANJIKU',
  counterpartyPhone: '0712345678',
);

class _PaidToStub extends StatelessWidget {
  const _PaidToStub();

  @override
  Widget build(BuildContext context) => PrimaryScaffold(
    title: 'Paid to',
    activeIndex: 3,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('stubOpenParty'),
            onPressed: () => PrimaryShell.maybeOf(
              context,
            )!.openAnalytics(AnalyticsRouteArgs(type: 'SEND_MONEY', partyKey: _maryKey)),
            child: const Text('MARY'),
          ),
          TextButton(
            key: const Key('stubOpenTypeOnly'),
            onPressed: () =>
                PrimaryShell.maybeOf(context)!.openAnalytics(const AnalyticsRouteArgs(type: 'CASH')),
            child: const Text('CASH SHORTCUT'),
          ),
        ],
      ),
    ),
  );
}

Future<_ShellDb> _pumpShell(WidgetTester tester) async {
  tester.view.physicalSize = const Size(392, 850);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = _ShellDb(analyticsSampleRows());
  DateTime clock() => analyticsTestNow;
  await tester.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController(),
      child: MaterialApp(
        routes: {'/add': (_) => const Scaffold(body: Text('ADD PAGE'))},
        home: PrimaryShell(
          pages: {
            0: HomeScreen(db: db, clock: clock),
            1: AnalyticsScreen(db: db, clock: clock),
            3: const _PaidToStub(),
            4: const PrimaryScaffold(title: 'Settings', activeIndex: 4, body: Text('SETTINGS BODY')),
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
  return db;
}

Future<void> _tab(WidgetTester tester, String label) async {
  await tester.tap(find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text(label)));
  await tester.pumpAndSettle();
}

String? _pill(WidgetTester tester, String key) {
  final f = find.descendant(of: find.byKey(Key(key)), matching: find.byType(Text));
  return f.evaluate().isEmpty ? null : tester.widget<Text>(f).data;
}

String _homePeriod(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byKey(const Key('homePeriodButton')), matching: find.byType(Text)).first)
    .data!;

Future<void> _pickFromMenu(WidgetTester tester, Key button, String item) async {
  await tester.tap(find.byKey(button));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// Lets a hand-off highlight run out so no timer is left pending.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

/// Analytics on 11–17 Sep with Cash's filter on.
Future<void> _analyticsPlace(WidgetTester tester) async {
  await _tab(tester, 'Analytics');
  await tester.tap(find.byKey(const Key('analyticsPrev')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('analyticsTypeTile-CASH')));
  await tester.pumpAndSettle();
  expect(_pill(tester, 'analyticsPeriodValue'), '11–17 Sep');
  expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'hint_seen_$homeHintId': true}));

  group('F5: the pages stay alive', () {
    testWidgets('switching tabs keeps Analytics\' period and filter', (tester) async {
      await _pumpShell(tester);
      await _analyticsPlace(tester);
      await _tab(tester, 'Home');
      await _tab(tester, 'Settings');
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsPeriodValue'), '11–17 Sep');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);
      expect(find.byType(AnalyticsScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('a tab switch has no route transition: the next frame shows only the new page', (tester) async {
      await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      await tester.tap(find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text('Home')));
      await tester.pump();
      expect(find.byKey(const Key('homeSummaryCard')), findsOneWidget);
      expect(find.byKey(const Key('analyticsGranularity')), findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text('Analytics')));
      await tester.pump();
      expect(find.byKey(const Key('analyticsGranularity')), findsOneWidget);
      expect(find.byKey(const Key('homeSummaryCard')), findsNothing);
    });

    testWidgets('the Home-row hand-off retargets the live Analytics to that Day', (tester) async {
      await _pumpShell(tester);
      await _analyticsPlace(tester);
      await _tab(tester, 'Home');
      await tester.tap(find.byKey(const ValueKey('homeRecentRow-1')));
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      expect(_pill(tester, 'analyticsPeriodValue'), 'Today');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsNothing);
      expect(find.byType(AnalyticsScreen, skipOffstage: false), findsOneWidget, reason: 'no second Analytics');
      expect(find.byType(PrimaryShell), findsOneWidget);
      await _drain(tester);
    });

    testWidgets('Paid to: the close button restores the state before the recipient view', (tester) async {
      await _pumpShell(tester);
      await _analyticsPlace(tester);
      await _tab(tester, 'Paid to');
      await tester.tap(find.byKey(const Key('stubOpenParty')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      await tester.tap(find.byKey(const Key('analyticsPartyClose')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
      expect(_pill(tester, 'analyticsGranularity'), 'Week');
      expect(_pill(tester, 'analyticsPeriodValue'), '11–17 Sep');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);
    });

    testWidgets('back from a non-Home tab goes to Home; on Home back may leave', (tester) async {
      await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      final shellPop = find.ancestor(of: find.byType(IndexedStack), matching: find.byWidgetPredicate((w) => w is PopScope));
      expect((tester.widget(shellPop.first) as PopScope).canPop, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('homeSummaryCard')), findsOneWidget);
      expect((tester.widget(shellPop.first) as PopScope).canPop, isTrue);
    });

    testWidgets('data changed elsewhere appears when the tab is shown again', (tester) async {
      final db = await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      expect(find.text('NEW PERSON'), findsNothing);
      await _tab(tester, 'Settings');
      // e.g. a row restored from Recently Deleted.
      db.transactions.add(fakeTx(id: 99, at: DateTime(2026, 9, 24, 12), label: 'NEW PERSON', amountCents: 7000));
      await _tab(tester, 'Analytics');
      expect(find.text('NEW PERSON'), findsOneWidget);
      expect(_pill(tester, 'analyticsPeriodValue'), '18–24 Sep', reason: 'the place is kept');
    });

    testWidgets('dataChanged (Add saved) refreshes the live pages without a tab switch', (tester) async {
      final db = await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      expect(find.text('NEW PERSON'), findsNothing);
      db.transactions.add(fakeTx(id: 99, at: DateTime(2026, 9, 24, 12), label: 'NEW PERSON', amountCents: 7000));
      PrimaryShell.active!.dataChanged();
      await tester.pumpAndSettle();
      expect(find.text('NEW PERSON'), findsOneWidget);
      expect(_pill(tester, 'analyticsPeriodValue'), '18–24 Sep', reason: 'the place is kept');
    });

    testWidgets('Add from the FAB is pushed over the shell; the pages survive it', (tester) async {
      await _pumpShell(tester);
      await _analyticsPlace(tester);
      await tester.tap(find.byKey(const Key('primaryFab')));
      await tester.pumpAndSettle();
      expect(find.text('ADD PAGE'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsPeriodValue'), '11–17 Sep');
    });
  });

  group('F6: Home and Analytics share the period length', () {
    testWidgets('first Analytics visit with Home untouched: the last 7 days', (tester) async {
      await _pumpShell(tester);
      expect(_homePeriod(tester), 'This month');
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Week');
      expect(_pill(tester, 'analyticsPeriodValue'), '18–24 Sep');
    });

    testWidgets('Home -> Analytics: Today = Day today, This week = last 7 days, This month = this month', (
      tester,
    ) async {
      await _pumpShell(tester);
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      expect(_homePeriod(tester), 'Today');
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      expect(_pill(tester, 'analyticsPeriodValue'), 'Today');
      await _tab(tester, 'Home');
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Week');
      expect(_pill(tester, 'analyticsPeriodValue'), '18–24 Sep');
      await _tab(tester, 'Home');
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Month');
    });

    testWidgets('Analytics -> Home: Day / Week / Month set Home; Year, All time, Custom do not', (tester) async {
      await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Day');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'Today');
      await _tab(tester, 'Analytics');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Week');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This week');
      await _tab(tester, 'Analytics');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Month');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month');
      await _tab(tester, 'Analytics');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Year');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'All time');
      await tester.tap(find.byKey(const Key('analyticsCalendar')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('analyticsCustomShow')));
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsGranularity'), 'Custom');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month');
    });

    testWidgets('browsing back never changes Home; a bar tap that changes the length does', (tester) async {
      await _pumpShell(tester);
      await _tab(tester, 'Analytics');
      await tester.tap(find.byKey(const Key('analyticsPrev')));
      await tester.pumpAndSettle();
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month', reason: '‹ within Week');
      await _tab(tester, 'Analytics');
      // Week -> Day via a bar tap is a length change.
      await tester.tap(find.byKey(const Key('analyticsBar-6')));
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'Today');
      await _tab(tester, 'Home');
      await tester.tap(find.byKey(const Key('homePeriodButton'))); // -> This week
      await tester.pumpAndSettle();
      await _tab(tester, 'Analytics');
      await tester.tap(find.byKey(const Key('analyticsPrev'))); // an earlier week
      await tester.pumpAndSettle();
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This week');
    });

    testWidgets('the Home-row hand-off and the recipient view never change Home', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byKey(const ValueKey('homeRecentRow-1')));
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      await _drain(tester);
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month');
      await _tab(tester, 'Paid to');
      await tester.tap(find.byKey(const Key('stubOpenParty')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month');
    });

    testWidgets('F8: a type-only shortcut (shell path) lands on All time and never changes Home', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byKey(const Key('homePeriodButton'))); // Today
      await tester.pumpAndSettle();
      expect(_homePeriod(tester), 'Today');
      await _tab(tester, 'Paid to');
      await tester.tap(find.byKey(const Key('stubOpenTypeOnly')));
      await tester.pumpAndSettle();
      expect(_pill(tester, 'analyticsGranularity'), 'All time');
      expect(find.byKey(const Key('analyticsFilterChipType')), findsOneWidget);
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'Today', reason: 'F8 is a hand-off; Home is untouched (F6)');
    });

    testWidgets('the last change wins', (tester) async {
      await _pumpShell(tester);
      await tester.tap(find.byKey(const Key('homePeriodButton'))); // Today
      await tester.pumpAndSettle();
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      await _pickFromMenu(tester, const Key('analyticsGranularity'), 'Month');
      await _tab(tester, 'Home');
      expect(_homePeriod(tester), 'This month');
      await tester.tap(find.byKey(const Key('homePeriodButton'))); // Today again
      await tester.pumpAndSettle();
      await _tab(tester, 'Analytics');
      expect(_pill(tester, 'analyticsGranularity'), 'Day');
      expect(_pill(tester, 'analyticsPeriodValue'), 'Today');
    });
  });

  test('the shell mapping helpers', () {
    final today = DateTime(2026, 9, 24);
    expect(homePeriodForAnalytics(AnalyticsGranularity.day), HomePeriod.today);
    expect(homePeriodForAnalytics(AnalyticsGranularity.week), HomePeriod.week);
    expect(homePeriodForAnalytics(AnalyticsGranularity.month), HomePeriod.month);
    expect(homePeriodForAnalytics(AnalyticsGranularity.year), isNull);
    expect(homePeriodForAnalytics(AnalyticsGranularity.all), isNull);
    expect(homePeriodForAnalytics(AnalyticsGranularity.custom), isNull);
    expect(analyticsPeriodForHome(HomePeriod.today, today), AnalyticsPeriod.day(today));
    expect(analyticsPeriodForHome(HomePeriod.week, today), AnalyticsPeriod.lastSevenDays(today));
    expect(analyticsPeriodForHome(HomePeriod.month, today), AnalyticsPeriod.month(today));
  });
}

