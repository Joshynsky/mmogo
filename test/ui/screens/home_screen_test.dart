// T20 — Home rework widget tests (lib/ui/screens/home_screen.dart), built to
// the approved home-colours mock (v4).
//
// Same environment constraint every widget test here documents: a real
// sqflite_common_ffi Database hangs inside testWidgets, so Home is driven
// through its `db:` seam with a small fake that answers the four
// HomeDashboardDao queries (the real SQL is proven against in-memory sqlite
// in test/data/home_dashboard_dao_test.dart). The fake tells "this period"
// from "prior period" sums by the start bound it is asked for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/prefs/app_prefs.dart';
import 'package:mpesa_tracker/domain/home/home_period.dart';
import 'package:mpesa_tracker/ui/screens/home_screen.dart';
import 'package:mpesa_tracker/ui/shell/routes.dart';
import 'package:mpesa_tracker/ui/theme/app_colors.dart';
import 'package:mpesa_tracker/ui/widgets/coach_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 24 Sep 2026, 09:30 — a morning.
final _morning = DateTime(2026, 9, 24, 9, 30);

class _FakeHomeDb implements Database {
  _FakeHomeDb({
    required this.now,
    this.thisTotal = 0,
    this.priorTotal = 0,
    this.types = const {},
    this.recentCount = 0,
  });

  final DateTime now;
  final int thisTotal;
  final int priorTotal;

  /// source_type -> (total cents, cost cents)
  final Map<String, (int, int)> types;
  final int recentCount;

  /// The start bound of every period-sum query (T21 pull-to-refresh test).
  final List<int> sumStarts = [];

