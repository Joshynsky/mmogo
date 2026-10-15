import 'package:flutter/services.dart';

import '../../domain/format/ksh_amount.dart';

/// Lets an amount field hold only a valid shape (digits, one optional `.`,
/// at most two decimals): any edit or paste that would break it is ignored.
class KshInputFormatter extends TextInputFormatter {
  const KshInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      kshTypingShape.hasMatch(newValue.text) ? newValue : oldValue;
}

/// Digits with thousands separators, no sign: `1500` -> `1,500`, `2000.5` ->
/// `2,000.5`. [raw] must already be a valid typing shape without commas.
String groupKshText(String raw) {
  final dot = raw.indexOf('.');
  final whole = dot < 0 ? raw : raw.substring(0, dot);
  final tail = dot < 0 ? '' : raw.substring(dot);
  return whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',') + tail;
}

/// The Add amount field (signed 08-10-2026): same shape rule as
/// [KshInputFormatter] but the field SHOWS thousands separators as you type
/// (`2,000.00`, like the review sheet). The caret keeps its place counted in
/// digits and dots. The commas are display only: read the value with
/// [stripKshGrouping] before [parseKshCents].
class KshGroupedInputFormatter extends TextInputFormatter {
  const KshGroupedInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = stripKshGrouping(newValue.text);
    if (!kshTypingShape.hasMatch(raw)) return oldValue;
    final grouped = groupKshText(raw);
    final sel = newValue.selection;
    final caret = sel.isValid ? sel.baseOffset.clamp(0, newValue.text.length) : newValue.text.length;
    final before = stripKshGrouping(newValue.text.substring(0, caret)).length;
    var pos = 0;
    var seen = 0;
    while (pos < grouped.length && seen < before) {
      if (grouped[pos] != ',') seen++;
      pos++;
    }
    return TextEditingValue(text: grouped, selection: TextSelection.collapsed(offset: pos));
  }
}

/// [text] without the display commas.
String stripKshGrouping(String text) => text.replaceAll(',', '');
