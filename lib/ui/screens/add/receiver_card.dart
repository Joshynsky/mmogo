import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/error_notes.dart';
import 'form_row.dart';

/// B3: longest receiver / label text the Add form accepts (typing is cut here;
/// longer values already saved are loaded as they are).
const receiverFieldMaxLength = 200;

/// The longest agent number the database accepts (`agent_number` CHECK).
const agentNumberMaxLength = 20;

/// The line under the "Also record ..." label (also its spoken hint).
const kReceiverCaptureHint = 'So you can see them on Paid to. Leave it off to keep it private.';

/// §ADD.RECEIVER — receiver capture (T15/T6-D3), opt-in: the per-type label
/// and fields (Name + Phone / Business + Account / Shop / Pochi name /
/// Agent name + Agent number, S8c-1), plus the subline
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
    this.subError,
    this.onNameChanged,
    this.belowName,
  });

  /// One of `'SEND_MONEY'`, `'PAYBILL'`, `'BUY_GOODS'`.
  final String type;
  final bool checked;
  final TextEditingController name;

  /// Phone (Send Money) / Account (Paybill). Unused for Buy Goods.
  final TextEditingController sub;
  final ValueChanged<bool> onCheckedChanged;
  final VoidCallback onFieldChanged;

  /// Inline error under the second field (the agent number), or null.
  final String? subError;

  /// 0.1.2 S8c-2: fired when the user types in the Name field (the remembered
  /// recipients chooser listens), and the widget shown right under that field.
  final VoidCallback? onNameChanged;
  final Widget? belowName;

  bool get _isAgent => type == 'AGENT_WITHDRAWAL';

  (String, String, String?) get _labels => switch (type) {
        'SEND_MONEY' => ('Also record the receiver’s name & phone', 'Name', 'Phone'),
        'PAYBILL' => ('Also record the business & account', 'Business', 'Account'),
        'POCHI_LA_BIASHARA' => ('Also record the receiver’s name', 'Name', null),
        'AGENT_WITHDRAWAL' => ('Also record the agent’s name & number', 'Agent name', 'Agent number'),
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
          // R53: the row and its checkbox are ONE stop: label, hint and checked.
          Semantics(
            container: true,
            checked: checked,
            label: label,
            hint: kReceiverCaptureHint,
            onTap: () => onCheckedChanged(!checked),
            excludeSemantics: true,
            child: InkWell(
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
                            kReceiverCaptureHint,
                            style: TextStyle(fontSize: 11.5, color: palette.mutedInk),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (checked) ...[
            Divider(height: 1, color: palette.line),
            _field(
              context,
              palette,
              key: const Key('addReceiverNameField'),
              label: nameLabel,
              controller: name,
              labelWidth: _isAgent ? 100 : 70,
              onChanged: onNameChanged,
            ),
            ?belowName,
            if (subLabel != null) ...[
              Divider(height: 1, color: palette.line),
              _field(
                context,
                palette,
                key: const Key('addReceiverSubField'),
                label: subLabel,
                controller: sub,
                keyboardType: type == 'SEND_MONEY'
                    ? TextInputType.phone
                    : (_isAgent ? TextInputType.number : TextInputType.text),
                maxLength: _isAgent ? agentNumberMaxLength : receiverFieldMaxLength,
                inputFormatters: _isAgent ? [FilteringTextInputFormatter.digitsOnly] : null,
                labelWidth: _isAgent ? 100 : 70,
              ),
              if (subError != null) KeyedSubtree(key: const Key('addReceiverSubError'), child: FieldError(subError!)),
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
    int maxLength = receiverFieldMaxLength,
    List<TextInputFormatter>? inputFormatters,
    double labelWidth = 70,
    VoidCallback? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: AddFormRow(
        label: label,
        labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.mutedInk),
        labelWidth: labelWidth,
        child: TextField(
          key: key,
          controller: controller,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: palette.ink),
          cursorColor: palette.primary,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none),
          onChanged: (_) {
            onFieldChanged();
            onChanged?.call();
          },
        ),
      ),
    );
  }
}
