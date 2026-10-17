// F1 (0.1.2 corrections, finding R33): with "First day of the week" = Sunday,
// EVERY Analytics view buckets weeks Sunday-first, however it was reached:
// Paid to's hand-off, the Year drill-down, the arrows, clearing the recipient
// filter, and coming back to the page. Calendar: 1 Sep 2026 is a Tuesday, 1 Oct
// a Thursday; "now" is Saturday 17 Oct 2026. Invented rows; prefs are the
// shared_preferences test mock, never the real ones.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:mmogo/ui/screens/paid_to_screen.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

final _now = DateTime(2026, 10, 17, 12);

List<Map<String, Object?>> _rows() => [
  fakeTx(id: 1, at: DateTime(2026, 10, 16, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 100000),
  fakeTx(id: 2, at: DateTime(2026, 10, 12, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 50000),
  fakeTx(id: 3, at: DateTime(2026, 10, 2, 9), label: 'JOHN KAMAU', phone: '0700000003', amountCents: 20000),
  fakeTx(id: 4, at: DateTime(2026, 9, 15, 9), label: 'MARY WANJIKU', phone: '0712345678', amountCents: 75000),
  fakeTx(id: 5, at: DateTime(2026, 9, 2, 9), label: 'JOHN KAMAU', phone: '0700000003', amountCents: 30000),
];

const _octSundayFirst = ['1-3', '4-10', '11-17', '18-24', '25-31'];
const _sepSundayFirst = ['1-5', '6-12', '13-19', '20-26', '27-30'];

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> _pumpAnalytics(WidgetTester tester, {Object? args}) async {
  _size(tester);
  await tester.pumpWidget(const SizedBox()); // a fresh tree: a new visit, not an update
  await tester.pumpWidget(
    MaterialApp(
      onGenerateRoute: (settings) => MaterialPageRoute(
        settings: RouteSettings(name: settings.name, arguments: args),
        builder: (_) => AnalyticsScreen(db: FakeAnalyticsDb(_rows()), clock: () => _now),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// What a real Paid to hands to Analytics for Mary: the screen itself, its
/// own button, the args it pushed.
Future<AnalyticsRouteArgs> _paidToHandOff(WidgetTester tester) async {
  _size(tester);
  AnalyticsRouteArgs? got;
  await tester.pumpWidget(
    MaterialApp(
      home: PaidToScreen(db: FakeAnalyticsDb(_rows()), clock: () => _now),
      onGenerateRoute: (settings) {
        if (settings.name != '/analytics') return null;
        got = settings.arguments! as AnalyticsRouteArgs;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('ANALYTICS')),
        );
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

/// The label of bar [i] (what a screen reader says: "4-10 Oct, 7 days: ...").
String _barLabel(WidgetTester tester, int i) => tester
    .widget<Semantics>(
      find.ancestor(of: find.byKey(Key('analyticsBar-$i')), matching: find.byType(Semantics)).first,
    )
    .properties
    .label!;

int _barCount() {
  var n = 0;
  while (find.byKey(Key('analyticsBar-$n')).evaluate().isNotEmpty) {
    n++;
  }
  return n;
}

/// The Month chart's bar names reduced to "4-10".
List<String> _weekBars(WidgetTester tester) => [
  for (var i = 0; i < _barCount(); i++) _barLabel(tester, i).split(' ').first,
];

/// The Week chart's bars: the first two letters of each day.
List<String> _dayBars(WidgetTester tester) => [
  for (var i = 0; i < _barCount(); i++) _barLabel(tester, i).substring(0, 2),
];

String _value(WidgetTester t) => t
    .widget<Text>(find.descendant(of: find.byKey(const Key('analyticsPeriodValue')), matching: find.byType(Text)))
    .data!;

Future<void> _pickGranularity(WidgetTester t, String label) async {
  await t.tap(find.byKey(const Key('analyticsGranularity')));
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

void main() {
  late SemanticsHandle semantics;
  setUp(() {
    SharedPreferences.setMockInitialValues({'first_day_of_week': 7});
  });
  setUp(() => semantics = TestWidgetsFlutterBinding.ensureInitialized().ensureSemantics());
  tearDown(() => semantics.dispose());

  testWidgets('Paid to hand-off, Month: the recipient view buckets Sunday-first; clearing it restores a Sunday week', (
    t,
  ) async {
    final args = await _paidToHandOff(t);
    expect(args.period!.firstDay, 7, reason: 'the hand-off carries the preference');
    await _pumpAnalytics(t, args: args);
    expect(find.byKey(const Key('analyticsPartyCard')), findsOneWidget);
    expect(_weekBars(t), _octSundayFirst);

    // Another visit with the same hand-off (the "later runs" of R33).
    await _pumpAnalytics(t, args: args);
    expect(_weekBars(t), _octSundayFirst);

    await t.tap(find.byKey(const Key('analyticsPartyClose')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('analyticsPartyCard')), findsNothing);
    expect(_value(t), '11–17 Oct');
    expect(_dayBars(t).first, 'Su');
  });

  testWidgets('a hand-off period built with the Monday default is still anchored to the preference', (t) async {
    // The view must not trust the period it is handed (an old caller, a restore).
    await _pumpAnalytics(
      t,
      args: AnalyticsRouteArgs(
        type: 'SEND_MONEY',
        partyKey: '0712345678',
        partyName: 'MARY WANJIKU',
        period: AnalyticsPeriod.month(DateTime(2026, 10, 1), firstDay: 1),
      ),
    );
    expect(_weekBars(t), _octSundayFirst);
  });

  testWidgets('Year, tap September, arrow to October and back: all Sunday-first; leave and return keeps it', (t) async {
    await _pumpAnalytics(t);
    await _pickGranularity(t, 'Year');
    expect(_value(t), '2026');
    await t.tap(find.byKey(const Key('analyticsBar-8'))); // September
    await t.pumpAndSettle();
    expect(_value(t), 'Sep 2026');
    expect(_weekBars(t), _sepSundayFirst);

    await t.tap(find.byKey(const Key('analyticsNext')));
    await t.pumpAndSettle();
    expect(_value(t), 'Oct 2026');
    expect(_weekBars(t), _octSundayFirst);

    await t.tap(find.byKey(const Key('analyticsPrev')));
    await t.pumpAndSettle();
    expect(_weekBars(t), _sepSundayFirst);

    // Leave the app and come back: the load runs again, the period stays.
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
    await t.pumpAndSettle();
    expect(_weekBars(t), _sepSundayFirst);
    await t.tap(find.byKey(const Key('analyticsNext')));
    await t.pumpAndSettle();
    expect(_weekBars(t), _octSundayFirst);
  });

  testWidgets('a part week opened from Year > Month > bar is a Sunday week', (t) async {
    await _pumpAnalytics(t);
    await _pickGranularity(t, 'Year');
    await t.tap(find.byKey(const Key('analyticsBar-9'))); // October
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('analyticsBar-2'))); // 11-17: first tap, tooltip
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('analyticsBar-2'))); // second tap opens the week
    await t.pumpAndSettle();
    expect(_value(t), '11–17 Oct');
    expect(_dayBars(t).first, 'Su');
  });

  testWidgets('a LIVE Analytics (in the shell) keeps Sunday weeks across repeated hand-offs built with Monday', (t) async {
    // The R33 "later runs": the page stays alive and is retargeted again and
    // again; the first load already knew the preference, so only an
    // always-on re-anchor (not a change check) keeps the later ones right.
    _size(t);
    await t.pumpWidget(
      MaterialApp(
        home: PrimaryShell(
          initialIndex: 1,
          pages: {
            0: const SizedBox(),
            1: AnalyticsScreen(db: FakeAnalyticsDb(_rows()), clock: () => _now),
            3: const SizedBox(),
            4: const SizedBox(),
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    final shell = PrimaryShell.active!;
    for (var run = 1; run <= 3; run++) {
      shell.openAnalytics(
        AnalyticsRouteArgs(
          type: 'SEND_MONEY',
          partyKey: '0712345678',
          partyName: 'MARY WANJIKU',
          period: AnalyticsPeriod.month(DateTime(2026, 10, 1), firstDay: 1),
        ),
      );
      await t.pumpAndSettle();
      expect(_weekBars(t), _octSundayFirst, reason: 'hand-off run $run');
      await t.tap(find.byKey(const Key('analyticsPartyClose')));
      await t.pumpAndSettle();
      expect(_value(t), '11–17 Oct', reason: 'restored week after run $run');
      expect(_dayBars(t).first, 'Su');
    }
  });

  testWidgets('Monday still means Monday: first day 1 keeps the Monday buckets on the same paths', (t) async {
    SharedPreferences.setMockInitialValues({'first_day_of_week': 1});
    await _pumpAnalytics(t);
    await _pickGranularity(t, 'Year');
    await t.tap(find.byKey(const Key('analyticsBar-8')));
    await t.pumpAndSettle();
    expect(_weekBars(t), ['1-6', '7-13', '14-20', '21-27', '28-30']);
  });
}
