import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/ksh_input_formatter.dart';
import 'form_row.dart';

/// §ADD.DETAILS — Code (D1: 10 characters, uppercase, D5's "already
/// recorded" duplicate check), When (the existing date & time picker via
/// "Change", D7's low-key text) and Fee.
class DetailsCard extends StatelessWidget {
  const DetailsCard({
    super.key,
    required this.code,
    required this.fee,
    required this.codeShapeInvalid,
    required this.codeDuplicate,
    required this.whenText,
    required this.onCodeChanged,
    required this.onFeeChanged,
    required this.onWhenChangeTap,
  });

  final TextEditingController code;
  final TextEditingController fee;
  final bool codeShapeInvalid;
  final bool codeDuplicate;
  final String whenText;
  final ValueChanged<String> onCodeChanged;
  final ValueChanged<String> onFeeChanged;
  final VoidCallback onWhenChangeTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(
            context,
            palette,
            label: 'Code',
            child: TextField(
              key: const Key('addCodeField'),
              controller: code,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseTextFormatter()],
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.ink),
              cursorColor: palette.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'e.g. THA7K2P9QX',
                hintStyle: TextStyle(color: palette.mutedInk),
              ),
              onChanged: onCodeChanged,
            ),
          ),
          if (codeShapeInvalid)
            _errorText(key: const Key('addCodeShapeError'), text: 'Enter the 10-character M-Pesa code')
          else if (codeDuplicate)
            _errorText(key: const Key('addCodeDuplicateError'), text: 'This code is already recorded'),
          Divider(height: 1, color: palette.line),
          _row(
            context,
            palette,
            label: 'When',
            child: Row(
              children: [
                Expanded(
                  child: Text(whenText, key: const Key('addWhenText'), style: TextStyle(fontSize: 13.5, color: palette.ink)),
                ),
                TextButton(
                  key: const Key('addWhenChangeButton'),
                  onPressed: onWhenChangeTap,
                  style: TextButton.styleFrom(foregroundColor: palette.primary),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.line),
          _row(
            context,
            palette,
            label: 'Fee',
            child: TextField(
              key: const Key('addFeeField'),
              controller: fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [KshInputFormatter()],
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.ink),
              cursorColor: palette.primary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'Ksh 0.00',
                hintStyle: TextStyle(color: palette.mutedInk),
              ),
              onChanged: onFeeChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppPalette palette, {required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: AddFormRow(
        label: label,
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.mutedInk),
        labelWidth: 60,
        child: child,
      ),
    );
  }

  Widget _errorText({required Key key, required String text}) {
    return Padding(
      padding: const EdgeInsets.only(left: 14, right: 14, bottom: 8),
      child: Text(text, key: key, style: const TextStyle(fontSize: 11.5, color: Color(0xFFE5484D))),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

/// Cash's own version of this card (build step 8: "the amount, When, and
/// category chips only") — just the When row, same low-key text + "Change"
/// link, no Code/Fee.
class CashWhenRow extends StatelessWidget {
  const CashWhenRow({super.key, required this.whenText, required this.onWhenChangeTap});

  final String whenText;
  final VoidCallback onWhenChangeTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(14)),
      child: AddFormRow(
        label: 'When',
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.mutedInk),
        labelWidth: 60,
        child: Row(
          children: [
            Expanded(child: Text(whenText, key: const Key('addCashWhenText'), style: TextStyle(fontSize: 13.5, color: palette.ink))),
            TextButton(
              key: const Key('addCashWhenChangeButton'),
              onPressed: onWhenChangeTap,
              style: TextButton.styleFrom(foregroundColor: palette.primary),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
  }
}

const _monthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// D7 — plain, low-key date/time text ("Today, 3:57 PM" / "19 Sep 2026,
/// 2:10 PM"), carried forward unchanged from the old `mpesa_tab_body.dart`/
/// `cash_tab_body.dart`'s duplicated private helper — one definition now,
/// shared by both this file's own `whenText` callers (`add_screen.dart`).
String formatLowKeyDateTime(DateTime d) {
  final now = DateTime.now();
  final hour24 = d.hour;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final minute = d.minute.toString().padLeft(2, '0');
  final time = '$hour12:$minute $period';
  final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
  if (isToday) return 'Today, $time';
  final day = d.day.toString().padLeft(2, '0');
  return '$day ${_monthAbbrev[d.month - 1]} ${d.year}, $time';
}
