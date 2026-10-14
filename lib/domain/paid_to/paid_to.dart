/// T22 — "Paid to" (formerly Parties, T15): who the money went to.
///
/// Pure grouping / sorting over one period's M-Pesa payments (prototype v12's
/// `PT_API`), kept out of the screen so it can be unit tested. Cash is never a
/// recipient and never reaches this code.
///
/// 0.1.2 S7a (PT1): Pochi and Withdrawal join the domain; "Not recorded"
/// replaces "Unnamed" (counts, the Not recorded summary, the hero and the
/// wording helpers are in `paid_to_counts.dart`): a payment with no captured
/// receiver is never a recipient, only a per-type summary whose money stays in
/// the totals. The old unnamed-row path (`groupPaidTo` with the default
/// `includeUnrecorded: true`) stays only for the screen until S7b.
library;

import '../analytics/analytics_period.dart';
import '../counterparty/counterparty_key.dart';
import '../parsing/parsed_sms_fields.dart';

/// The recipient types the SCREEN loads (S7a: still the three; S7b widens it).
const paidToTypes = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS'];

/// DB strings (`SmsSourceTypeDb`) of the two types added in 0.1.2.
const paidToPochi = 'POCHI_LA_BIASHARA';
const paidToWithdrawal = 'AGENT_WITHDRAWAL';

/// All five types the domain knows, in section / pill order (mock `CODES`).
const paidToAllTypes = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', paidToPochi, paidToWithdrawal];

enum PaidToSort { amount, timesPaid, recent, fees }

const paidToSortLabels = {
  PaidToSort.amount: 'Amount',
  PaidToSort.timesPaid: 'Times paid',
  PaidToSort.recent: 'Most recent',
  PaidToSort.fees: 'Transaction cost',
};

/// The sorts the Filter sheet draws in S7a (no look change); S7b adds [PaidToSort.fees].
const paidToSortsShown = [PaidToSort.amount, PaidToSort.timesPaid, PaidToSort.recent];

/// One payment, as Paid to needs it.
class PaidToPayment {
  const PaidToPayment({
    required this.sourceType,
    required this.amountCents,
    required this.feeCents,
    required this.occurredAt,
    required this.classificationName,
    this.label,
    this.phone,
    this.account,
    this.agentNumber,
  });

  /// A DB source type: one of [paidToAllTypes].
  final String sourceType;
  final int amountCents;
  final int feeCents;
  final DateTime occurredAt;
  final String classificationName;
  final String? label;
  final String? phone;
  final String? account;

  /// Withdrawal only (`transactions.agent_number`).
  final String? agentNumber;
}

bool _filled(String? s) => s != null && s.trim().isNotEmpty;

/// Whether the receiver was captured, per type: Send Money a phone, Paybill a
/// name and an account, Buy Goods a name, Pochi a phone or a name, Withdrawal
/// an agent number or a name.
bool hasCapturedIdentity(String sourceType, String? label, String? phone, String? account, {String? agentNumber}) {
  return switch (sourceType) {
    'SEND_MONEY' => _filled(phone),
    'PAYBILL' => _filled(label) && _filled(account),
    'BUY_GOODS' => _filled(label),
    paidToPochi => _filled(phone) || _filled(label),
    paidToWithdrawal => _filled(agentNumber) || _filled(label),
    _ => false,
  };
}

// The ONE key rules are `deriveCounterpartyKey` (phone and label); Paid to only
// reaches them through it (the phone-key static guard allows no other caller).
String _phoneKey(String? phone) => deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);
String _labelKey(String? label) => deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: label);

/// The grouping key of one payment's recipient. Send Money, Paybill, Buy Goods:
/// `deriveCounterpartyKey`. Pochi: the phone key (`tel|`), else the name
/// (`name|`). Withdrawal: the agent number (`no|`), else the name (`name|`).
/// Not captured: `anon|type|classification` (the S7a functions never show it
/// as a recipient).
String paidToRecipientKey(PaidToPayment p) {
  if (!hasCapturedIdentity(p.sourceType, p.label, p.phone, p.account, agentNumber: p.agentNumber)) {
    return 'anon|${p.sourceType}|${p.classificationName}';
  }
  final inner = switch (p.sourceType) {
    paidToPochi => _filled(p.phone) ? 'tel|${_phoneKey(p.phone)}' : 'name|${_labelKey(p.label)}',
    paidToWithdrawal => _filled(p.agentNumber) ? 'no|${p.agentNumber!.trim()}' : 'name|${_labelKey(p.label)}',
    'SEND_MONEY' => _phoneKey(p.phone),
    'PAYBILL' => deriveCounterpartyKey(
      sourceType: SmsSourceType.payBill,
      counterpartyLabel: p.label,
      paybillAccountNumber: p.account,
    ),
    _ => _labelKey(p.label),
  };
  return '${p.sourceType}|$inner';
}

