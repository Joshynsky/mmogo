/// §DOMAIN.PAID_TO.COUNTS — Paid to's counting, Not recorded summary, wording
/// and hero numbers (0.1.2 S7a, PT1; the signed mock `paidto.html`:
/// `unrecOf`, `groupsOf`, `recCount`, `counts`, `countLabel`, `shortLabel`,
/// `heroInfo`).
///
/// ONE counting function: the type pills, the section headers, the Filter
/// sheet's "Show N" and the hero all call [paidToCounts] / [paidToGroups], so the
/// same type + category + search gives the same number everywhere. Recipients
/// and agents (Withdrawal) are named apart and never added.
///
/// A payment with no captured receiver is NOT a recipient (reverses 0.1.0 T15,
/// PM 08-10-2026): never grouped, in no recipient count, no recipient sheet.
/// [paidToNotRecorded] is its one summary; its money and cost STAY in the hero
/// totals.
library;

import 'paid_to.dart';

/// The payments of [type] (`null` = every type the domain knows).
Iterable<PaidToPayment> _ofType(Iterable<PaidToPayment> payments, String? type) =>
    payments.where((p) => type == null ? paidToAllTypes.contains(p.sourceType) : p.sourceType == type);

bool _recorded(PaidToPayment p) =>
    hasCapturedIdentity(p.sourceType, p.label, p.phone, p.account, agentNumber: p.agentNumber);

/// The recipients as the list draws them: named only, narrowed by [type]
/// (`null` = all), [classification] and the typed search [term]. Unsorted.
List<PaidToRecipient> paidToGroups(
  Iterable<PaidToPayment> payments, {
  String? type,
  String? classification,
  String term = '',
}) => [
  for (final g in groupPaidTo(_ofType(payments, type), classification: classification))
    if (g.matches(term)) g,
];

/// The payments with no captured receiver: one count, one total, one fee.
class PaidToNotRecorded {
  const PaidToNotRecorded(this.count, this.totalCents, this.feeCents);

  final int count;
  final int totalCents;
  final int feeCents;
}

/// The Not recorded summary for [type] (`null` = all types) and, when chosen,
/// [classification]. Empty while a search [term] is typed (it has no name,
/// phone or account to find).
PaidToNotRecorded paidToNotRecorded(
  Iterable<PaidToPayment> payments, {
  String? type,
  String? classification,
  String term = '',
}) {
  if (term.trim().isNotEmpty) return const PaidToNotRecorded(0, 0, 0);
  var n = 0, total = 0, fee = 0;
  for (final p in _ofType(payments, type)) {
    if (_recorded(p)) continue;
    if (classification != null && p.classificationName != classification) continue;
    n += 1;
    total += p.amountCents;
    fee += p.feeCents;
  }
  return PaidToNotRecorded(n, total, fee);
}

/// Mock `counts`: `by[type]` for every type, `rec` (every type except
/// Withdrawal), `ag` (Withdrawal) and `all` (every group, agents included).
class PaidToCounts {
  const PaidToCounts(this.by, this.rec, this.ag, this.all);

  final Map<String, int> by;
  final int rec;
  final int ag;
  final int all;
}

/// The number of recipients (agents for Withdrawal) for [type] (`null` = all).
int paidToRecipientCount(
  Iterable<PaidToPayment> payments, {
  String? type,
  String? classification,
  String term = '',
}) => paidToGroups(payments, type: type, classification: classification, term: term).length;

/// ONE counting function (mock `counts`).
PaidToCounts paidToCounts(Iterable<PaidToPayment> payments, {String? classification, String term = ''}) {
  final list = payments.toList();
  final by = {
    for (final t in paidToAllTypes) t: paidToRecipientCount(list, type: t, classification: classification, term: term),
  };
  final rec = paidToAllTypes.fold<int>(0, (s, t) => t == paidToWithdrawal ? s : s + by[t]!);
  return PaidToCounts(by, rec, by[paidToWithdrawal]!, paidToRecipientCount(list, classification: classification, term: term));
}

