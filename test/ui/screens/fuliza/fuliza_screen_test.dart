// 0.2.0 S9: the Fuliza page, its Related arrow (opens THAT borrowing inside the page, Back returns), the Home
// V3 line, and "no data = nothing drawn". Invented data only; the page runs on a loader, not a database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/fuliza/fuliza_demo.dart';
import 'package:mmogo/domain/fuliza/fuliza_ledger.dart';
import 'package:mmogo/domain/fuliza/fuliza_page_data.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_home_line.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_screen.dart';
import 'package:mmogo/ui/screens/fuliza/fuliza_source.dart';
import 'package:mmogo/ui/theme/app_colors.dart';

import '../../../support/fake_analytics_db.dart';

final _now = DateTime(2026, 11, 3, 12);

AnalyticsTransactionRow _tx(int id, String code, String type, String label, int ksh, DateTime at) =>
    AnalyticsTransactionRow(
      id: id,
      displayCode: code,
      sourceType: type,
      amountCents: ksh * 100,
      counterpartyLabel: label,
      counterpartyPhone: null,
      paybillAccountNumber: null,
      classificationId: 1,
      classificationName: 'Shopping',
      occurredAt: at,
      transactionCostCents: 0,
    );

FulizaSnapshot _snap(List<FulizaEvent> events) {
  final spends = [
    _tx(1, 'QDMFL00001', 'BUY_GOODS', 'JAVA HOUSE', 900, _now.subtract(const Duration(days: 6))),
    _tx(2, 'QDMFL00002', 'SEND_MONEY', 'MARY WANJIKU', 400, _now.subtract(const Duration(days: 3))),
    _tx(4, 'QDMFL00004', 'PAYBILL', 'DSTV KENYA', 500, _now.subtract(const Duration(days: 1))),
  ];
  final byCode = {for (final s in spends) s.displayCode: s};
  final state = FulizaCalculator.compute(events, byCode.keys.toSet());
  return FulizaSnapshot(buildFulizaPage(state, events)!, byCode);
}

Widget _app(Widget home) => MaterialApp(home: home);

