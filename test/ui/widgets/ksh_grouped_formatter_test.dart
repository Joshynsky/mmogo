// 0.1.2 S8c-1: the Add amount field shows thousands separators as you type
// (signed 08-10-2026). Commas are display only.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/widgets/ksh_input_formatter.dart';

TextEditingValue _edit(String old, String next, {int? caret}) => const KshGroupedInputFormatter().formatEditUpdate(
      TextEditingValue(text: old, selection: TextSelection.collapsed(offset: old.length)),
      TextEditingValue(text: next, selection: TextSelection.collapsed(offset: caret ?? next.length)),
    );

void main() {
  test('groupKshText groups the whole part only', () {
    expect(groupKshText('2000'), '2,000');
    expect(groupKshText('2000.00'), '2,000.00');
    expect(groupKshText('999'), '999');
    expect(groupKshText('1234567.5'), '1,234,567.5');
    expect(groupKshText('.5'), '.5');
    expect(groupKshText(''), '');
  });

  test('typing adds commas; the caret stays after the typed digit', () {
    var v = _edit('', '2');
    expect(v.text, '2');
    v = _edit('200', '2000');
    expect(v.text, '2,000');
    expect(v.selection.baseOffset, 5);
    v = _edit('2,000', '12,000', caret: 1); // a digit typed at the front
    expect(v.text, '12,000');
    expect(v.selection.baseOffset, 1);
    v = _edit('999', '1999', caret: 2); // a digit typed after the first one: a comma appears before the caret
    expect(v.text, '1,999');
    expect(v.selection.baseOffset, 3);
  });

  test('the old shape rule still holds: 3 decimals, letters and 9 digits are refused', () {
    expect(_edit('1,500.00', '1,500.005').text, '1,500.00');
    expect(_edit('12', '12a').text, '12');
    expect(_edit('12,345,678', '123,456,789').text, '12,345,678');
  });

  test('pasting a comma-grouped value works and stripKshGrouping gives the raw digits', () {
    expect(_edit('', '1,500.50').text, '1,500.50');
    expect(stripKshGrouping('1,500.50'), '1500.50');
  });
}
