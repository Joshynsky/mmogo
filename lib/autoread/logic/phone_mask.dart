/// §AUTOREAD.PHONE_MASK: the ONE place a phone number is masked for the screen (0.2.2, F2).
/// Pure: no stored key and no data change. Format like M-Pesa: first 4 digits, `***`, last 3
/// (0722***555). Paid to keeps full numbers and does not use this.
library;

/// The mask for [raw] (07xx, 01xx, +254 or 254 form), or '' when it has no digits.
/// 254722000555 and +254722000555 show as 0722***555. Already masked (has a `*`): returned as is.
/// Fewer than 8 digits (too short to hide the middle): just `***`.
String maskPhone(String? raw) {
  final s = (raw ?? '').trim();
  if (s.contains('*')) return s;
  var d = s.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  if (d.length == 12 && d.startsWith('254')) d = '0${d.substring(3)}';
  if (d.length < 8) return '***';
  return '${d.substring(0, 4)}***${d.substring(d.length - 3)}';
}

/// True when [s] is only a number (digits, spaces, +, -, or already masked), i.e. not a name.
bool looksLikeNumber(String? s) {
  final t = (s ?? '').trim();
  if (t.isEmpty) return false;
  return RegExp(r'^[+\d\s\-*]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t);
}

/// What to show for a person: the NAME wins, a number-only label is masked, and a missing label
/// shows the masked [phone]. Never shows a raw number. '' when there is nothing.
String nameOrMask(String? name, String? phone) {
  final n = (name ?? '').trim();
  if (n.isNotEmpty) return looksLikeNumber(n) ? maskPhone(n) : n;
  return maskPhone(phone);
}

/// Name and mask together, to tell two people with one name apart: `LUCY AKINYI 0722***555`.
/// Without a name (or a number-only name) just the mask; without digits just the name.
String nameWithMask(String? name, String? phone) {
  final n = (name ?? '').trim();
  if (n.isEmpty || looksLikeNumber(n)) return maskPhone(n.isEmpty ? phone : n);
  final m = maskPhone(phone);
  return m.isEmpty ? n : '$n $m';
}
