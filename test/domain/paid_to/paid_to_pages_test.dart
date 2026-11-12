// 0.2.0 S8 — the paging maths of Paid to's Paybill ACCOUNTS block (pages of 5) and the
// "a named Paybill is one recipient" grouping that feeds it (debug flavor switch, default off).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/paid_to/paid_to_counts.dart';
import 'package:mmogo/domain/paid_to/paid_to_pages.dart';

PaidToPayment _pb(String name, String acc, int ksh, {DateTime? at, int fee = 0}) => PaidToPayment(
  sourceType: 'PAYBILL',
  amountCents: ksh * 100,
  feeCents: fee * 100,
  occurredAt: at ?? DateTime(2026, 10, 5, 10),
  classificationName: 'Bills',
  label: name,
  account: acc,
);

void main() {
  tearDown(() => PaidToGrouping.paybillByName = false);

  group('paging maths', () {
    test('page counts: 25 -> 5, 24 -> 5, 26 -> 6, 0 -> 0, 5 -> 1, 6 -> 2, 1 -> 1', () {
      expect(paidToPageCount(25), 5);
      expect(paidToPageCount(24), 5);
      expect(paidToPageCount(26), 6);
      expect(paidToPageCount(0), 0);
      expect(paidToPageCount(5), 1);
      expect(paidToPageCount(6), 2);
      expect(paidToPageCount(1), 1);
      expect(paidToPageCount(-3), 0);
    });

    test('pages only above 5 records', () {
      expect(paidToNeedsPages(0), isFalse);
      expect(paidToNeedsPages(5), isFalse);
      expect(paidToNeedsPages(6), isTrue);
    });

    test('items per page: 25 -> 5 x 5; 24 -> 5,5,5,5,4; 26 -> last page has 1; 0 -> none', () {
      List<int> sizes(int n) {
        final items = List.generate(n, (i) => i);
        return [for (var k = 0; k < paidToPageCount(n); k++) paidToPageItems(items, k).length];
      }

      expect(sizes(25), [5, 5, 5, 5, 5]);
      expect(sizes(24), [5, 5, 5, 5, 4]);
      expect(sizes(26), [5, 5, 5, 5, 5, 1]);
      expect(sizes(0), isEmpty);
    });

    test('every record is on exactly one page, in order, for 24, 25 and 26', () {
      for (final n in [24, 25, 26]) {
        final items = List.generate(n, (i) => i);
        final all = [for (var k = 0; k < paidToPageCount(n); k++) ...paidToPageItems(items, k)];
        expect(all, items, reason: '$n records');
      }
    });

    test('out-of-range page is empty', () {
      expect(paidToPageItems([1, 2, 3], 1), isEmpty);
      expect(paidToPageItems([1, 2, 3], -1), isEmpty);
      expect(paidToPageItems(<int>[], 0), isEmpty);
    });

    test('label "Page n of N" is clamped and empty for no pages', () {
      expect(paidToPageLabel(0, 5), 'Page 1 of 5');
      expect(paidToPageLabel(4, 5), 'Page 5 of 5');
      expect(paidToPageLabel(9, 5), 'Page 5 of 5');
      expect(paidToPageLabel(-1, 5), 'Page 1 of 5');
      expect(paidToPageLabel(0, 0), '');
    });

    test('scroll offset -> page (nearest), clamped', () {
      expect(paidToPageAt(0, 300, 5), 0);
      expect(paidToPageAt(149, 300, 5), 0);
      expect(paidToPageAt(150, 300, 5), 1);
      expect(paidToPageAt(1200, 300, 5), 4);
      expect(paidToPageAt(5000, 300, 5), 4);
      expect(paidToPageAt(-20, 300, 5), 0);
      expect(paidToPageAt(10, 0, 5), 0);
      expect(paidToPageAt(10, 300, 0), 0);
    });
  });

  group('Paybill by name (switch)', () {
    final pays = [
      for (var i = 0; i < 25; i++) _pb('DIRECT PAY 04', '70000${i.toString().padLeft(2, '0')}', 100 + i, fee: i.isEven ? 5 : 0),
      _pb('DIRECT PAY 05', '811', 300),
      _pb('DIRECT PAY 05', '811', 200),
      _pb('DSTV KENYA', '5566', 1200),
    ];

    test('default OFF = 0.1.3: one row per name + account (27 rows)', () {
      expect(PaidToGrouping.paybillByName, isFalse);
      final g = paidToGroups(pays, type: 'PAYBILL');
      expect(g.length, 27);
      expect(g.every((r) => !r.hasManyAccounts), isTrue);
    });

    test('ON: one row per name (3 rows); DIRECT PAY 04 has 25 accounts, 5 pages', () {
      PaidToGrouping.paybillByName = true;
      final g = paidToGroups(pays, type: 'PAYBILL');
      expect(g.length, 3);
      final d4 = g.firstWhere((r) => r.name == 'DIRECT PAY 04');
      expect(d4.accounts.length, 25);
      expect(d4.count, 25);
      expect(d4.hasManyAccounts, isTrue);
      expect(d4.detail, '25 accounts');
      expect(paidToPageCount(d4.accounts.length), 5);
      final d5 = g.firstWhere((r) => r.name == 'DIRECT PAY 05');
      expect(d5.accounts.length, 1);
      expect(d5.hasManyAccounts, isFalse);
      expect(d5.count, 2);
    });

    test('C-10: money and payment counts agree with and without the switch', () {
      int sum(Iterable<PaidToRecipient> g, int Function(PaidToRecipient) f) => g.fold(0, (s, r) => s + f(r));
      final off = paidToGroups(pays, type: 'PAYBILL');
      PaidToGrouping.paybillByName = true;
      final on = paidToGroups(pays, type: 'PAYBILL');
      expect(sum(on, (r) => r.totalCents), sum(off, (r) => r.totalCents));
      expect(sum(on, (r) => r.count), sum(off, (r) => r.count));
      expect(sum(on, (r) => r.feeCents), sum(off, (r) => r.feeCents));
      expect(sum(on, (r) => r.count), pays.length);
      final hero = paidToCounts(pays);
      expect(hero.by['PAYBILL'], 3);
    });

    test('accounts are biggest total first, then latest; account totals add up to the row', () {
      PaidToGrouping.paybillByName = true;
      final d4 = paidToGroups(pays, type: 'PAYBILL').firstWhere((r) => r.name == 'DIRECT PAY 04');
      final totals = [for (final a in d4.accounts) a.totalCents];
      expect([...totals]..sort((a, b) => b.compareTo(a)), totals);
      expect(totals.fold<int>(0, (s, c) => s + c), d4.totalCents);
      expect(d4.accounts.fold<int>(0, (s, a) => s + a.feeCents), d4.feeCents);
    });

    test('search finds an account number inside a grouped name', () {
      PaidToGrouping.paybillByName = true;
      final g = paidToGroups(pays, type: 'PAYBILL', term: '7000007');
      expect(g.map((r) => r.name), ['DIRECT PAY 04']);
    });

    test('a Paybill with the same name in other case / spacing is one row', () {
      PaidToGrouping.paybillByName = true;
      final g = paidToGroups([_pb('Direct  Pay 04', '1', 10), _pb('DIRECT PAY 04', '2', 20)], type: 'PAYBILL');
      expect(g.length, 1);
      expect(g.single.accounts.length, 2);
    });

    test('other types are untouched by the switch', () {
      PaidToGrouping.paybillByName = true;
      final g = paidToGroups([
        PaidToPayment(
          sourceType: 'BUY_GOODS',
          amountCents: 1000,
          feeCents: 0,
          occurredAt: DateTime(2026, 10, 5),
          classificationName: 'x',
          label: 'SHOP',
        ),
      ]);
      expect(g.length, 1);
      expect(g.single.accounts, isEmpty);
    });
  });
}
