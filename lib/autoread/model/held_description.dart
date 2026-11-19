/// §AUTOREAD.HELD_DESCRIPTION — what a held message is, in words (pure Dart).
///
/// Every field is derived text, never the message body. [what] describes a
/// readable message ("Sent Ksh 200 to Wanjiru Kamau"); [code], [amount] and
/// [time] are what the light reader found in an unreadable one. A field is
/// null when it was not found. Held in memory only, shown in the app only.
library;

class HeldDescription {
  const HeldDescription({this.what, this.code, this.amount, this.time, this.notice = false});

  final String? what;
  final String? code;
  final String? amount;
  final String? time;

  /// True when the light reader recognised an M-Pesa system notice that is not a
  /// transaction (e.g. "unable to process ... similar transaction underway").
  final bool notice;

  /// True when nothing was found (the row keeps its fallback title).
  bool get isEmpty => what == null && code == null && amount == null && time == null && !notice;
}
