// 0.1.2 S7a (PT1): Paid to's domain rules for five types, Not recorded instead
// of Unnamed, the ONE counting function, search in any phone form, the fees
// sort and the hero numbers. Invented data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';
import 'package:mmogo/domain/paid_to/paid_to_counts.dart';

PaidToPayment _p(
  String type,
  int ksh, {
  String? label,
  String? phone,
  String? account,
  String? agent,
  String cls = 'Family',
  int fee = 0,
  int day = 10,
}) => PaidToPayment(
  sourceType: type,
  amountCents: ksh * 100,
  feeCents: fee * 100,
  occurredAt: DateTime(2026, 9, day),
  classificationName: cls,
  label: label,
  phone: phone,
  account: account,
  agentNumber: agent,
);

const sm = 'SEND_MONEY';
const pb = 'PAYBILL';
const bg = 'BUY_GOODS';
const po = paidToPochi;
const wd = paidToWithdrawal;

List<PaidToRecipient> _groups(List<PaidToPayment> ps, {String? type}) => paidToGroups(ps, type: type);

void main() {
  group('types', () {
    test('the domain knows five types in the mock order; the screen list stays three', () {
      expect(paidToAllTypes, ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL']);
      expect(paidToTypes, ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS']);
    });
  });

  group('captured identity per type', () {
    test('Pochi = phone or name; Withdrawal = agent number or name; the old three stay', () {
      expect(hasCapturedIdentity(po, null, '0722114455', null), isTrue);
      expect(hasCapturedIdentity(po, 'MAMA FUA', null, null), isTrue);
      expect(hasCapturedIdentity(po, ' ', ' ', null), isFalse);
      expect(hasCapturedIdentity(po, null, null, null), isFalse);
      expect(hasCapturedIdentity(wd, null, null, null, agentNumber: '123456'), isTrue);
      expect(hasCapturedIdentity(wd, 'JOY AGENT', null, null), isTrue);
      expect(hasCapturedIdentity(wd, ' ', null, null, agentNumber: ' '), isFalse);
      expect(hasCapturedIdentity(sm, 'X', ' ', null), isFalse);
      expect(hasCapturedIdentity(pb, 'DSTV', null, null), isFalse);
      expect(hasCapturedIdentity(bg, '', null, null), isFalse);
    });
  });

  group('who is one recipient', () {
    test('Send Money: every phone form is one; 07 and 01 are never merged', () {
      final gs = _groups([
        _p(sm, 100, phone: '0722114455', label: 'ANN'),
        _p(sm, 100, phone: '+254722114455', label: 'ANN W'),
        _p(sm, 100, phone: '254 722 114 455'),
        _p(sm, 100, phone: '00254722114455'),
        _p(sm, 100, phone: '0722-114-455'),
        _p(sm, 100, phone: '0122114455', label: 'ANN'),
        _p(sm, 100, phone: '+254122114455'),
      ]);
      expect(gs, hasLength(2));
      final seven = gs.singleWhere((g) => g.detail == '0722114455');
      expect(seven.count, 5);
      expect(gs.singleWhere((g) => g.detail == '0122114455').count, 2);
    });

    test('same name, different phone = two; same phone, different names and categories = one', () {
      final diffPhone = _groups([
        _p(sm, 10, label: 'CAROL', phone: '0711000001'),
        _p(sm, 10, label: 'CAROL', phone: '0711000002'),
      ]);
      expect(diffPhone, hasLength(2));
      final samePhone = _groups([
        _p(sm, 10, label: 'DAN', phone: '0733000003', cls: 'Rent'),
        _p(sm, 10, label: 'DANIEL', phone: '0733000003', cls: 'Family'),
      ]);
      expect(samePhone, hasLength(1));
      expect(samePhone.single.count, 2);
    });

    test('Paybill = same name + account; Buy Goods = same name (case and spaces ignored)', () {
      final pbs = _groups([
        _p(pb, 10, label: 'DSTV', account: '5566'),
        _p(pb, 10, label: 'dstv ', account: '5566'),
        _p(pb, 10, label: 'DSTV', account: '7788'),
      ]);
      expect(pbs, hasLength(2));
      final bgs = _groups([
        _p(bg, 10, label: 'NAIVAS  WESTLANDS'),
        _p(bg, 10, label: 'naivas westlands'),
        _p(bg, 10, label: 'QUICKMART'),
      ]);
      expect(bgs, hasLength(2));
    });

    test('Pochi = same phone; with no phone, the same name; a phone and a name-only payment are apart', () {
      final gs = _groups([
        _p(po, 10, label: 'MAMA FUA', phone: '+254744000009'),
        _p(po, 10, label: 'FUA LADY', phone: '0744000009'),
        _p(po, 10, label: 'Mama  Mboga'),
        _p(po, 10, label: 'MAMA MBOGA '),
        _p(po, 10, label: 'MAMA FUA'),
      ]);
      expect(gs, hasLength(3));
      expect(gs.singleWhere((g) => g.detail == '0744000009').count, 2);
      expect(gs.singleWhere((g) => g.partyKey == 'name|MAMA MBOGA').count, 2);
      expect(gs.singleWhere((g) => g.partyKey == 'name|MAMA FUA').count, 1);
    });

    test('Withdrawal = same agent number; with no number, the same agent name', () {
      final gs = _groups([
        _p(wd, 1000, agent: '123456', label: 'JOY AGENT'),
        _p(wd, 1000, agent: ' 123456 ', label: 'JOY SHOP'),
        _p(wd, 1000, agent: '654321', label: 'JOY AGENT'),
        _p(wd, 500, label: 'Kim Agent'),
        _p(wd, 500, label: 'KIM  AGENT'),
      ]);
      expect(gs, hasLength(3));
      expect(gs.singleWhere((g) => g.partyKey == 'no|123456').count, 2);
      expect(gs.singleWhere((g) => g.partyKey == 'name|KIM AGENT').count, 2);
    });

    test('the key of the old three is exactly what the recipient key was (one implementation)', () {
      expect(paidToRecipientKey(_p(sm, 1, phone: '+254722114455')), 'SEND_MONEY|0722114455');
      expect(paidToRecipientKey(_p(pb, 1, label: 'dstv', account: '55')), 'PAYBILL|DSTV#55');
      expect(paidToRecipientKey(_p(bg, 1, label: 'naivas')), 'BUY_GOODS|NAIVAS');
    });
  });

  group('detail text', () {
    test('local phone for Send Money, Acc, Pochi, Agent, Merchant; stored value never rewritten', () {
      final sendMoney = _groups([_p(sm, 1, phone: '+254722114455')]).single;
      expect(sendMoney.detail, '0722114455');
      expect(sendMoney.phones, {'+254722114455'});
      expect(_groups([_p(pb, 1, label: 'DSTV', account: '5566')]).single.detail, 'Acc 5566');
      expect(_groups([_p(po, 1, phone: '254744000009')]).single.detail, '0744000009');
      expect(_groups([_p(po, 1, label: 'MAMA')]).single.detail, 'Pochi');
      expect(_groups([_p(wd, 1, agent: '123456')]).single.detail, 'Agent 123456');
      expect(_groups([_p(wd, 1, label: 'JOY')]).single.detail, 'Agent number not recorded');
      expect(_groups([_p(bg, 1, label: 'NAIVAS')]).single.detail, 'Merchant');
    });
  });

  group('Not recorded replaces Unnamed', () {
    final pays = [
      _p(sm, 300, cls: 'Family', fee: 7),
      _p(sm, 200, cls: 'Family', fee: 7),
      _p(sm, 100, cls: 'Rent', fee: 5),
      _p(sm, 1500, label: 'ANN', phone: '0722114455', cls: 'Family', fee: 22),
      _p(pb, 900, label: 'DSTV', cls: 'Shopping', fee: 10), // no account
      _p(pb, 1200, label: 'DSTV', account: '5566', cls: 'Shopping', fee: 15),
      _p(bg, 850, label: 'NAIVAS', cls: 'Shopping', fee: 3),
      _p(bg, 60, cls: 'Shopping', fee: 1),
      _p(po, 400, cls: 'Family', fee: 2),
      _p(po, 450, label: 'MAMA MBOGA', cls: 'Family', fee: 3),
      _p(wd, 2000, cls: 'Cash', fee: 30),
      _p(wd, 3000, agent: '123456', cls: 'Cash', fee: 45),
    ];

    test('never grouped, in no count, no row', () {
      final gs = paidToGroups(pays);
      expect(gs.where((g) => g.isUnnamed), isEmpty);
      expect(gs, hasLength(5));
      final c = paidToCounts(pays);
      expect(c.by, {sm: 1, pb: 1, bg: 1, po: 1, wd: 1});
    });

    test('one summary per type, and per category when a category is chosen', () {
      final s = paidToNotRecorded(pays, type: sm);
      expect((s.count, s.totalCents, s.feeCents), (3, 60000, 1900));
      final fam = paidToNotRecorded(pays, type: sm, classification: 'Family');
      expect((fam.count, fam.totalCents, fam.feeCents), (2, 50000, 1400));
      final rent = paidToNotRecorded(pays, type: sm, classification: 'Rent');
      expect((rent.count, rent.totalCents), (1, 10000));
      expect(paidToNotRecorded(pays, type: bg, classification: 'Rent').count, 0);
      expect(paidToNotRecorded(pays, type: pb).count, 1);
      expect(paidToNotRecorded(pays, type: po).count, 1);
      expect(paidToNotRecorded(pays, type: wd).count, 1);
      expect(paidToNotRecorded(pays).count, 3 + 1 + 1 + 1 + 1);
    });

    test('hidden while a search is typed', () {
      expect(paidToNotRecorded(pays, type: sm, term: 'ann').count, 0);
      expect(paidToNotRecorded(pays, type: sm, term: ' ').count, 3);
    });

    test('money conservation: groups + Not recorded = all payments, amount and fee, per type', () {
      for (final t in paidToAllTypes) {
        final all = pays.where((p) => p.sourceType == t);
        final gs = paidToGroups(pays, type: t);
        final nr = paidToNotRecorded(pays, type: t);
        expect(gs.fold(0, (s, g) => s + g.totalCents) + nr.totalCents, all.fold(0, (s, p) => s + p.amountCents), reason: t);
        expect(gs.fold(0, (s, g) => s + g.feeCents) + nr.feeCents, all.fold(0, (s, p) => s + p.feeCents), reason: '$t fee');
        expect(gs.fold(0, (s, g) => s + g.count) + nr.count, all.length, reason: '$t count');
      }
    });
  });

  group('the ONE counting function', () {
    final pays = [
      _p(sm, 10, phone: '0722114455'),
      _p(sm, 10, phone: '+254722114455'),
      _p(sm, 10, phone: '0733000003', cls: 'Rent'),
      _p(pb, 10, label: 'DSTV', account: '1'),
      _p(bg, 10, label: 'NAIVAS', cls: 'Rent'),
      _p(po, 10, label: 'MAMA'),
      _p(wd, 10, agent: '111'),
      _p(wd, 10, agent: '222', cls: 'Rent'),
      _p(sm, 10), // not recorded
    ];

    test('by, rec, ag, all; agents are never added to recipients', () {
      final c = paidToCounts(pays);
      expect(c.by, {sm: 2, pb: 1, bg: 1, po: 1, wd: 2});
      expect(c.rec, 5);
      expect(c.ag, 2);
      expect(c.all, 7);
    });

    test('pills, section sizes and hero agree for the same inputs; a category narrows all of them', () {
      for (final cls in <String?>[null, 'Rent', 'Family']) {
        final c = paidToCounts(pays, classification: cls);
        var sectionSum = 0;
        for (final t in paidToAllTypes) {
          final section = paidToGroups(pays, type: t, classification: cls);
          expect(section.length, c.by[t], reason: '$t $cls');
          if (t != wd) sectionSum += section.length;
        }
        expect(sectionSum, c.rec, reason: 'rec $cls');
      }
      final hero = paidToHero(pays);
      expect(hero.recipients, paidToCounts(pays).rec);
      expect(hero.agents, paidToCounts(pays).ag);
      expect(paidToRecipientCount(pays, type: sm, classification: 'Rent'), 1);
    });

    test('a typed search is counted the same everywhere', () {
      final c = paidToCounts(pays, term: 'mama');
      expect(c.by[po], 1);
      expect(c.rec, 1);
      expect(c.all, 1);
      expect(paidToRecipientCount(pays, type: po, term: 'mama'), 1);
    });
  });

  group('wording', () {
    test('long label: recipients and agents named apart', () {
      PaidToCounts c(int rec, int ag, Map<String, int> by) => PaidToCounts(by, rec, ag, rec + ag);
      expect(paidToCountLabel(c(14, 3, {sm: 9, pb: 3, bg: 2, po: 0, wd: 3})), '14 recipients, 3 agents');
      expect(paidToCountLabel(c(1, 1, {sm: 1, pb: 0, bg: 0, po: 0, wd: 1})), '1 recipient, 1 agent');
      expect(paidToCountLabel(c(2, 0, {sm: 2, pb: 0, bg: 0, po: 0, wd: 0})), '2 recipients');
      expect(paidToCountLabel(c(14, 3, {sm: 9, pb: 3, bg: 2, po: 0, wd: 3}), tab: sm), '9 recipients');
      expect(paidToCountLabel(c(14, 3, {sm: 1, pb: 3, bg: 2, po: 0, wd: 3}), tab: sm), '1 recipient');
      expect(paidToCountLabel(c(14, 3, {sm: 9, pb: 3, bg: 2, po: 0, wd: 3}), tab: wd), '3 agents');
    });

    test('short label: "14 + 3 agents", the count alone in one view', () {
      expect(paidToShortLabel(14, 3), '14 + 3 agents');
      expect(paidToShortLabel(14, 1), '14 + 1 agent');
      expect(paidToShortLabel(14, 0), '14');
      expect(paidToShortLabel(9, 3, tab: sm), '9');
      expect(paidToShortLabel(9, 3, tab: wd), '3 agents');
    });

    test('nouns and payment words', () {
      expect([for (final t in paidToAllTypes) paidToNoun(t, 1)], ['person', 'bill', 'shop', 'business', 'agent']);
      expect([for (final t in paidToAllTypes) paidToNoun(t, 2)], ['people', 'bills', 'shops', 'businesses', 'agents']);
      expect(paidToPayWord(sm, 1), 'payment');
      expect(paidToPayWord(sm, 2), 'payments');
      expect(paidToPayWord(wd, 1), 'withdrawal');
      expect(paidToPayWord(wd, 2), 'withdrawals');
    });
  });

  group('search', () {
    final pays = [
      _p(sm, 100, label: 'ANN', phone: '+254722114455'),
      _p(sm, 100, label: 'ANNIE W', phone: '0722 114 455'),
      _p(sm, 100, label: 'BOB', phone: '0122114455'),
      _p(pb, 100, label: 'DSTV', account: '5566778'),
      _p(po, 100, label: 'MAMA MBOGA', phone: '0744000009'),
      _p(wd, 100, label: 'JOY AGENT', agent: '314159'),
      _p(sm, 100), // not recorded
    ];
    List<String> find(String term) => [for (final g in paidToGroups(pays, term: term)) g.partyKey!]..sort();

    test('by name (any of the names a merged recipient was written with)', () {
      expect(find('ann'), ['0722114455']);
      expect(find('annie'), ['0722114455']);
      expect(find('mboga'), ['tel|0744000009']);
    });

    test('by the phone in ANY written form finds the same recipient', () {
      for (final t in ['0722114455', '+254722114455', '254722114455', '722114455', '0722 114 455', '00254722114455']) {
        expect(find(t), ['0722114455'], reason: t);
      }
    });

    test('07 and 01 are not confused: the 01 number finds only Bob', () {
      expect(find('0122114455'), ['0122114455']);
      expect(find('+254122114455'), ['0122114455']);
    });

    test('by account number and by agent number', () {
      expect(find('5566778'), ['DSTV#5566778']);
      expect(find('314159'), ['no|314159']);
      expect(find('Agent 314'), ['no|314159']);
    });

    test('a merged group matches every label and every stored phone form it holds', () {
      final g = paidToGroups(pays).singleWhere((g) => g.detail == '0722114455');
      expect(g.labels, {'ann', 'annie w'});
      expect(g.phones, {'+254722114455', '0722 114 455'});
      expect(g.matches('ANNIE'), isTrue);
      expect(g.matches('+254 722 114 455'), isTrue);
      expect(g.matches('0733'), isFalse);
      expect(g.matches(''), isTrue);
    });

    test('no match gives nothing and the Not recorded payment is never found', () {
      expect(find('zzz'), isEmpty);
      expect(paidToNotRecorded(pays, term: 'ann').count, 0);
    });
  });

  group('sorts', () {
    List<String> order(PaidToSort s, List<PaidToPayment> ps) {
      final gs = paidToGroups(ps);
      sortPaidTo(gs, s);
      return [for (final g in gs) g.name];
    }

    test('Transaction cost: fee, then total, then name', () {
      final ps = [
        _p(bg, 500, label: 'B SHOP', fee: 10),
        _p(bg, 900, label: 'A SHOP', fee: 10),
        _p(bg, 900, label: 'C SHOP', fee: 10),
        _p(bg, 100, label: 'D SHOP', fee: 40),
        _p(bg, 100, label: 'E SHOP', fee: 0),
      ];
      expect(order(PaidToSort.fees, ps), ['D SHOP', 'A SHOP', 'C SHOP', 'B SHOP', 'E SHOP']);
      expect(paidToSortLabels[PaidToSort.fees], 'Transaction cost');
    });

    test('Amount, Times paid, Most recent keep their order and tie-breaks', () {
      final ps = [
        _p(bg, 100, label: 'B SHOP', day: 3),
        _p(bg, 100, label: 'A SHOP', day: 3),
        _p(bg, 50, label: 'C SHOP', day: 20),
        _p(bg, 50, label: 'C SHOP', day: 21),
      ];
      expect(order(PaidToSort.amount, ps), ['C SHOP', 'A SHOP', 'B SHOP']); // 100 total, 2 payments, then 100 ties by name
      expect(order(PaidToSort.timesPaid, ps), ['C SHOP', 'A SHOP', 'B SHOP']);
      expect(order(PaidToSort.recent, ps), ['C SHOP', 'A SHOP', 'B SHOP']);
      expect(paidToSortsShown, [PaidToSort.amount, PaidToSort.timesPaid, PaidToSort.recent]);
    });
  });

  group('hero numbers', () {
    final pays = [
      _p(sm, 1000, phone: '0722114455', fee: 20),
      _p(sm, 500, fee: 10), // not recorded
      _p(pb, 700, label: 'DSTV', account: '1', fee: 5),
      _p(po, 300, label: 'MAMA', fee: 4),
      _p(wd, 2000, agent: '111', fee: 30),
      _p(wd, 4000, fee: 60), // not recorded withdrawal
    ];

    test('Paid out never includes withdrawn money; cost covers the same payments; Not recorded is in the totals', () {
      final h = paidToHero(pays);
      expect(h.withdrawn, isFalse);
      expect(h.totalCents, (1000 + 500 + 700 + 300) * 100);
      expect(h.costCents, (20 + 10 + 5 + 4) * 100);
      expect(h.payments, 4);
      expect(h.recipients, 3); // the Not recorded payment is not a recipient
      expect(h.agents, 1);
      expect(h.withdrawalCostCents, (30 + 60) * 100);
    });

    test('the W view reads Withdrawn: only withdrawals, agents counted, no separate withdrawal cost', () {
      final h = paidToHero(pays, withdrawn: true);
      expect(h.withdrawn, isTrue);
      expect(h.totalCents, 6000 * 100);
      expect(h.costCents, 90 * 100);
      expect(h.payments, 2);
      expect(h.recipients, 1);
      expect(h.withdrawalCostCents, 0);
    });

    test('without withdrawals or Not recorded payments', () {
      final only = pays.where((p) => p.sourceType == pb || p.sourceType == po).toList();
      final h = paidToHero(only);
      expect(h.totalCents, 1000 * 100);
      expect(h.costCents, 9 * 100);
      expect(h.payments, 2);
      expect(h.recipients, 2);
      expect(h.agents, 0);
      expect(h.withdrawalCostCents, 0);
    });

    test('an empty period is all zero', () {
      final h = paidToHero(const []);
      expect((h.totalCents, h.costCents, h.payments, h.recipients, h.agents, h.withdrawalCostCents), (0, 0, 0, 0, 0, 0));
    });
  });
}