  static const _codes = ['BUY_GOODS', 'SEND_MONEY', 'CASH', 'PAYBILL'];

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('GROUP BY source_type')) {
      return [
        for (final e in types.entries) {'source_type': e.key, 'total': e.value.$1, 'cost': e.value.$2},
      ];
    }
    if (sql.contains('JOIN classifications')) {
      final limit = arguments!.single as int;
      return [
        for (var i = 0; i < recentCount && i < limit; i++)
          {
            'id': i + 1,
            'display_code': 'CODE$i',
            'source_type': _codes[i % 4],
            'amount_cents': 1000 * (i + 1),
            'counterparty_label': 'PARTY NUMBER ${i + 1} WITH A VERY LONG NAME THAT MUST ELLIPSISE',
            'transaction_occurred_at': now.subtract(Duration(hours: i)).millisecondsSinceEpoch,
            'classification_name': 'Lunch',
          },
      ];
    }
    if (sql.contains('SUM(amount_cents)')) {
      final start = arguments!.first as int;
      sumStarts.add(start);
      final currentStarts = {for (final p in HomePeriod.values) p.bounds(now).$1};
      return [
        {'total': currentStarts.contains(start) ? thisTotal : priorTotal},
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _pushed = <RouteSettings>[];

Future<void> _pumpHome(
  WidgetTester tester,
  _FakeHomeDb db, {
  Size size = const Size(392, 850),
  double textScale = 1.0,
  Brightness brightness = Brightness.light,
  DateTime? now,
  DateTime Function()? clock,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(db: db, clock: clock ?? () => now ?? db.now),
      onGenerateRoute: (settings) {
        _pushed.add(settings);
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const Scaffold(body: Text('ANALYTICS')),
        );
      },
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

Color? _textColor(WidgetTester tester, Finder f) => tester.widget<Text>(f).style?.color;

Color? _boxColor(WidgetTester tester, Key key) {
  final c = tester.widget<Container>(find.byKey(key));
  return (c.decoration as BoxDecoration?)?.color ?? c.color;
}

ScrollPosition _homeScroll(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(of: find.byKey(const Key('homeScroll')), matching: find.byType(Scrollable)))
    .position;

Finder _recentRows({bool skipOffstage = true}) => find.byWidgetPredicate(
  (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('homeRecentRow-'),
  skipOffstage: skipOffstage,
);

void main() {
  setUp(() {
    // The tour is already seen, so its scrim never covers the card.
    SharedPreferences.setMockInitialValues({'tour_seen_$homeTourId': true});
    _pushed.clear();
  });

  group('merged card', () {
    final db = _FakeHomeDb(
      now: _morning,
      thisTotal: 550000,
      priorTotal: 200000,
      // BUY_GOODS absent = zero this period.
      types: {'SEND_MONEY': (350000, 4200), 'PAYBILL': (120000, 2000), 'CASH': (80000, 0)},
      recentCount: 3,
    );

    testWidgets('one card: period label, total headline, diff; no donut, no separate cards', (tester) async {
      await _pumpHome(tester, db);
      final card = find.byKey(const Key('homeSummaryCard'));
      expect(card, findsOneWidget);
      for (final f in [
        find.text('This month'),
        find.byKey(const Key('homeTotal')),
        find.byKey(const Key('homeDiff')),
        find.text('Transaction cost (all M-Pesa)'),
      ]) {
        expect(find.descendant(of: card, matching: f), findsOneWidget);
      }
      expect(find.text('Ksh 5,500.00'), findsOneWidget);
      final total = tester.widget<Text>(find.byKey(const Key('homeTotal')));
      expect(total.style!.fontSize, 27);
      expect(total.style!.fontWeight, FontWeight.w800);
      expect(total.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.text('BY SOURCE'), findsNothing);
      expect(find.text('▲ 175% vs last month'), findsOneWidget);
    });

    testWidgets('bars: fixed order, length = share of the total, type colours', (tester) async {
      await _pumpHome(tester, db);
      const order = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH'];
      const expectedShare = {
        'SEND_MONEY': 350000 / 550000,
        'PAYBILL': 120000 / 550000,
        'BUY_GOODS': 0.0,
        'CASH': 80000 / 550000,
      };

      final ys = [for (final c in order) tester.getTopLeft(find.byKey(Key('homeTypeRow-$c'))).dy];
      expect(ys, orderedEquals([...ys]..sort()), reason: 'Send Money, Paybill, Buy Goods, Cash top to bottom');
      expect(
        [for (final c in order) tester.widget<Text>(find.byKey(Key('homeTypeAmount-$c'))).data],
        ['Ksh 3,500.00', 'Ksh 1,200.00', 'Ksh 0.00', 'Ksh 800.00'],
      );

      for (final c in order) {
        final bar = find.byKey(Key('homeBar-$c'));
        expect(tester.widget<AnimatedFractionallySizedBox>(bar).widthFactor, closeTo(expectedShare[c]!, 1e-9));
        // Rendered: the bar's width over its track's width.
        final track = find.ancestor(of: bar, matching: find.byType(ClipRRect)).first;
        final fillBox = find.descendant(of: bar, matching: find.byType(DecoratedBox));
        final rendered = tester.getSize(fillBox).width / tester.getSize(track).width;
        expect(rendered, closeTo(expectedShare[c]!, 0.01), reason: c);
        final fill = tester.widget<DecoratedBox>(find.descendant(of: bar, matching: find.byType(DecoratedBox)));
        expect((fill.decoration as BoxDecoration).color, AppPalette.light.typeColor(c));
      }
      // The shares add up to one full bar.
      final sum = order.fold<double>(
        0,
        (s, c) => s + tester.widget<AnimatedFractionallySizedBox>(find.byKey(Key('homeBar-$c'))).widthFactor!,
      );
      expect(sum, closeTo(1.0, 1e-9));
    });

    testWidgets('a zero type keeps its row, faded, with Ksh 0.00', (tester) async {
      await _pumpHome(tester, db);
      expect(find.byKey(const Key('homeTypeRow-BUY_GOODS')), findsOneWidget);
      expect(tester.widget<Opacity>(find.byKey(const Key('homeTypeLabel-BUY_GOODS'))).opacity, 0.6);
      expect(tester.widget<Opacity>(find.byKey(const Key('homeTypeLabel-SEND_MONEY'))).opacity, 1.0);
      expect(tester.widget<Text>(find.byKey(const Key('homeTypeAmount-BUY_GOODS'))).data, 'Ksh 0.00');
    });

    testWidgets('the cost row sums all M-Pesa costs', (tester) async {
      await _pumpHome(tester, db);
      expect(tester.widget<Text>(find.byKey(const Key('homeCost'))).data, 'Ksh 62.00');
    });

    testWidgets('the cost row is shown with Ksh 0.00 when nothing was spent', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning));
      expect(find.text('Transaction cost (all M-Pesa)'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('homeCost'))).data, 'Ksh 0.00');
      expect(find.text('Ksh 0.00'), findsNWidgets(6)); // total + 4 types + cost
      for (final c in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'CASH']) {
        expect(tester.widget<AnimatedFractionallySizedBox>(find.byKey(Key('homeBar-$c'))).widthFactor, 0);
        expect(tester.widget<Opacity>(find.byKey(Key('homeTypeLabel-$c'))).opacity, 0.6);
      }
      // HomeDiff's no-prior state stays muted text.
      expect(find.text('—'), findsOneWidget);
      expect(_textColor(tester, find.text('—')), AppPalette.light.mutedInk);
    });

    testWidgets('tapping the period label cycles Today → This week → This month (not a menu)', (tester) async {
      await _pumpHome(tester, db);
      expect(find.text('This month'), findsOneWidget);
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      expect(find.text('Today'), findsOneWidget);
      expect(find.byType(PopupMenuItem<Object>), findsNothing);
      expect(find.text('▲ 175% vs yesterday'), findsOneWidget);
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsOneWidget);
      await tester.tap(find.byKey(const Key('homePeriodButton')));
      await tester.pumpAndSettle();
      expect(find.text('This month'), findsOneWidget);
    });

    testWidgets('no-prior-spend state keeps its muted message', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, thisTotal: 1000, types: {'CASH': (1000, 0)}));
      final f = find.text('No spend in the prior period to compare');
      expect(f, findsOneWidget);
      expect(_textColor(tester, f), AppPalette.light.mutedInk);
    });
  });

  group('diff colours', () {
    for (final brightness in Brightness.values) {
      final palette = AppPalette.forBrightness(brightness);
      testWidgets('${brightness.name}: spending up is red', (tester) async {
        await _pumpHome(
          tester,
          _FakeHomeDb(now: _morning, thisTotal: 400000, priorTotal: 100000),
          brightness: brightness,
        );
        final f = find.text('▲ 300% vs last month');
        expect(f, findsOneWidget);
        expect(_textColor(tester, f), palette.diffUp);
        expect(palette.diffUp, brightness == Brightness.light ? const Color(0xFFC62828) : const Color(0xFFFF8A80));
      });

      testWidgets('${brightness.name}: spending down is the primary Ocean', (tester) async {
        await _pumpHome(
          tester,
          _FakeHomeDb(now: _morning, thisTotal: 88000, priorTotal: 100000),
          brightness: brightness,
        );
        final f = find.text('▼ 12% vs last month');
        expect(f, findsOneWidget);
        expect(_textColor(tester, f), palette.diffDown);
        expect(palette.diffDown, palette.primary);
        expect(palette.diffDown, brightness == Brightness.light ? const Color(0xFF0A6E8A) : const Color(0xFF3FB6D4));
      });
    }
  });

  group('greeting', () {
    testWidgets('time of day + name in the top bar', (tester) async {
      SharedPreferences.setMockInitialValues({'tour_seen_$homeTourId': true, AppPrefs.keyUserDisplayName: 'Shyn'});
      await _pumpHome(tester, _FakeHomeDb(now: _morning), now: DateTime(2026, 9, 24, 11, 59));
      final title = find.descendant(of: find.byType(AppBar), matching: find.text('Good morning Shyn,'));
      expect(title, findsOneWidget);
    });

    testWidgets('no name -> just the time of day', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning), now: DateTime(2026, 9, 24, 17));
      expect(find.text('Good evening'), findsOneWidget);
      expect(find.text('Welcome back'), findsNothing);
    });
  });

  group('recent transactions: whole rows only', () {
    testWidgets('as many whole rows as fit, most recent first; the page does not scroll', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, thisTotal: 1000, recentCount: 30));
      expect(find.byKey(const Key('homeRecentFit')), findsOneWidget);
      expect(find.byKey(const Key('homeRecentFallback')), findsNothing);

      final rows = _recentRows();
      final n = rows.evaluate().length;
      expect(n, greaterThanOrEqualTo(1));
      expect(n, lessThan(30));
      final card = tester.getRect(find.byKey(const Key('homeRecentCard')));
      final rects = [for (var i = 1; i <= n; i++) tester.getRect(find.byKey(Key('homeRecentRow-$i')))];
      // Most recent first (ids are fetched newest-first) and every row whole.
      for (var i = 0; i < n; i++) {
        expect(rects[i].bottom, lessThanOrEqualTo(card.bottom + 0.01), reason: 'row ${i + 1} is whole');
        if (i > 0) expect(rects[i].top, greaterThan(rects[i - 1].top));
      }
      // One more row would not have fit.
      final rowH = rects.first.height;
      expect(card.bottom - rects.last.bottom, lessThan(rowH + 1));
      expect(_homeScroll(tester).maxScrollExtent, 0);
    });

    testWidgets('a taller screen fits more rows', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, recentCount: 30), size: const Size(392, 700));
      final small = _recentRows().evaluate().length;
      await _pumpHome(tester, _FakeHomeDb(now: _morning, recentCount: 30), size: const Size(392, 1000));
      final big = _recentRows().evaluate().length;
      expect(big, greaterThan(small));
    });

    testWidgets('row content: type-colour dot, ellipsised name, "Type · date" (no code), amount', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, recentCount: 2));
      // Row 1 is BUY_GOODS (the fake's first code), dated 24 Sep.
      expect(find.text('Buy Goods · 24 Sep'), findsOneWidget);
      expect(find.text('Send Money · 24 Sep'), findsOneWidget);
      expect(find.textContaining('CODE'), findsNothing);
      final dot = tester.widget<Container>(find.byKey(const Key('homeRecentDot-1')));
      expect((dot.decoration! as BoxDecoration).color, AppPalette.light.typeBuyGoods);
      expect(tester.getSize(find.byKey(const Key('homeRecentDot-1'))), const Size(9, 9));
      final name = tester.widget<Text>(find.text('PARTY NUMBER 1 WITH A VERY LONG NAME THAT MUST ELLIPSISE'));
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.maxLines, 1);
      expect(find.text('Ksh 10.00'), findsOneWidget);
    });

    testWidgets('tapping a row hands its id to Analytics, as before', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, recentCount: 3));
      await tester.tap(find.byKey(const Key('homeRecentRow-2')));
      await tester.pumpAndSettle();
      expect(_pushed.single.name, Routes.analytics);
      expect(_pushed.single.arguments, 2);
    });

    testWidgets('empty state', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning));
      expect(find.text('No transactions yet. Tap + to add one.'), findsOneWidget);
    });

    testWidgets('fallback: when not even one row fits, the page scrolls instead of squeezing', (tester) async {
      await _pumpHome(
        tester,
        _FakeHomeDb(now: _morning, thisTotal: 1000, recentCount: 30),
        size: const Size(320, 480),
        textScale: 2.0,
      );
      // (skipOffstage: false — the list starts below the fold here.)
      expect(find.byKey(const Key('homeRecentFallback'), skipOffstage: false), findsOneWidget);
      expect(find.byKey(const Key('homeRecentFit'), skipOffstage: false), findsNothing);
      expect(_recentRows(skipOffstage: false), findsNWidgets(homeRecentFallbackRows));
      expect(_homeScroll(tester).maxScrollExtent, greaterThan(0));

      // Every row is readable once scrolled to: full height, not clipped.
      await tester.dragUntilVisible(
        find.byKey(const Key('homeRecentRow-$homeRecentFallbackRows')),
        find.byKey(const Key('homeScroll')),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      final first = tester.getSize(find.byKey(const Key('homeRecentRow-1'))).height;
      final last = tester.getSize(find.byKey(const Key('homeRecentRow-$homeRecentFallbackRows'))).height;
      expect(last, first);
    });
  });

  group('theme: Home follows the phone', () {
    for (final brightness in Brightness.values) {
      final palette = AppPalette.forBrightness(brightness);
      testWidgets('${brightness.name} phone -> Ocean & Sun ${brightness.name} on Home and its chrome', (tester) async {
        await _pumpHome(tester, _FakeHomeDb(now: _morning, recentCount: 2), brightness: brightness);
        expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, palette.background);
        expect(_boxColor(tester, const Key('homeSummaryCard')), palette.card);
        expect(_boxColor(tester, const Key('homeRecentCard')), palette.card);
        expect(_boxColor(tester, const Key('primaryBottomNav')), palette.card);
        final fab = tester.widget<Material>(find.byKey(const Key('primaryFab')));
        expect(fab.color, palette.primary);
        final plus = tester.widget<Icon>(
          find.descendant(of: find.byKey(const Key('primaryFab')), matching: find.byIcon(Icons.add)),
        );
        expect(plus.color, palette.onPrimary);
        final homeLabel = find.descendant(of: find.byKey(const Key('primaryBottomNav')), matching: find.text('Home'));
        expect(_textColor(tester, homeLabel), palette.primary);
        final appBar = tester.widget<AppBar>(find.byType(AppBar));
        expect(appBar.systemOverlayStyle, palette.systemOverlayStyle);
        expect(appBar.backgroundColor!, isA<WidgetStateColor>());
        expect((appBar.backgroundColor! as WidgetStateColor).resolve(<WidgetState>{}), palette.background);
        // The bars use this theme's chart colours.
        final fill = tester.widget<DecoratedBox>(
          find.descendant(of: find.byKey(const Key('homeBar-CASH')), matching: find.byType(DecoratedBox)),
        );
        expect((fill.decoration as BoxDecoration).color, palette.typeCash);
      });
    }
  });

  group('pull to refresh (T21)', () {
    testWidgets('re-queries and recomputes the time-derived values: the greeting and the period bounds', (
      tester,
    ) async {
      var clock = DateTime(2026, 9, 30, 11, 50);
      final db = _FakeHomeDb(now: clock, thisTotal: 1000, recentCount: 2);
      await _pumpHome(tester, db, clock: () => clock);
      expect(find.text('Good morning'), findsOneWidget);
      expect(tester.widget<RefreshIndicator>(find.byKey(const Key('homeRefresh'))).color, AppPalette.light.primary);

      // Home stays open past noon and into a new month; the user pulls.
      clock = DateTime(2026, 10, 1, 12, 10);
      final before = db.sumStarts.length;
      await tester.fling(find.byKey(const Key('homeScroll')), const Offset(0, 400), 1500);
      await tester.pumpAndSettle();

      expect(find.text('Good afternoon'), findsOneWidget);
      expect(find.text('Good morning'), findsNothing);
      final newStarts = db.sumStarts.skip(before).toList();
      expect(newStarts, contains(HomePeriod.month.bounds(clock).$1), reason: 'October, not September');
      expect(newStarts, isNot(contains(HomePeriod.month.bounds(DateTime(2026, 9, 30)).$1)));
    });
  });

  group('coach tour', () {
    setUp(() => CoachTour.autoStartDisabled = false);
    tearDown(() => CoachTour.autoStartDisabled = true);

    Future<Object?> storedSeen() async => (await SharedPreferences.getInstance()).getBool('tour_seen_$homeTourId');

    testWidgets('first visit with data: 4 steps; Analytics and Add carry "Take me there"', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHome(tester, _FakeHomeDb(now: _morning, thisTotal: 1000, recentCount: 3));
      expect(find.text('1 of 4'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsNothing);

      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      expect(find.text('2 of 4'), findsOneWidget);

      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      expect(find.text('3 of 4'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsOneWidget);

      await tester.tap(find.byKey(coachTourNextKey));
      await tester.pumpAndSettle();
      expect(find.text('4 of 4'), findsOneWidget);
      expect(find.byKey(coachTourActionKey), findsOneWidget);

      await tester.tap(find.byKey(coachTourNextKey)); // Done
      await tester.pumpAndSettle();
      expect(find.byKey(coachTourBubbleKey), findsNothing);
      expect(await storedSeen(), isTrue);
    });

    testWidgets('step 1 spotlights the period button: the bubble sits right under it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHome(tester, _FakeHomeDb(now: _morning, thisTotal: 1000, recentCount: 3));
      final button = tester.getRect(find.byKey(const Key('homePeriodButton')));
      final bubble = tester.getRect(find.byKey(coachTourBubbleKey));
      expect(bubble.top, moreOrLessEquals(button.bottom + 6 + 12, epsilon: 1));
    });

    testWidgets('no transactions yet: a single pointer at +', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await _pumpHome(tester, _FakeHomeDb(now: _morning));
      expect(find.text('1 of 1'), findsOneWidget);
      expect(find.textContaining('Add your first transaction'), findsOneWidget);
    });

    testWidgets('the header ? replays a seen tour; Take me there on + opens Add', (tester) async {
      await _pumpHome(tester, _FakeHomeDb(now: _morning, thisTotal: 1000, recentCount: 3));
      expect(find.byKey(coachTourBubbleKey), findsNothing);

      await tester.tap(find.byKey(const Key('pageHelpButton')));
      await tester.pumpAndSettle();
      expect(find.text('1 of 4'), findsOneWidget);

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(coachTourNextKey));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(coachTourActionKey));
      await tester.pumpAndSettle();
      expect(_pushed.map((s) => s.name), contains(Routes.add));
    });
  });
}
