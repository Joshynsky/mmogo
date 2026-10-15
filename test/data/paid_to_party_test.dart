// S7b (PT1) — the Analytics recipient view for Pochi and Withdrawal
// (AnalyticsDao._matchesParty): the party key Paid to hands over must select
// exactly the rows of the Paid to row, for all five types. Plain test (the
// DAO filters the party in Dart after the query), against FakeAnalyticsDb.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/paid_to/paid_to.dart';

import '../support/fake_analytics_db.dart';

const _pochi = 'POCHI_LA_BIASHARA';
const _wd = 'AGENT_WITHDRAWAL';

Map<String, Object?> _tx(
  int id,
  String type, {
  String? label,
  String? phone,
  String? agent,
  String? account,
  int cents = 10000,
}) {
  final r = fakeTx(
    id: id,
    at: DateTime(2026, 9, 1 + id),
    type: type,
    label: label,
    phone: phone,
    account: account,
    agentNumber: agent,
    amountCents: cents,
  );
  r['counterparty_label'] = label; // fakeTx invents a name when none is given
  r['counterparty_phone'] = phone;
  return r;
}

void main() {
  final rows = [
    // Pochi: one business written with two phone forms, one by name only, one other business, one not recorded.
    _tx(1, _pochi, label: 'MAMA MBOGA', phone: '0744000009'),
    _tx(2, _pochi, label: 'MAMA MBOGA', phone: '254744000009'),
    _tx(3, _pochi, label: 'JUICE BAR'),
    _tx(4, _pochi, label: 'JUICE  BAR'), // irregular spacing, same name
    _tx(5, _pochi, label: 'OTHER', phone: '0755000001'),
    _tx(6, _pochi),
    // Withdrawal: an agent by number (two names written), one by name only, one not recorded.
    _tx(7, _wd, label: 'JOY AGENT', agent: '314159'),
    _tx(8, _wd, label: 'JOY AGENT SHOP', agent: '314159'),
    _tx(9, _wd, label: 'KAMAU AGENT'),
    _tx(10, _wd),
    // Same name / number text under another type must never match.
    _tx(11, 'SEND_MONEY', label: 'JOY AGENT', phone: '0744000009'),
    _tx(12, 'BUY_GOODS', label: 'JUICE BAR'),
  ];

  Future<List<AnalyticsTransactionRow>> all(FakeAnalyticsDb db) =>
      AnalyticsDao.itemizedTransactions(db, startMs: null, endMs: null, types: AnalyticsDao.allTypes);

  test('for every Pochi and Withdrawal recipient the Analytics party view holds exactly the Paid to row', () async {
    final db = FakeAnalyticsDb(rows);
    final pays = [
      for (final r in await all(db))
        PaidToPayment(
          sourceType: r.sourceType,
          amountCents: r.amountCents,
          feeCents: r.transactionCostCents ?? 0,
          occurredAt: r.occurredAt,
          classificationName: r.classificationName,
          label: r.counterpartyLabel,
          phone: r.counterpartyPhone,
          account: r.paybillAccountNumber,
          agentNumber: r.agentNumber,
        ),
    ];
    final groups = groupPaidTo(pays.where((p) => p.sourceType == _pochi || p.sourceType == _wd));
    expect(groups, hasLength(5)); // MAMA (tel), JUICE BAR (name), OTHER (tel), JOY (no), KAMAU (name)
    final counts = {for (final g in groups) g.partyKey: g.count};
    expect(counts, {
      'tel|0744000009': 2,
      'name|JUICE BAR': 2,
      'tel|0755000001': 1,
      'no|314159': 2,
      'name|KAMAU AGENT': 1,
    });

    for (final g in groups) {
      final view = await AnalyticsDao.itemizedTransactions(
        db,
        startMs: null,
        endMs: null,
        types: AnalyticsDao.allTypes,
        partyType: g.sourceType,
        partyKey: g.partyKey,
      );
      expect(view, hasLength(g.count), reason: '${g.sourceType} ${g.partyKey}');
      expect(view.fold<int>(0, (s, r) => s + r.amountCents), g.totalCents);
      expect(view.every((r) => r.sourceType == g.sourceType), isTrue);
    }
  });

  test('a recipient with no captured identity, or another type\'s key, matches nothing', () async {
    final db = FakeAnalyticsDb(rows);
    Future<int> count(String type, String key) async => (await AnalyticsDao.itemizedTransactions(
      db,
      startMs: null,
      endMs: null,
      types: AnalyticsDao.allTypes,
      partyType: type,
      partyKey: key,
    )).length;
    expect(await count(_wd, 'tel|0744000009'), 0, reason: 'a Pochi key under Withdrawal');
    expect(await count(_pochi, 'no|314159'), 0, reason: 'a Withdrawal key under Pochi');
    expect(await count(_pochi, 'name|'), 0, reason: 'the not-recorded rows are no recipient');
    expect(await count('AIRTIME', 'name|X'), 0);
  });
}
