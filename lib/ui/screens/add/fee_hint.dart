import 'package:flutter/material.dart';

import '../../../domain/fees/safaricom_withdrawal_fees.dart';
import '../../../domain/format/ksh_amount.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ksh_input_formatter.dart';
import '../../widgets/tap_target.dart';

/// §ADD.FEE_HINT — 0.1.2 S8c-2 (AD2 / CB11 / WD8b). Under the Withdrawal Fee
/// field: while Fee is EMPTY a tappable muted line plus a small "Usual fee"
/// pill (both put the usual fee in the field and do nothing else); once a fee is
/// there and it differs from the usual one, a soft note. Never a prefill, never
/// a lock, never blocks saving, never rewrites a parsed fee. The tariff lives in
/// `domain/fees/safaricom_withdrawal_fees.dart`; this file only shows it.

/// Whole shillings with thousands commas, no decimals (`200000` cents -> `2,000`).
String feeHintKsh(int cents) => groupKshText((cents ~/ 100).toString());

/// The fee-differs note (CB11). The apostrophe is U+2019 (the mock's).
String feeDiffersNoteText(int amountCents, int usualCents) =>
    'Safaricom’s usual fee for Ksh ${feeHintKsh(amountCents)} is Ksh ${feeHintKsh(usualCents)} '
    '(as of $kWithdrawalFeesAsOf). Check your message.';

/// The hint line text and its screen-reader label.
String feeHintLineText(int amountCents) =>
    'Safaricom’s usual fee for Ksh ${feeHintKsh(amountCents)}. Tap to use it.';
String feeHintLineLabel(int amountCents, int usualCents) =>
    'Safaricom’s usual fee for Ksh ${feeHintKsh(amountCents)} is Ksh ${feeHintKsh(usualCents)}. Tap to use it.';

/// What goes in the Fee field when the hint is tapped: `29.00`.
String feeHintFieldText(int usualCents) => (usualCents / 100).toStringAsFixed(2);

class FeeHint extends StatelessWidget {
  const FeeHint({super.key, required this.amountCents, required this.feeText, required this.onUse});

  /// The parsed Amount, or null when it is empty or invalid.
  final int? amountCents;

  /// What the Fee field holds right now.
  final String feeText;

  /// Fired with the usual fee in cents.
  final ValueChanged<int> onUse;

  @override
  Widget build(BuildContext context) {
    final amount = amountCents;
    if (amount == null) return const SizedBox.shrink();
    final usual = suggestedWithdrawalFee(amount);
    if (usual == null) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final fee = feeText.trim();
    if (fee.isEmpty) {
      void use() => onUse(usual);
      return Padding(
        key: const Key('addFeeHintRow'),
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: feeHintLineLabel(amount, usual),
                excludeSemantics: true,
                onTap: use,
                child: InkWell(
                  key: const Key('addFeeHintLine'),
                  onTap: use,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: kMinTapTarget),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        feeHintLineText(amount),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: palette.mutedInk,
                          decoration: TextDecoration.underline,
                          decorationStyle: TextDecorationStyle.dotted,
                          decorationColor: palette.mutedInk,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // The pill repeats the line for the eye; screen readers hear it once.
            ExcludeSemantics(
              child: TapTarget(
                key: const Key('addFeeHintPill'),
                expandWidth: false,
                onTap: use,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.tint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.primary, width: 1.5),
                  ),
                  child: Text(
                    'Usual fee Ksh ${feeHintKsh(usual)}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: palette.tintInk),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final typed = parseKshCents(fee, allowZero: true);
    if (typed == null || feeCheck(amount, typed).looksUsual) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Text(
        feeDiffersNoteText(amount, usual),
        key: const Key('addFeeDiffersNote'),
        style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: palette.mutedInk),
      ),
    );
  }
}
