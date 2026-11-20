import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_counts.dart';
import '../../theme/app_colors.dart';

/// 0.1.3 F3: the ONE muted Airtime line ("Airtime · 2 purchases · Ksh 120"). Airtime has no
/// recipient, so there is no tap and no sheet; its money is inside the hero's "Paid out".
class PaidToAirtimeLine extends StatelessWidget {
  const PaidToAirtimeLine({super.key, required this.palette, required this.summary});

  final AppPalette palette;
  final PaidToAirtime summary;

  /// The line's words (also what a test pins).
  static String text(PaidToAirtime s) =>
      'Airtime · ${s.count} ${s.count == 1 ? 'purchase' : 'purchases'} · ${kshTrim(s.totalCents)}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Text(
        text(summary),
        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: palette.softInk),
      ),
    );
  }
}

/// §PAIDTO.NOT_RECORDED — the ONE muted line per type section (mock `nrLine`):
/// "Receiver not saved · N payments · Ksh X" (with the type name first, "Send Money · Receiver not
/// saved ...", in the overview and for a type that has no recipients; plain in a type view that has
/// some). Payments with no captured receiver are not recipients: no recipient sheet, not in the
/// pills, the hero's recipient count or "Show N". Hidden while a search is typed (the caller
/// passes an empty summary then).
///
/// 0.2.1 #4 (was "Not recorded"; PM contender 4, recommendation A): the words say what is missing
/// (the receiver), and with [onTap] the line is a button (44 px high, an info icon) that explains why
/// and offers the "Record receiver details" switch (`showPaidToNotRecordedExplainer`).
/// WORDING-DRAFT: "Receiver not saved".
class PaidToNotRecordedLine extends StatelessWidget {
  const PaidToNotRecordedLine({
    super.key,
    required this.palette,
    required this.type,
    required this.summary,
    required this.withType,
    this.onTap,
  });

  final AppPalette palette;
  final String type;
  final PaidToNotRecorded summary;
  final bool withType;

  /// Opens the explanation; null = a plain muted line.
  final VoidCallback? onTap;

  /// The line's words (also what a test pins).
  static String text(String type, PaidToNotRecorded s, {required bool withType}) =>
      '${withType ? '${sourceTypeName(type)} · ' : ''}Receiver not saved · ${s.count} ${paidToPayWord(type, s.count)} · ${kshTrim(s.totalCents)}';

  @override
  Widget build(BuildContext context) {
    final words = text(type, summary, withType: withType);
    final line = Text(words, style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: palette.softInk));
    if (onTap == null) {
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: line);
    }
    return Semantics(
      button: true,
      label: '$words. Tap to see why',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Flexible(child: line),
                const SizedBox(width: 6),
                Icon(Icons.info_outline_rounded, size: 15, color: palette.softInk),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