/// One row on Paid to: a named recipient (or, on the old path, an unnamed
/// classification group).
class PaidToRecipient {
  PaidToRecipient._({
    required this.key,
    required this.sourceType,
    required this.isUnnamed,
    required this.classificationName,
    required this.partyKey,
    required this.label,
    required this.detail,
    required this.lastAt,
  });

  final String key;
  final String sourceType;

  /// No receiver captured (old T15 path only): grouped by [classificationName].
  final bool isUnnamed;

  /// The unnamed group's classification (for a named recipient: the first
  /// payment's, unused).
  final String classificationName;

  /// The key after the type (named only). Send Money, Paybill, Buy Goods: what
  /// Analytics' party view takes. Pochi (`tel|...` / `name|...`) and Withdrawal
  /// (`no|...` / `name|...`): not yet understood by the party filter (S7b).
  final String? partyKey;

  /// The receiver's name as captured (named only).
  final String? label;

  /// The LOCAL phone (Send Money), "Acc (number)" (Paybill), "Merchant" (Buy
  /// Goods), the local phone or "Pochi", "Agent (number)" or "Agent number not
  /// recorded"; "Receiver not recorded" when unnamed.
  final String detail;

  /// Every name written for this recipient (lower case) and every phone form as
  /// stored (more than one phone form = a merge); both feed search.
  final Set<String> labels = {};
  final Set<String> phones = {};

  int totalCents = 0;
  int count = 0;
  int feeCents = 0;
  DateTime lastAt;

  /// The row's title (mock: "Unnamed · (classification)" on the old path).
  String get name => isUnnamed ? 'Unnamed · $classificationName' : (label?.trim().isNotEmpty ?? false) ? label! : detail;

  /// What search matches on: name, detail (local phone, account, agent number),
  /// every name written and every phone form as stored.
  String get searchText => '$name $detail ${labels.join(' ')} ${phones.join(' ')}'.toLowerCase();

  /// Search: [searchText] contains the typed term, or (a phone written in any
  /// form) contains the term's phone key. An empty term matches everything.
  bool matches(String term) {
    final t = term.trim();
    if (t.isEmpty) return true;
    final text = searchText;
    if (text.contains(t.toLowerCase())) return true;
    final key = _phoneKey(t);
    return key != t && key.isNotEmpty && text.contains(key.toLowerCase());
  }
}

String _detailOf(PaidToPayment p) => switch (p.sourceType) {
  'SEND_MONEY' => _phoneKey(p.phone),
  'PAYBILL' => 'Acc ${p.account ?? ''}',
  paidToPochi => _filled(p.phone) ? _phoneKey(p.phone) : 'Pochi',
  paidToWithdrawal => _filled(p.agentNumber) ? 'Agent ${p.agentNumber!.trim()}' : 'Agent number not recorded',
  _ => 'Merchant',
};

/// Groups [payments] into recipients, optionally only those in
/// [classification]. Unsorted (see [sortPaidTo]). [includeUnrecorded] true (the
/// 0.1.0 T15 path, kept for the screen until S7b) also makes one "Unnamed" row
/// per type + classification; false (0.1.2) leaves payments with no captured
/// receiver out: they are not recipients (see `paidToNotRecorded`).
List<PaidToRecipient> groupPaidTo(
  Iterable<PaidToPayment> payments, {
  String? classification,
  bool includeUnrecorded = true,
}) {
  final map = <String, PaidToRecipient>{};
  for (final p in payments) {
    if (classification != null && p.classificationName != classification) continue;
    final key = paidToRecipientKey(p);
    final named = !key.startsWith('anon|');
    if (!named && !includeUnrecorded) continue;
    final g = map.putIfAbsent(
      key,
      () => PaidToRecipient._(
        key: key,
        sourceType: p.sourceType,
        isUnnamed: !named,
        classificationName: p.classificationName,
        partyKey: named ? key.substring(p.sourceType.length + 1) : null,
        label: named ? p.label : null,
        detail: named ? _detailOf(p) : 'Receiver not recorded',
        lastAt: p.occurredAt,
      ),
    );
    g.totalCents += p.amountCents;
    g.count += 1;
    g.feeCents += p.feeCents;
    if (_filled(p.label)) g.labels.add(p.label!.trim().toLowerCase());
    if (_filled(p.phone)) g.phones.add(p.phone!.trim());
    if (p.occurredAt.isAfter(g.lastAt)) g.lastAt = p.occurredAt;
  }
  return map.values.toList();
}