void _phone(WidgetTester t) {
  t.view.physicalSize = const Size(400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Finder _scroller() => find.byType(Scrollable).first;

void main() {
  tearDown(() => FulizaSource.repository = null);

  group('the page', () {
    testWidgets('summary, fees, history, carried in, estimate note, related', (t) async {
      _phone(t);
      final snap = _snap(demoFulizaEvents(_now));
      await t.pumpWidget(_app(FulizaScreen(loader: () async => snap)));
      await t.pumpAndSettle();
      expect(find.text('Owing now'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('fulizaOwingAmount'))).data, 'about Ksh 1,227.00');
      expect(find.byKey(const Key('fulizaEstimateNote')), findsOneWidget);
      expect(find.text('Taken'), findsOneWidget);
      expect(find.text('Repaid'), findsOneWidget);
      expect(find.text('Fuliza cost'), findsOneWidget);
      expect(find.text('(estimated)'), findsWidgets);
      expect(find.text('Ksh 1,500'), findsOneWidget); // taken
      expect(find.text('Ksh 500'), findsWidgets); // repaid
      await t.scrollUntilVisible(find.byKey(const Key('fulizaCarriedIn')), 300, scrollable: _scroller());
      expect(find.text('Carried in from before the data'), findsOneWidget);
      expect(find.textContaining('about Ksh 200 was already owed'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const Key('fulizaRelated-QDMFL00001')), 300, scrollable: _scroller());
      expect(find.text('Part on Fuliza'), findsOneWidget); // 600 of 900
      expect(find.text('On Fuliza'), findsNWidgets(2));
      expect(find.byKey(const Key('fulizaFocusBanner')), findsNothing);
    });

    testWidgets('owing unknown: a plain note and a dash, no amount', (t) async {
      _phone(t);
      final ev = [FulizaEvent(kind: FulizaEventKind.repayPartial, code: 'QDMFL00009', at: _now, amountCents: 20000)];
      final snap = FulizaSnapshot(buildFulizaPage(FulizaCalculator.compute(ev, {}), ev)!, const {});
      await t.pumpWidget(_app(FulizaScreen(loader: () async => snap)));
      await t.pumpAndSettle();
      expect(find.text('Owing unknown'), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('fulizaOwingAmount'))).data, '—');
      expect(find.byKey(const Key('fulizaUnknownNote')), findsOneWidget);
      expect(find.byKey(const Key('fulizaEstimateNote')), findsNothing);
    });

    testWidgets('nothing owed after a full repayment', (t) async {
      _phone(t);
      final ev = [
        FulizaEvent(
          kind: FulizaEventKind.draw,
          code: 'QDMFL00001',
          at: DateTime(2026, 10, 30, 9),
          amountCents: 50000,
          feeCents: 500,
          printedTotalCents: 50500,
        ),
        FulizaEvent(
          kind: FulizaEventKind.repayFull,
          code: 'QDMFL00005',
          at: DateTime(2026, 11, 1, 9),
          amountCents: 50500,
        ),
      ];
      final snap = FulizaSnapshot(buildFulizaPage(FulizaCalculator.compute(ev, {}), ev)!, const {});
      await t.pumpWidget(_app(FulizaScreen(loader: () async => snap)));
      await t.pumpAndSettle();
      expect(find.text('Nothing owed'), findsOneWidget);
      expect(find.textContaining('Paid back in full on 1 Nov'), findsOneWidget);
    });

    testWidgets('no data: the page says so', (t) async {
      await t.pumpWidget(_app(FulizaScreen(loader: () async => null)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('fulizaEmpty')), findsOneWidget);
    });
  });

  group('Related arrow and Back', () {
    testWidgets('the arrow opens THAT borrowing inside the Fuliza page, lit and in view; Back returns', (t) async {
      _phone(t);
      final snap = _snap(demoFulizaEvents(_now));
      final edited = <String>[];
      await t.pumpWidget(
        _app(FulizaScreen(loader: () async => snap, openEdit: (tx) async => edited.add(tx.displayCode))),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('fulizaShow-QDMFL00002')), 300, scrollable: _scroller());
      // The body of the row opens the edit sheet (here: the seam), the arrow does not.
      await t.tap(find.byKey(const Key('fulizaRelated-QDMFL00002')));
      await t.pumpAndSettle();
      expect(edited, ['QDMFL00002']);
      await t.tap(find.byKey(const Key('fulizaShow-QDMFL00002')));
      await t.pumpAndSettle();
      expect(edited, ['QDMFL00002'], reason: 'the arrow must not open the edit sheet');
      // A second Fuliza page: banner, the entry on screen.
      expect(find.byKey(const Key('fulizaFocusBanner')), findsOneWidget);
      expect(find.text('Showing this borrowing in the History'), findsOneWidget);
      expect(find.byType(FulizaScreen, skipOffstage: false), findsNWidgets(2));
      final entry = find.byKey(const Key('fulizaEntry-QDMFL00002-draw'));
      expect(entry, findsOneWidget);
      final box = t.getRect(entry);
      expect(box.top >= 0 && box.bottom <= 2400, isTrue, reason: 'scrolled into view');
      // Back returns to the first page, which still shows Related.
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(FulizaScreen), findsOneWidget);
      expect(find.byKey(const Key('fulizaFocusBanner')), findsNothing);
      expect(find.byKey(const Key('fulizaShow-QDMFL00002')), findsOneWidget);
    });

    testWidgets('the arrow is at least 44 x 44 and named for a screen reader', (t) async {
      _phone(t);
      final snap = _snap(demoFulizaEvents(_now));
      await t.pumpWidget(_app(FulizaScreen(loader: () async => snap)));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const Key('fulizaShow-QDMFL00001')), 300, scrollable: _scroller());
      final r = t.getRect(find.byKey(const Key('fulizaShow-QDMFL00001')));
      expect(r.width >= 44 && r.height >= 44, isTrue);
      expect(find.bySemanticsLabel('Show JAVA HOUSE in the Fuliza history'), findsOneWidget);
    });
  });

  group('Home V3 line', () {
    testWidgets('label, Details, chevron, tappable, at least 44 high', (t) async {
      var taps = 0;
      final d = _snap(demoFulizaEvents(_now)).data;
      await t.pumpWidget(
        _app(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: FulizaHomeLine(palette: AppPalette.light, data: d, onTap: () => taps++),
              ),
            ),
          ),
        ),
      );
      expect(t.widget<Text>(find.byKey(const Key('homeFulizaText'))).data, 'Fuliza · Owing about Ksh 1,227.00');
      expect(find.text('Details'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('homeFulizaLine'))).height >= 44, isTrue);
      await t.tap(find.byKey(const Key('homeFulizaLine')));
      expect(taps, 1);
    });

    testWidgets('large text 1.3 on a narrow card: no overflow', (t) async {
      final d = _snap(demoFulizaEvents(_now)).data;
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Scaffold(
              body: SizedBox(
                width: 300,
                child: FulizaHomeLine(palette: AppPalette.dark, data: d, onTap: () {}),
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
    });
  });

  group('no Fuliza data = no Fuliza anything', () {
    test('a normal build has no repository: load returns null', () async {
      expect(FulizaSource.repository, isNull);
      expect(await FulizaSource.load(FakeAnalyticsDb(analyticsSampleRows())), isNull);
    });

    test('an empty repository also returns null', () async {
      FulizaSource.repository = InMemoryFulizaRepository();
      expect(await FulizaSource.load(FakeAnalyticsDb(analyticsSampleRows())), isNull);
    });

    test('installDemoIfOn does nothing without the define', () async {
      await FulizaSource.installDemoIfOn(_now);
      expect(FulizaSource.repository, isNull);
    });
  });
}
