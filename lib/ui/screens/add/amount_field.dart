import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/ksh_input_formatter.dart';

/// §ADD.AMOUNT — the big, centred amount field.
/// Shared by both M-Pesa and Cash. [errorText] is a plain inline message
/// shown under the field when what was typed is not an acceptable amount.
class AmountField extends StatelessWidget {
  const AmountField({super.key, required this.controller, required this.onChanged, this.errorText});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Ksh', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: palette.mutedInk)),
          const SizedBox(width: 6),
          SizedBox(
            width: 190,
            child: TextField(
              key: const Key('addAmountField'),
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: const [KshInputFormatter()],
              style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: palette.ink),
              cursorColor: palette.primary,
              decoration: InputDecoration(
                border: UnderlineInputBorder(borderSide: BorderSide(color: palette.line)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 2)),
                errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.diffUp)),
                focusedErrorBorder: UnderlineInputBorder(borderSide: BorderSide(color: palette.diffUp, width: 2)),
                errorText: errorText,
                errorMaxLines: 2,
                errorStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: palette.diffUp),
                hintText: '0.00',
                // Dimmer than typed text but on the palette (the theme's own hint colour is olive grey).
                hintStyle: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: palette.mutedInk.withValues(alpha: 0.55)),
                isDense: true,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
