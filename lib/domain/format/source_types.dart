/// §FORMAT.SOURCE_TYPES — the seven transaction source types in their fixed
/// chart/bar order (colours never move, T20) with their display names. The
/// four 0.1.1 types keep their places; the three 0.1.2 types follow them.
const sourceTypeOrder = [
  ('SEND_MONEY', 'Send Money'),
  ('PAYBILL', 'Paybill'),
  ('BUY_GOODS', 'Buy Goods'),
  ('CASH', 'Cash'),
  ('POCHI_LA_BIASHARA', 'Pochi'),
  ('AGENT_WITHDRAWAL', 'Withdrawal'),
  ('AIRTIME', 'Airtime'),
];

/// The display name of a source-type [code]; an unknown code is returned as is.
String sourceTypeName(String code) {
  for (final (c, name) in sourceTypeOrder) {
    if (c == code) return name;
  }
  return code;
}
