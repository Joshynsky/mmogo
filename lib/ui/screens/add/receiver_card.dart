import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'form_row.dart';

/// §ADD.RECEIVER — receiver capture (T15/T6-D3), opt-in: the per-type label
/// and fields (Name + Phone / Business + Account / Shop), plus the subline
/// "So you can see them on Paid to. Leave it off to keep it private."
class ReceiverCard extends StatelessWidget {
  const ReceiverCard({
    super.key,
    required this.type,
    required this.checked,
    required this.name,
    required this.sub,
    required this.onCheckedChanged,
    required this.onFieldChanged,
  });

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'`.
  final String type;
  final bool checked;
  final TextEditingController name;

  /// Phone (Send Money) / Account (Paybill). Unused for Buy Goods.
  final TextEditingController sub;
  final ValueChanged<bool> onCheckedChanged;
  final VoidCallback onFieldChanged;

  (String, String, String?) get _labels => switch (type) {
        'SEND_MONEY' => ('Also record the receiver’s name & phone', 'Name', 'Phone'),
        'PAYBILL' => ('Also record the business & account', 'Business', 'Account'),
        _ => ('Also record the shop’s name', 'Shop', null),
      };

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (label, nameLabel, subLabel) = _labels;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(color: palette.card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const Key('addCaptureCheckbox'),
            onTap: () => onCheckedChanged(!checked),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Checkbox(
                    value: checked,
                    activeColor: palette.primary,
                    checkColor: palette.onPrimary,
                    side: BorderSide(color: palette.mutedInk, width: 1.5),
                    onChanged: (v) => onCheckedChanged(v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink)),
                        const SizedBox(height: 2),
                        Text(
                          'So you can see them on Paid to. Leave it off to keep it private.',
                          style: TextStyle(fontSize: 11.5, color: palette.mutedInk),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (checked) ...[
            Divider(height: 1, color: palette.line),
            _field(context, palette, key: const Key('addReceiverNameField'), label: nameLabel, controller: name),
            if (subLabel != null) ...[
              Divider(height: 1, color: palette.line),
              _field(
                context,
                palette,
                key: const Key('addReceiverSubField'),
                label: subLabel,
                controller: sub,
                keyboardType: type == 'SEND_MONEY' ? TextInputType.phone : TextInputType.text,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _field(
    BuildContext context,
    AppPalette palette, {
    required Key key,
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: AddFormRow(
        label: label,
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.mutedInk),
        labelWidth: 70,
        child: TextField(
          key: key,
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.ink),
          cursorColor: palette.primary,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          onChanged: (_) => onFieldChanged(),
        ),
      ),
    );
  }
}
