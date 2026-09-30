/// §FORMAT.SOURCE_TYPES — the four transaction source types in their fixed
/// chart/bar order (colours never move, T20) with their display names.
const sourceTypeOrder = [
  ('SEND_MONEY', 'Send Money'),
  ('PAYBILL', 'Paybill'),
  ('BUY_GOODS', 'Buy Goods'),
  ('CASH', 'Cash'),
];

/// The display name of a source-type [code]; an unknown code is returned as is.
String sourceTypeName(String code) {
  for (final (c, name) in sourceTypeOrder) {
    if (c == code) return name;
  }
  return code;
}
