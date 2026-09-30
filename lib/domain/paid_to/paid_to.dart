/// T22 — "Paid to" (formerly Parties, T15): who the money went to.
///
/// Pure grouping / counting / sorting over one period's M-Pesa payments
/// (prototype v12's `PT_API`), kept out of the screen so it can be unit
/// tested. Cash is never a recipient and never reaches this code (the screen
/// only loads Send Money / Paybill / Buy Goods).
///
/// The T15 rule is kept: a payment whose receiver was never captured is
/// never dropped; it is grouped by its classification (one "Unnamed" row
/// per type + classification) and rendered distinctly.
library;

import '../analytics/analytics_period.dart';
import '../counterparty/counterparty_key.dart';
import '../parsing/parsed_sms_fields.dart';

/// The recipient types, in section / pill order.
const paidToTypes = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS'];

enum PaidToSort { amount, timesPaid, recent }

const paidToSortLabels = {
  PaidToSort.amount: 'Amount',
  PaidToSort.timesPaid: 'Times paid',
  PaidToSort.recent: 'Most recent',
};

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
  });

  final String sourceType; // 'SEND_MONEY' | 'PAYBILL' | 'BUY_GOODS'
  final int amountCents;
  final int feeCents;
  final DateTime occurredAt;
  final String classificationName;
  final String? label;
  final String? phone;
  final String? account;
}

/// Whether the receiver was captured — T15's per-type rule: Send Money needs a phone, Paybill a name and
/// an account, Buy Goods a name.
bool hasCapturedIdentity(String sourceType, String? label, String? phone, String? account) {
  bool filled(String? s) => s != null && s.trim().isNotEmpty;
  return switch (sourceType) {
    'SEND_MONEY' => filled(phone),
    'PAYBILL' => filled(label) && filled(account),
    'BUY_GOODS' => filled(label),
    _ => false,
  };
}

SmsSourceType _sms(String type) => switch (type) {
  'SEND_MONEY' => SmsSourceType.sendMoney,
  'PAYBILL' => SmsSourceType.payBill,
  _ => SmsSourceType.buyGoods,
};

/// The grouping key of one payment's recipient: the authoritative
/// `deriveCounterpartyKey` for a named receiver, else the type +
/// classification (the unnamed group).
String paidToRecipientKey(PaidToPayment p) {
  if (!hasCapturedIdentity(p.sourceType, p.label, p.phone, p.account)) {
    return 'anon|${p.sourceType}|${p.classificationName}';
  }
  return '${p.sourceType}|${deriveCounterpartyKey(
    sourceType: _sms(p.sourceType),
    counterpartyLabel: p.label,
    counterpartyPhone: p.phone,
    paybillAccountNumber: p.account,
  )}';
}

/// One row on Paid to: a named recipient or an unnamed classification group.
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

  /// No receiver captured (T15): grouped by [classificationName].
  final bool isUnnamed;

  /// The unnamed group's classification (for a named recipient: the first
  /// payment's, unused).
  final String classificationName;

  /// `deriveCounterpartyKey` (named only) — what Analytics' party view takes.
  final String? partyKey;

  /// The receiver's name as captured (named only).
  final String? label;

  /// Phone (Send Money), "Acc (number)" (Paybill) or "Merchant" (Buy Goods);
  /// "Receiver not recorded" when unnamed.
  final String detail;

  int totalCents = 0;
  int count = 0;
  int feeCents = 0;
  DateTime lastAt;

  /// The row's title (mock: "Unnamed · (classification)").
  String get name => isUnnamed ? 'Unnamed · $classificationName' : (label?.trim().isNotEmpty ?? false) ? label! : detail;

  /// What search matches on: name + detail.
  String get searchText => '$name $detail'.toLowerCase();
}

String _detailOf(PaidToPayment p) => switch (p.sourceType) {
  'SEND_MONEY' => p.phone ?? '',
  'PAYBILL' => 'Acc ${p.account ?? ''}',
  _ => 'Merchant',
};

/// Groups [payments] into recipients, optionally only those in
/// [classification]. Unsorted (see [sortPaidTo]).
List<PaidToRecipient> groupPaidTo(Iterable<PaidToPayment> payments, {String? classification}) {
  final map = <String, PaidToRecipient>{};
  for (final p in payments) {
    if (classification != null && p.classificationName != classification) continue;
    final key = paidToRecipientKey(p);
    final named = !key.startsWith('anon|');
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
    if (p.occurredAt.isAfter(g.lastAt)) g.lastAt = p.occurredAt;
  }
  return map.values.toList();
}

/// Sorts in place (mock `SORTF`): Amount = total, then times paid; Times
/// paid = count, then total; Most recent = last payment. Ties by name.
void sortPaidTo(List<PaidToRecipient> list, PaidToSort sort) {
  int byName(PaidToRecipient a, PaidToRecipient b) => a.name.compareTo(b.name);
  list.sort(
    (a, b) => switch (sort) {
      PaidToSort.amount => _chain([b.totalCents.compareTo(a.totalCents), b.count.compareTo(a.count), byName(a, b)]),
      PaidToSort.timesPaid => _chain([b.count.compareTo(a.count), b.totalCents.compareTo(a.totalCents), byName(a, b)]),
      PaidToSort.recent => _chain([b.lastAt.compareTo(a.lastAt), byName(a, b)]),
    },
  );
}

int _chain(List<int> cmps) => cmps.firstWhere((c) => c != 0, orElse: () => 0);

/// Distinct recipients among [payments], optionally of one [type] and one
/// [classification] (the hero, the type pills, the sheet's "Show N").
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

/// "person/people", "bill/bills", "shop/shops" (mock `SECT`).
String paidToNoun(String type, int n) => switch (type) {
  'SEND_MONEY' => n == 1 ? 'person' : 'people',
  'PAYBILL' => n == 1 ? 'bill' : 'bills',
  _ => n == 1 ? 'shop' : 'shops',
};

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
