// T22 — the pure Paid to logic (lib/domain/paid_to/paid_to.dart): grouping
// (named by the authoritative counterparty key, unnamed by type +
// classification — the T15 rule), counts, categories, sorting and the
// period hand-off.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/analytics_period.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';

PaidToPayment _p(
  String type,
  int ksh, {
  String? label,
  String? phone,
  String? account,
  String cls = 'Rent',
  int fee = 0,
  DateTime? at,
}) => PaidToPayment(
  sourceType: type,
  amountCents: ksh * 100,
  feeCents: fee * 100,
  occurredAt: at ?? DateTime(2026, 9, 10),
  classificationName: cls,
  label: label,
  phone: phone,
  account: account,
);

void main() {
  final pays = [
    _p('SEND_MONEY', 1500, label: 'JOHN KAMAU', phone: '0798630424', cls: 'Family', fee: 22, at: DateTime(2026, 9, 24)),
    _p('SEND_MONEY', 500, label: 'JOHN  KAMAU', phone: '0798630424', cls: 'Family', fee: 7, at: DateTime(2026, 9, 2)),
    _p('SEND_MONEY', 2000, label: 'MARY', phone: '0712345678', fee: 25, at: DateTime(2026, 9, 15)),
    _p('SEND_MONEY', 300, cls: 'Family', at: DateTime(2026, 9, 20)), // unnamed
    _p('SEND_MONEY', 200, cls: 'Family', at: DateTime(2026, 9, 21)), // unnamed
    _p('SEND_MONEY', 100, cls: 'Rent', at: DateTime(2026, 9, 1)), // unnamed, other class
    _p('PAYBILL', 1200, label: 'DSTV', account: '5566', cls: 'Shopping', fee: 15),
    _p('PAYBILL', 900, label: 'DSTV', cls: 'Shopping'), // no account = unnamed (T15)
    _p('BUY_GOODS', 850, label: 'NAIVAS', cls: 'Shopping', at: DateTime(2026, 9, 23)),
  ];

  test('hasCapturedIdentity keeps the T15 per-type rule', () {
    expect(hasCapturedIdentity('SEND_MONEY', null, '0712', null), isTrue);
    expect(hasCapturedIdentity('SEND_MONEY', 'X', ' ', null), isFalse);
    expect(hasCapturedIdentity('PAYBILL', 'DSTV', null, '1'), isTrue);
    expect(hasCapturedIdentity('PAYBILL', 'DSTV', null, null), isFalse);
    expect(hasCapturedIdentity('BUY_GOODS', 'NAIVAS', null, null), isTrue);
    expect(hasCapturedIdentity('BUY_GOODS', '', null, null), isFalse);
    expect(hasCapturedIdentity('CASH', 'X', '1', '1'), isFalse);
  });

  group('groupPaidTo', () {
    test('named by counterparty key; unnamed by type + classification; nothing dropped', () {
      final gs = groupPaidTo(pays);
      expect(gs.fold<int>(0, (s, g) => s + g.count), pays.length);
      final john = gs.singleWhere((g) => g.name == 'JOHN KAMAU');
      expect(john.count, 2);
      expect(john.totalCents, 200000);
      expect(john.feeCents, 2900);
      expect(john.lastAt, DateTime(2026, 9, 24));
      expect(john.detail, '0798630424');
      expect(john.partyKey, '0798630424');
      final unnamedFamily = gs.singleWhere((g) => g.name == 'Unnamed · Family');
      expect(unnamedFamily.isUnnamed, isTrue);
      expect(unnamedFamily.count, 2);
      expect(unnamedFamily.totalCents, 50000);
      expect(unnamedFamily.detail, 'Receiver not recorded');
      expect(unnamedFamily.partyKey, isNull);
      expect(gs.where((g) => g.isUnnamed).map((g) => '${g.sourceType} ${g.classificationName}').toSet(), {
        'SEND_MONEY Family',
        'SEND_MONEY Rent',
        'PAYBILL Shopping',
      });
      expect(gs.singleWhere((g) => g.name == 'DSTV').detail, 'Acc 5566');
      expect(gs.singleWhere((g) => g.name == 'NAIVAS').detail, 'Merchant');
    });

    test('a classification narrows the payments first', () {
      final gs = groupPaidTo(pays, classification: 'Shopping');
      expect(gs.map((g) => g.name).toSet(), {'DSTV', 'Unnamed · Shopping', 'NAIVAS'});
    });
  });

  test('countPaidToRecipients: all, per type, per type + classification', () {
    expect(countPaidToRecipients(pays), 7);
    expect(countPaidToRecipients(pays, type: 'SEND_MONEY'), 4);
    expect(countPaidToRecipients(pays, type: 'PAYBILL'), 2);
    expect(countPaidToRecipients(pays, classification: 'Family'), 2);
    expect(countPaidToRecipients(pays, type: 'BUY_GOODS', classification: 'Rent'), 0);
  });

  test('paidToCategories: scoped to a type, most payments first, ties by name', () {
    expect(paidToCategories(pays), [('Family', 4), ('Shopping', 3), ('Rent', 2)]);
    expect(paidToCategories(pays, type: 'SEND_MONEY'), [('Family', 4), ('Rent', 2)]);
    expect(paidToCategories(pays, type: 'BUY_GOODS'), [('Shopping', 1)]);
  });

  group('sortPaidTo', () {
    List<String> names(PaidToSort s) {
      final gs = groupPaidTo(pays.where((p) => p.sourceType == 'SEND_MONEY'));
      sortPaidTo(gs, s);
      return gs.map((g) => g.name).toList();
    }

    test('Amount: total, then times paid', () {
      expect(names(PaidToSort.amount), ['JOHN KAMAU', 'MARY', 'Unnamed · Family', 'Unnamed · Rent']);
    });

    test('Times paid: count, then total', () {
      expect(names(PaidToSort.timesPaid), ['JOHN KAMAU', 'Unnamed · Family', 'MARY', 'Unnamed · Rent']);
    });

    test('Most recent: the last payment', () {
      expect(names(PaidToSort.recent), ['JOHN KAMAU', 'Unnamed · Family', 'MARY', 'Unnamed · Rent']);
    });
  });

  test('section summary and nouns', () {
    final s = PaidToSection('SEND_MONEY', groupPaidTo(pays.where((p) => p.sourceType == 'SEND_MONEY')));
    expect(s.totalCents, 460000);
    expect(s.payments, 6);
    expect(s.feeCents, 5400);
    expect(paidToNoun('SEND_MONEY', 1), 'person');
    expect(paidToNoun('SEND_MONEY', 2), 'people');
    expect(paidToNoun('PAYBILL', 3), 'bills');
    expect(paidToNoun('BUY_GOODS', 1), 'shop');
  });

  group('periods', () {
    final today = DateTime(2026, 9, 24);

    test('paidToPeriodNow: the current one of each length', () {
      expect(paidToPeriodNow(AnalyticsGranularity.month, today), AnalyticsPeriod.month(today));
      expect(paidToPeriodNow(AnalyticsGranularity.year, today), AnalyticsPeriod.year(2026, today: today));
      expect(paidToPeriodNow(AnalyticsGranularity.all, today), AnalyticsPeriod.allTime(today));
    });

    test('analyticsPeriodForPaidTo: same length and anchor; an old month lands on the chart window', () {
      final may = analyticsPeriodForPaidTo(AnalyticsPeriod.month(DateTime(2026, 3, 1)), today);
      expect(may.granularity, AnalyticsGranularity.month);
      expect(may.range(today: today), DayRange(DateTime(2026, 3, 1), DateTime(2026, 3, 31)));
      expect(may.monthWindowEnd, DateTime(2026, 5, 1));
      final sep = analyticsPeriodForPaidTo(AnalyticsPeriod.month(today), today);
      expect(sep.monthWindowEnd, isNull);
      expect(
        analyticsPeriodForPaidTo(AnalyticsPeriod.year(2025, today: today), today),
        AnalyticsPeriod.year(2025, today: today),
      );
      expect(analyticsPeriodForPaidTo(AnalyticsPeriod.allTime(today), today), AnalyticsPeriod.allTime(today));
    });
  });
}
