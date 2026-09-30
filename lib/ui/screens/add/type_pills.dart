import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'form_row.dart';

/// §ADD.TYPES — Send Money / Paybill / Buy Goods pills. Shown only pre-parse ("or enter it yourself");
/// once a paste has filled the form the shell stops building this widget at
/// all, which is D2's "Type LOCKS after a successful parse" carried
/// forward — a locked control can't be tapped no matter which layer is
/// asked, and not building it at all is the strongest form of that.
class TypePills extends StatelessWidget {
  const TypePills({super.key, required this.type, required this.onChanged});

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'`.
  final String type;
  final ValueChanged<String> onChanged;

  static const _options = [
    ('SEND_MONEY', 'Send Money'),
    ('PAYBILL', 'Paybill'),
    ('BUY_GOODS', 'Buy Goods'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        for (final option in _options)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _pill(context, palette, option.$2, option.$1),
            ),
          ),
      ],
    );
  }

  static Widget orDivider(AppPalette palette) {
    final style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: palette.mutedInk);
    return Builder(
      builder: (context) {
        // The text can't wrap between the two divider lines, so at a large
        // phone font it stands alone, centred, without them.
        if (MediaQuery.textScalerOf(context).scale(1) >= AddFormRow.stackAbove) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: Text('or enter it yourself', textAlign: TextAlign.center, style: style)),
          );
        }
        return Row(
          children: [
            Expanded(child: Divider(color: palette.line)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or enter it yourself', style: style)),
            Expanded(child: Divider(color: palette.line)),
          ],
        );
      },
    );
  }

  Widget _pill(BuildContext context, AppPalette palette, String label, String value) {
    final active = type == value;
    return GestureDetector(
      key: Key('addTypePill_$value'),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? palette.primary : palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? palette.primary : palette.line, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: active ? palette.onPrimary : palette.ink,
          ),
        ),
      ),
    );
  }
}
