// 0.1.2 S6c: the Analytics filter state (MS1 class set, TL1 type set), pure.
// matches for every combination, chip labels and "+ n more", the empty text,
// onlyWithdrawal, the By type percentages, hand-off sets. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/route_args.dart';

AnalyticsTransactionRow _row(String type, String cls, {int amount = 10000}) => AnalyticsTransactionRow(
  id: 1,
  displayCode: 'X1',
  sourceType: type,
  amountCents: amount,
  counterpartyLabel: 'Invented',
  counterpartyPhone: null,
  paybillAccountNumber: null,
  classificationId: 1,
  classificationName: cls,
  occurredAt: DateTime(2026, 10, 14, 9),
  transactionCostCents: 0,
);

void main() {
  final sm = _row('SEND_MONEY', 'Rent');
  final smFood = _row('SEND_MONEY', 'Groceries');
  final pb = _row('PAYBILL', 'Rent');
  final cash = _row('CASH', 'Transport');
  final wd = _row('AGENT_WITHDRAWAL', 'Withdrawal');
  final all = [sm, smFood, pb, cash, wd];
  List<AnalyticsTransactionRow> hits(AnalyticsFilters f) => all.where(f.matches).toList();

  group('matches', () {
    test('no filter matches every row', () {
      expect(hits(AnalyticsFilters.none), all);
      expect(AnalyticsFilters.none.isEmpty, isTrue);
    });

    test('types only: OR within the set', () {
      expect(hits(AnalyticsFilters.none.toggleType('SEND_MONEY')), [sm, smFood]);
      expect(hits(AnalyticsFilters.none.toggleType('SEND_MONEY').toggleType('CASH')), [sm, smFood, cash]);
    });

    test('classes only: OR within the set', () {
      expect(hits(AnalyticsFilters.none.toggleClass('Rent')), [sm, pb]);
      expect(hits(AnalyticsFilters.none.toggleClass('Rent').toggleClass('Transport')), [sm, pb, cash]);
    });

    test('both sets: AND between them, OR inside each', () {
      final f = AnalyticsFilters.none.toggleType('SEND_MONEY').toggleType('PAYBILL').toggleClass('Rent');
      expect(hits(f), [sm, pb]);
      final g = AnalyticsFilters.none.toggleType('SEND_MONEY').toggleClass('Rent').toggleClass('Groceries');
      expect(hits(g), [sm, smFood]);
    });

    test('one type + one class', () {
      expect(hits(AnalyticsFilters.handOff(type: 'PAYBILL', classification: 'Rent')), [pb]);
      expect(hits(AnalyticsFilters.handOff(type: 'CASH', classification: 'Rent')), isEmpty);
    });

    test('a toggle twice is back to the start; toggling never mutates the old state', () {
      final a = AnalyticsFilters.none.toggleType('CASH');
      final b = a.toggleType('CASH');
      expect(b.types, isEmpty);
      expect(a.types, {'CASH'});
      expect(() => a.types.add('X'), throwsUnsupportedError);
    });
  });

  group('chips and the empty text', () {
    test('one type: its name; more: first + n more, in the order picked', () {
      expect(AnalyticsFilters.none.typeChipLabel, '');
      expect(AnalyticsFilters.none.toggleType('PAYBILL').typeChipLabel, 'Paybill');
      final f = AnalyticsFilters.none.toggleType('PAYBILL').toggleType('SEND_MONEY').toggleType('CASH');
      expect(f.typeChipLabel, 'Paybill + 2 more');
    });

    test('one class: its name; more: first + n more', () {
      final f = AnalyticsFilters.none.toggleClass('Groceries').toggleClass('Rent').toggleClass('Fuel');
      expect(f.classChipLabel, 'Groceries + 2 more');
      expect(AnalyticsFilters.none.toggleClass('Rent').classChipLabel, 'Rent');
    });

    test('orList reads "a, b or c"', () {
      expect(AnalyticsFilters.orList(['a']), 'a');
      expect(AnalyticsFilters.orList(['a', 'b']), 'a or b');
      expect(AnalyticsFilters.orList(['a', 'b', 'c']), 'a, b or c');
    });

    test('empty text: types, categories in brackets after them, categories alone', () {
      expect(AnalyticsFilters.none.emptyText, 'No transactions in this period.');
      expect(AnalyticsFilters.none.toggleType('PAYBILL').emptyText, 'No Paybill transactions in this period.');
      final t = AnalyticsFilters.none.toggleType('PAYBILL').toggleType('SEND_MONEY').toggleType('CASH');
      expect(t.emptyText, 'No Paybill, Send Money or Cash transactions in this period.');
      expect(
        t.toggleClass('Rent').toggleClass('Fuel').emptyText,
        'No Paybill, Send Money or Cash (Rent or Fuel) transactions in this period.',
      );
      expect(AnalyticsFilters.none.toggleClass('Rent').emptyText, 'No Rent transactions in this period.');
      expect(
        AnalyticsFilters.none.toggleClass('Rent').toggleClass('Fuel').toggleClass('Gas').emptyText,
        'No Rent, Fuel or Gas transactions in this period.',
      );
    });
  });

  group('onlyWithdrawal', () {
    test('true only when the type set is exactly {Withdrawal}', () {
      expect(AnalyticsFilters.none.toggleType('AGENT_WITHDRAWAL').onlyWithdrawal, isTrue);
      expect(AnalyticsFilters.none.toggleType('AGENT_WITHDRAWAL').toggleClass('Rent').onlyWithdrawal, isTrue);
      expect(AnalyticsFilters.none.toggleType('AGENT_WITHDRAWAL').toggleType('CASH').onlyWithdrawal, isFalse);
      expect(AnalyticsFilters.none.toggleType('CASH').onlyWithdrawal, isFalse);
      expect(AnalyticsFilters.none.onlyWithdrawal, isFalse);
    });
  });

  group('By type percentages', () {
    // Amounts in the period (already following the class set): SM 500, PB 300, CASH 200, WD 900.
    final by = {'SEND_MONEY': 500, 'PAYBILL': 300, 'CASH': 200, 'AGENT_WITHDRAWAL': 900};
    const total = 1000;

    String text(AnalyticsFilters f, String code) =>
        typeShareText(f, code, by[code] ?? 0, typeShareBase(f, by, total));

    test('nothing selected: against the whole spending total', () {
      expect(text(AnalyticsFilters.none, 'SEND_MONEY'), '50%');
      expect(text(AnalyticsFilters.none, 'CASH'), '20%');
      expect(text(AnalyticsFilters.none, 'AGENT_WITHDRAWAL'), 'tracked');
    });

    test('a selection: the share of the selected types total, the others a dash', () {
      final f = AnalyticsFilters.none.toggleType('SEND_MONEY').toggleType('PAYBILL');
      expect(typeShareBase(f, by, total), 800);
      expect(text(f, 'SEND_MONEY'), '63%');
      expect(text(f, 'PAYBILL'), '38%');
      expect(text(f, 'CASH'), '—');
    });

    test('a withdrawal in the set adds nothing to the base and keeps "tracked"', () {
      final f = AnalyticsFilters.none.toggleType('SEND_MONEY').toggleType('AGENT_WITHDRAWAL');
      expect(typeShareBase(f, by, total), 500);
      expect(text(f, 'SEND_MONEY'), '100%');
      expect(text(f, 'AGENT_WITHDRAWAL'), 'tracked');
      expect(text(f, 'PAYBILL'), '—');
    });

    test('only Withdrawal selected: nothing to share, every other tile a dash', () {
      final f = AnalyticsFilters.none.toggleType('AGENT_WITHDRAWAL');
      expect(typeShareBase(f, by, total), 0);
      expect(text(f, 'SEND_MONEY'), '—');
      expect(text(f, 'AGENT_WITHDRAWAL'), 'tracked');
    });

    test('no spending at all: a dash, not a division by zero', () {
      expect(typeShareText(AnalyticsFilters.none, 'CASH', 0, 0), '—');
    });
  });

  group('hand-offs', () {
    test('a type and a class from Home or Paid to become a set of one each', () {
      final f = AnalyticsFilters.handOff(type: 'PAYBILL', classification: 'Rent');
      expect(f.types, {'PAYBILL'});
      expect(f.classes, {'Rent'});
      expect(AnalyticsFilters.handOff(type: 'CASH').classes, isEmpty);
      expect(AnalyticsFilters.handOff(classification: 'Rent').types, isEmpty);
    });

    test('the route arguments resolve to the same strings the screen turns into sets', () {
      final r = AnalyticsResolvedArgs.resolve(const AnalyticsRouteArgs(type: 'PAYBILL', classification: 'Rent'));
      final f = AnalyticsFilters.handOff(type: r.type, classification: r.classification);
      expect(f.types, {'PAYBILL'});
      expect(f.classes, {'Rent'});
    });
  });
}
