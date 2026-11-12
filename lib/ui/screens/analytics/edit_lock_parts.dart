import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import 'sheet_parts.dart';

/// §ANALYTICS.EDIT_LOCK — 0.2.0 S9 (mock `analytics-sheets.js` S6b, CHANGES item 4): the pieces of the edit
/// sheet for a row that was read from an M-Pesa message. Amount, date and time, phone / account / agent
/// number and transaction cost are the message's own figures: shown read-only with a padlock and one
/// caption. The receiver name and the category stay editable. Fuliza tags (the "How it was paid" block) are
/// read-only too, with their own padlock note.
/// WORDING-DRAFT: "From the M-Pesa message, so it can't be changed", "How it was paid", "Paid with Fuliza",
/// "From your M-Pesa", "From Fuliza", "Total", "(borrowed)", "Fuliza is a loan; repaying it is tracked on the
/// Fuliza page.", "Fuliza tags come from the messages and cannot be edited."
const String kEditLockedCaption = "From the M‑Pesa message, so it can't be changed";
const String kFulizaTagsLockedNote = 'Fuliza tags come from the messages and cannot be edited.';

/// What the edit sheet needs to draw the "How it was paid" block for a row a borrowing paid for.
class FulizaPaidInfo {
  const FulizaPaidInfo({required this.drawCents});

  /// The borrowing's amount in cents (the part paid by Fuliza, capped at the row's amount).
  final int drawCents;
}

/// A field label followed by a small padlock.
Widget editLockedLabel(AppPalette p, String text) => Row(
  children: [
    Flexible(child: analyticsFieldLabel(p, text)),
    const SizedBox(width: 4),
    Icon(Icons.lock_outline_rounded, size: 13, color: p.mutedInk, semanticLabel: 'locked'),
  ],
);

/// The read-only value box (same look as an input, no cursor, not focusable). An optional [trailing]
/// (the Copy button) sits beside it.
class EditLockedBox extends StatelessWidget {
  const EditLockedBox({super.key, required this.palette, required this.text, this.trailing});

  final AppPalette palette;
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final box = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: analyticsFieldBox(p),
      child: Semantics(
        label: '$text, from the M‑Pesa message, cannot be changed',
        excludeSemantics: true,
        child: Text(
          text,
          style: TextStyle(fontSize: 13, fontFeatures: tabularFigures, color: p.softInk),
        ),
      ),
    );
    if (trailing == null) return box;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: box),
        trailing!,
      ],
    );
  }
}

/// The single caption under the locked fields.
class EditLockedCaption extends StatelessWidget {
  const EditLockedCaption({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Row(
    key: const Key('editLockedCaption'),
    children: [
      Icon(Icons.lock_outline_rounded, size: 13, color: palette.mutedInk),
      const SizedBox(width: 6),
      Expanded(
        child: Text(kEditLockedCaption, style: TextStyle(fontSize: 11.5, color: palette.mutedInk)),
      ),
    ],
  );
}

/// "How it was paid": whole Fuliza, or part own money and part Fuliza. Tapping it opens the Fuliza page.
class EditFulizaBlock extends StatelessWidget {
  const EditFulizaBlock({
    super.key,
    required this.palette,
    required this.amountCents,
    required this.drawCents,
    required this.onTap,
  });

  final AppPalette palette;
  final int amountCents;
  final int drawCents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final full = drawCents >= amountCents;
    Widget line(String l, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              l,
              style: TextStyle(fontSize: 12, fontWeight: strong ? FontWeight.w700 : FontWeight.w400, color: p.softInk),
            ),
          ),
          Text(
            v,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: tabularFigures, color: p.ink),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: 'How it was paid. ${full ? 'Paid with Fuliza' : 'Part paid with Fuliza'}. Open the Fuliza page',
      excludeSemantics: true,
      child: InkWell(
        key: const Key('editFulizaBlock'),
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'How it was paid',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: p.ink),
                    ),
                    const SizedBox(height: 2),
                    if (full)
                      line('Paid with Fuliza', '${kshTrim(amountCents)} (borrowed)')
                    else ...[
                      line('From your M‑Pesa', kshTrim(amountCents - drawCents)),
                      line('From Fuliza', kshTrim(drawCents)),
                      line('Total', kshTrim(amountCents), strong: true),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Fuliza is a loan; repaying it is tracked on the Fuliza page.',
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      key: const Key('editFulizaLockedNote'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.lock_outline_rounded, size: 12, color: p.mutedInk),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            kFulizaTagsLockedNote,
                            style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 20, color: p.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 0.2.0 S9: the default for [AnalyticsEditSheet.lockMessageFields]. False = the signed 0.1.3 edit sheet. main.dart
/// turns it on in the debug flavor (`kAutoReadCompiled`) only, until the PM signs the lock for the standard build.
class EditLockSwitch {
  EditLockSwitch._();

  static bool messageRowsReadOnly = false;
}