String _plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// Mock `countLabel`: Withdrawal "N agents"; a payment type "N recipients"; the
/// All view "N recipients, M agents" (agents only when there are some).
String paidToCountLabel(PaidToCounts c, {String? tab}) {
  if (tab == paidToWithdrawal) return _plural(c.ag, 'agent', 'agents');
  if (tab != null) return _plural(c.by[tab] ?? 0, 'recipient', 'recipients');
  return c.ag > 0
      ? '${_plural(c.rec, 'recipient', 'recipients')}, ${_plural(c.ag, 'agent', 'agents')}'
      : _plural(c.rec, 'recipient', 'recipients');
}

/// Mock `shortLabel`: "14 + 3 agents" in the All view, just the count in a
/// single-type view; Withdrawal "N agents". The All PILL shows only [PaidToCounts.rec].
String paidToShortLabel(int rec, int ag, {String? tab}) {
  if (tab == paidToWithdrawal) return _plural(ag, 'agent', 'agents');
  if (tab != null) return '$rec';
  return ag > 0 ? '$rec + ${_plural(ag, 'agent', 'agents')}' : '$rec';
}

/// The hero card's numbers (mock `heroInfo`, whole-period behaviour; the
/// "hero follows filters" switch is panel-only and not in the app).
class PaidToHero {
  const PaidToHero({
    required this.agentView,
    required this.totalCents,
    required this.costCents,
    required this.payments,
    required this.recipients,
    required this.agents,
    required this.withdrawalCostCents,
  });

  /// The W view: the card reads "Withdrawn", the amount is withdrawn money. (Named
  /// `agentView`, not `withdrawn`, so the static withdrawn-figure guard keeps meaning the cash figure.)
  final bool agentView;

  /// "Paid out" (or "Withdrawn"): never includes withdrawn money outside the W
  /// view; includes the Not recorded payments' money.
  final int totalCents;

  /// The Transaction cost line: exactly the same payments as [totalCents].
  final int costCents;
  final int payments;

  /// "to N recipients" (agents in the W view): Not recorded payments are not in it.
  final int recipients;

  /// "+ M agents (cash out, not counted)": the number of agents (0 line hidden).
  final int agents;

  /// "Transaction cost of withdrawals": separate, 0 in the W view.
  final int withdrawalCostCents;
}

/// Hero numbers over [payments] (one period's, no category, no search).
/// [withdrawn] = the W view.
PaidToHero paidToHero(Iterable<PaidToPayment> payments, {bool withdrawn = false}) {
  final list = payments.toList();
  final type = withdrawn ? paidToWithdrawal : null;
  bool inScope(String t) => withdrawn ? t == paidToWithdrawal : t != paidToWithdrawal;
  final groups = [for (final g in paidToGroups(list, type: type)) if (inScope(g.sourceType)) g];
  final notRecorded = [
    for (final t in paidToAllTypes)
      if (inScope(t)) paidToNotRecorded(list, type: t),
  ];
  final wGroups = withdrawn ? <PaidToRecipient>[] : paidToGroups(list, type: paidToWithdrawal);
  final wNotRecorded = withdrawn ? 0 : paidToNotRecorded(list, type: paidToWithdrawal).feeCents;
  return PaidToHero(
    agentView: withdrawn,
    totalCents: groups.fold(0, (s, g) => s + g.totalCents) + notRecorded.fold(0, (s, n) => s + n.totalCents),
    costCents: groups.fold(0, (s, g) => s + g.feeCents) + notRecorded.fold(0, (s, n) => s + n.feeCents),
    payments: groups.fold(0, (s, g) => s + g.count) + notRecorded.fold(0, (s, n) => s + n.count),
    recipients: groups.length,
    agents: paidToCounts(list).ag,
    withdrawalCostCents: wGroups.fold(0, (s, g) => s + g.feeCents) + wNotRecorded,
  );
}
