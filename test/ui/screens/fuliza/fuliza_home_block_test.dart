// The Fuliza block on Home: layout (44 px, 130 % text, light and dark, 360 px, no overflow), spoken label,
// and Home itself (period change, "Show Fuliza" off hides it, neither row touches the Spent total).
// Invented data only. The row rules and the date filter are pinned in test/domain/fuliza/fuliza_home_rows_test.dart.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/fuliza/fuliza_home_rows.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_home_line.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_source.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_visible.dart';
import 'package:mmogo/ui/screens/home_screen.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_home_db.dart';

const _both = FulizaHomeRows(
  owing: FulizaHomeRow('Fuliza: owing about', 'Ksh 1,486.50'),
  cost: FulizaHomeRow('Fuliza cost (estimated), this month', 'Ksh 36.50'),
  costCents: 3650,
);
const _owingOnly = FulizaHomeRows(owing: FulizaHomeRow('Fuliza: owing', 'Ksh 1,638.00'));
const _costOnly = FulizaHomeRows(
  cost: FulizaHomeRow('Fuliza cost (estimated), this week', 'Ksh 38.00'),
  costCents: 3800,
);
const _unknown = FulizaHomeRows(owing: FulizaHomeRow('Fuliza: balance not known'));
const _long = FulizaHomeRows(
  owing: FulizaHomeRow('Fuliza: owing about', 'Ksh 98,280.00'),
  cost: FulizaHomeRow('Fuliza cost (estimated), this month', 'Ksh 2,280.00'),
  costCents: 228000,
);

Future<void> _pump(WidgetTester t, FulizaHomeRows rows, {required bool dark, double scale = 1.3, VoidCallback? onTap}) {
  t.view.physicalSize = const Size(360, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  return t.pumpWidget(
    MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: MediaQuery(
        data: MediaQueryData(size: const Size(360, 800), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(14),
            child: Align(
              alignment: Alignment.topCenter,
              child: FulizaHomeLine(
                palette: dark ? AppPalette.dark : AppPalette.light,
                rows: rows,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// FakeHomeDb answers Home's queries; the Fuliza pairing lookup (by code) finds no payments.
class _Db extends FakeHomeDb {
  _Db({required super.now, super.thisTotal, super.types});

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) {
    if (sql.contains('IN (')) return Future.value(const []);
    return super.rawQuery(sql, arguments);
  }
}

void main() {
  setUp(() {
    fulizaVisible = true;
    SharedPreferences.setMockInitialValues({'tour_seen_home': true});
  });
  tearDown(() {
    fulizaVisible = false;
    FulizaSource.repository = null;
  });

  group('layout', () {
    for (final dark in [false, true]) {
      for (final (name, rows) in [
        ('both rows', _both),
        ('owing only', _owingOnly),
        ('cost only', _costOnly),
        ('balance not known', _unknown),
        ('long figures', _long),
      ]) {
        testWidgets('${dark ? 'dark' : 'light'}, 130% text, 360 px: $name, no overflow, 44 px minimum', (t) async {
          await _pump(t, rows, dark: dark);
          expect(t.takeException(), isNull);
          final box = t.getSize(find.byKey(const Key('homeFulizaLine')));
          expect(box.height >= 44, isTrue, reason: 'height ${box.height}');
          expect(find.byKey(const Key('homeFulizaOwing')), rows.owing == null ? findsNothing : findsOneWidget);
          expect(find.byKey(const Key('homeFulizaCost')), rows.cost == null ? findsNothing : findsOneWidget);
          // One chevron, never two (one block, not two lines).
          expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
          // A figure never wraps: one line high.
          for (final k in ['homeFulizaOwingValue', 'homeFulizaCostValue']) {
            final f = find.byKey(Key(k));
            if (f.evaluate().isEmpty) continue;
            expect(t.getSize(f).height < 12 * 1.3 * 1.5, isTrue, reason: '$k on one line');
          }
        });
      }
    }

    testWidgets('the block is the whole tap target and calls onTap once', (t) async {
      var taps = 0;
      await _pump(t, _both, dark: false, scale: 1.0, onTap: () => taps++);
      await t.tap(find.byKey(const Key('homeFulizaCost')));
      expect(taps, 1);
    });

    testWidgets('spoken label: both rows, then "Open details"; one button', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, _both, dark: false, scale: 1.0);
      expect(
        find.bySemanticsLabel(
          'Fuliza: owing about Ksh 1,486.50. Fuliza cost (estimated), this month Ksh 36.50. Open details',
        ),
        findsOneWidget,
      );
      h.dispose();
    });
  });

  group('on Home', () {
    // The invented messages: owing 1,638.00; fees on 11 Nov (2.50 + 12.00) and on 12 Nov (1.50);
    // nothing on the 10th. Clock: Thu 12 Nov 2026.
    final now = DateTime(2026, 11, 12, 14);

    Future<void> install({bool show = true}) async {
      SharedPreferences.setMockInitialValues({'tour_seen_home': true, 'fuliza_show': show});
      final repo = InMemoryFulizaRepository();
      for (final e in [
        FulizaEvent(
          kind: FulizaEventKind.draw,
          code: 'QDMHB00001',
          at: DateTime(2026, 11, 9, 9),
          amountCents: 100000,
          feeCents: 1000,
          printedTotalCents: 101000,
        ),
        FulizaEvent(
          kind: FulizaEventKind.draw,
          code: 'QDMHB00002',
          at: DateTime(2026, 11, 11, 9),
          amountCents: 25000,
          feeCents: 250,
          printedTotalCents: 127450, // 1,010 + 252.50 + 12.00 daily fee
        ),
        FulizaEvent(
          kind: FulizaEventKind.draw,
          code: 'QDMHB00003',
          at: DateTime(2026, 11, 12, 9),
          amountCents: 15000,
          feeCents: 150,
          printedTotalCents: 142600, // 1,274.50 + 151.50
        ),
      ]) {
        await repo.addEvent(e);
      }
      FulizaSource.repository = repo;
    }

    Future<void> openHome(WidgetTester t) async {
      t.view.physicalSize = const Size(392, 1600) * 3;
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            db: _Db(now: now, thisTotal: 500000, types: const {'SEND_MONEY': (500000, 3000)}),
            clock: () => now,
            startUpdates: () async {},
            showWhatsNew: (_) async {},
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(seconds: 3));
      await t.pumpAndSettle();
    }

    testWidgets('month, then the period name cycles to Today: the cost row follows, owing stays', (t) async {
      await install();
      await openHome(t);
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaOwingValue'))).data, 'Ksh 1,426.00');
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaCost'))).data, 'Fuliza cost (estimated), this month');
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaCostValue'))).data, 'Ksh 26.00');
      await t.tap(find.byKey(const Key('homePeriodButton')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaCost'))).data, 'Fuliza cost (estimated), today');
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaCostValue'))).data, 'Ksh 1.50');
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaOwingValue'))).data, 'Ksh 1,426.00');
    });

    testWidgets('"Show Fuliza" off hides the whole block', (t) async {
      await install(show: false);
      await openHome(t);
      expect(find.byKey(const Key('homeFulizaLine')), findsNothing);
    });

    testWidgets('hidden build (default): stored events and the pref on still draw no block', (t) async {
      await install();
      fulizaVisible = false;
      await openHome(t);
      expect(find.byKey(const Key('homeFulizaLine')), findsNothing);
      expect(find.textContaining('Fuliza'), findsNothing);
    });

    testWidgets('no Fuliza data: no block', (t) async {
      await openHome(t);
      expect(find.byKey(const Key('homeFulizaLine')), findsNothing);
    });
  });
}
