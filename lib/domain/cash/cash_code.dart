/// T3 — Add — Cash tab.
///
/// Generates the `CASH-YYYYMMDD-HHMM` display code for a manually-entered
/// cash transaction, from its (user-entered) `transaction_occurred_at`
/// epoch millis. The code is timestamp-based (the PM's direct choice over
/// sequential or random-hash codes): it encodes when the transaction
/// happened and is distinct enough from a real M-Pesa code to never be
/// confused with one. `display_code` is a non-unique display
/// column, NOT the real primary key (`transactions.id`, autoincrement, is)
/// — two same-minute cash entries producing an identical string here is
/// expected and schema-safe, not a bug this function needs to prevent.
///
/// It generates from the *entered* date/time, not "now".
library;

String generateCashDisplayCode(int occurredAtEpochMillis) {
  final d = DateTime.fromMillisecondsSinceEpoch(occurredAtEpochMillis);
  final y = d.year.toString().padLeft(4, '0');
  final mo = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final h = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return 'CASH-$y$mo$day-$h$mi';
}