/// Sorts in place (mock `SORTF`): Amount = total, then times paid; Times paid =
/// count, then total; Transaction cost = fee, then total; Most recent = last
/// payment. Ties by name.
void sortPaidTo(List<PaidToRecipient> list, PaidToSort sort) {
  int byName(PaidToRecipient a, PaidToRecipient b) => a.name.compareTo(b.name);
  list.sort(
    (a, b) => switch (sort) {
      PaidToSort.amount => _chain([b.totalCents.compareTo(a.totalCents), b.count.compareTo(a.count), byName(a, b)]),
      PaidToSort.timesPaid => _chain([b.count.compareTo(a.count), b.totalCents.compareTo(a.totalCents), byName(a, b)]),
      PaidToSort.fees => _chain([b.feeCents.compareTo(a.feeCents), b.totalCents.compareTo(a.totalCents), byName(a, b)]),
      PaidToSort.recent => _chain([b.lastAt.compareTo(a.lastAt), byName(a, b)]),
    },
  );
}

int _chain(List<int> cmps) => cmps.firstWhere((c) => c != 0, orElse: () => 0);

/// Distinct recipients among [payments], optionally of one [type] and one
/// [classification]. The 0.1.0 count (an unnamed group counts as one); kept for
/// the screen until S7b, which calls `paidToCounts` instead.
int countPaidToRecipients(Iterable<PaidToPayment> payments, {String? type, String? classification}) => {
  for (final p in payments)
    if ((type == null || p.sourceType == type) && (classification == null || p.classificationName == classification))
      paidToRecipientKey(p),
}.length;

/// The Filter sheet's categories for [type] (`null` = all types): each
/// classification with its payment count, most payments first (ties by
/// name).
List<(String name, int count)> paidToCategories(Iterable<PaidToPayment> payments, {String? type}) {
  final counts = <String, int>{};
  for (final p in payments) {
    if (type != null && p.sourceType != type) continue;
    counts[p.classificationName] = (counts[p.classificationName] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (e.key, e.value)];
  out.sort((a, b) => _chain([b.$2.compareTo(a.$2), a.$1.compareTo(b.$1)]));
  return out;
}

/// One type's section summary (header + subline).
class PaidToSection {
  PaidToSection(this.type, this.recipients);

  final String type;

  /// Already filtered and sorted.
  final List<PaidToRecipient> recipients;

  int get totalCents => recipients.fold(0, (s, r) => s + r.totalCents);
  int get payments => recipients.fold(0, (s, r) => s + r.count);
  int get feeCents => recipients.fold(0, (s, r) => s + r.feeCents);
}

/// "person/people", "bill/bills", "shop/shops", "business/businesses" (Pochi),
/// "agent/agents" (mock `noun`).
String paidToNoun(String type, int n) => switch (type) {
  'SEND_MONEY' => n == 1 ? 'person' : 'people',
  'PAYBILL' => n == 1 ? 'bill' : 'bills',
  paidToPochi => n == 1 ? 'business' : 'businesses',
  paidToWithdrawal => n == 1 ? 'agent' : 'agents',
  _ => n == 1 ? 'shop' : 'shops',
};

/// "payment(s)", or "withdrawal(s)" for Withdrawal (mock `payWord`).
String paidToPayWord(String type, int n) =>
    type == paidToWithdrawal ? (n == 1 ? 'withdrawal' : 'withdrawals') : (n == 1 ? 'payment' : 'payments');

/// Paid to's periods: All time / Year / Month (mock `GRANS`).
const paidToGranularities = [
  (AnalyticsGranularity.all, 'All time'),
  (AnalyticsGranularity.year, 'Year'),
  (AnalyticsGranularity.month, 'Month'),
];

/// [g] as of [today] (the pill's left half, and pull-to-refresh "back to
/// now": the same length, the current one).
AnalyticsPeriod paidToPeriodNow(AnalyticsGranularity g, DateTime today) => switch (g) {
  AnalyticsGranularity.all => AnalyticsPeriod.allTime(today),
  AnalyticsGranularity.year => AnalyticsPeriod.year(today.year, today: today),
  _ => AnalyticsPeriod.month(today),
};

/// The Analytics period a Paid to tap opens on: the same length and anchor
/// (a month is placed on Analytics' 6-month chart window).
AnalyticsPeriod analyticsPeriodForPaidTo(AnalyticsPeriod p, DateTime today) => switch (p.granularity) {
  AnalyticsGranularity.month => AnalyticsPeriod.monthShown(p.anchor, today: today),
  AnalyticsGranularity.year => AnalyticsPeriod.year(p.anchor.year, today: today),
  _ => AnalyticsPeriod.allTime(today),
};
