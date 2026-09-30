/// Shared money/date formatting helpers, pure Dart (no `intl` dependency —
/// not a project dependency yet, and these formats are small/fixed enough
/// not to need it). Reused wherever `Ksh`-formatted amounts appear;
/// currently Home (T4), later Parties/Analytics.
library;

const _monthAbbrev = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Formats integer cents as `Ksh 1,500.00`, matching the prototype's
/// `fmtMoney` (`toLocaleString('en-KE', {minimumFractionDigits:2,
/// maximumFractionDigits:2})`) without pulling in `intl`.
String formatKsh(int cents) {
  final isNegative = cents < 0;
  final abs = cents.abs();
  final whole = abs ~/ 100;
  final frac = (abs % 100).toString().padLeft(2, '0');
  return 'Ksh ${isNegative ? '-' : ''}${_groupThousands(whole)}.$frac';
}

/// `Ksh 1,500` — [formatKsh] without the `.00` (the mock's
/// `ksh(v).replace('.00', '')`).
String kshTrim(int cents) => formatKsh(cents).replaceFirst('.00', '');

String _groupThousands(int n) {
  final s = n.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
    buffer.write(s[i]);
  }
  return buffer.toString();
}

/// Formats a date as `18 Sep`, matching the prototype's recent-transaction
/// sub-line (`toLocaleDateString('en-GB', {day:'2-digit', month:'short'})`).
String formatShortDate(DateTime d) {
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_monthAbbrev[d.month - 1]}';
}

/// Formats a date as `18 Sep 2026`, matching Profile's "Date range covered"
/// row in the prototype (`toLocaleDateString('en-GB',
/// {day:'2-digit', month:'short', year:'numeric'})`). T17.
String formatLongDate(DateTime d) => '${formatShortDate(d)} ${d.year}';
