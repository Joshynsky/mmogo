/// §DOMAIN.PAID_TO.ACCOUNT_VIEW — 0.2.1 #4 (MK-12): the small rules behind choosing ONE account in
/// the recipient sheet of a Paybill name with several accounts: the key Analytics' party view takes
/// for it, and the words naming a swipeable chart window. Pure.
library;

import 'paid_to.dart';
import 'paid_to_sheet.dart';

const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The party key (after the type) of account [account] under [r], or null when no payment of it
/// carries a captured name and account (then there is nothing to hand to Analytics).
String? paidToAccountPartyKey(PaidToRecipient r, String account) {
  for (final p in r.payments) {
    if ((p.account ?? '').trim() != account) continue;
    final k = paidToPartyKeyOf(sourceType: p.sourceType, label: p.label, account: p.account);
    if (k != null) return k;
  }
  return null;
}

/// "Aug to Nov 2026" style words for one window of month bars ("Nov 2025 to Feb 2026" across a year,
/// "Oct 2026" for one month); '' when the window holds no month bar (7-day blocks have none).
String paidToWindowLabel(List<PaidToBar> window) {
  final ms = [
    for (final b in window)
      if (b.month != null) b.month!,
  ];
  if (ms.isEmpty) return '';
  final a = ms.first, b = ms.last;
  String my(DateTime d) => '${_mon[d.month - 1]} ${d.year}';
  if (a.year == b.year) return a.month == b.month ? my(a) : '${_mon[a.month - 1]} to ${my(b)}';
  return '${my(a)} to ${my(b)}';
}
