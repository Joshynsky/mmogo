import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_counts.dart';
import '../../theme/app_colors.dart';

/// §PAIDTO.NOT_RECORDED — the ONE muted line per type section (mock `nrLine`):
/// "Not recorded · N payments · Ksh X" (with the type name first, "Send Money · Not recorded ...",
/// in the overview and for a type that has no recipients; plain in a type view that has some).
/// Payments with no captured receiver are not recipients: NO tap, no recipient sheet, not in the
/// pills, the hero's recipient count or "Show N". Hidden while a search is typed (the caller
/// passes an empty summary then).
class PaidToNotRecordedLine extends StatelessWidget {
  const PaidToNotRecordedLine({
    super.key,
    required this.palette,
    required this.type,
    required this.summary,
    required this.withType,
  });

  final AppPalette palette;
  final String type;
  final PaidToNotRecorded summary;
  final bool withType;

  /// The line's words (also what a test pins).
  static String text(String type, PaidToNotRecorded s, {required bool withType}) =>
      '${withType ? '${sourceTypeName(type)} · ' : ''}Not recorded · ${s.count} ${paidToPayWord(type, s.count)} · ${kshTrim(s.totalCents)}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Text(
        text(type, summary, withType: withType),
        style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: palette.softInk),
      ),
    );
  }
}
