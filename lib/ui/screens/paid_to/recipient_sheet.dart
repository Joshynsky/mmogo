import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_sheet.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/tabular.dart';
import '../../widgets/type_icon.dart';

/// §PAIDTO.SHEET — the recipient sheet INSIDE Paid to (mock `openRecipient`): header (tile, name,
/// "Type · detail", close X), the combined-numbers note when more than one stored phone form, a 2x2
/// grid (Total paid / Total withdrawn for an agent, Payments / Withdrawals, Average, Transaction
/// cost), First and Last payment, a bar chart (PER WEEK for Month, PER MONTH for Year and All time)
/// and BY CATEGORY rows, then the Analytics ("See in Analytics") and Close buttons side by side. Figures are the row's own
/// (shown period, the row's category filter). Closed by Close, the X, a scrim tap or Back.
/// Pops `true` when "See these payments in Analytics" was chosen, else `null`.
Future<bool?> showPaidToRecipientSheet(
  BuildContext context, {
  required AppPalette palette,
  required PaidToRecipient recipient,
  required PaidToSheetData data,
  required String periodWords,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => PaidToRecipientSheet(palette: palette, recipient: recipient, data: data, periodWords: periodWords),
  );
}

class PaidToRecipientSheet extends StatelessWidget {
  const PaidToRecipientSheet({
    super.key,
    required this.palette,
    required this.recipient,
    required this.data,
    required this.periodWords,
  });

  final AppPalette palette;
  final PaidToRecipient recipient;
  final PaidToSheetData data;
  final String periodWords;

  static String _date(DateTime d) => '${fmtDayMonth(d)} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final g = recipient;
    final w = g.sourceType == paidToWithdrawal;
    final col = p.typeColor(g.sourceType);
    final label = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.66, color: p.mutedInk);

    Widget stat(String l, String v) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.42, color: p.mutedInk),
          ),
          const SizedBox(height: 1),
          Text(
            v,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, fontFeatures: tabularFigures, color: p.ink),
          ),
        ],
      ),
    );

    Widget date(String l, String v, CrossAxisAlignment a) => Column(
      crossAxisAlignment: a,
      children: [
        Text(l, style: TextStyle(fontSize: 12, color: p.mutedInk)),
        Text(
          v,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
        ),
      ],
    );

    final maxBar = data.bars.fold<int>(1, (m, b) => math.max(m, b.cents));
    final chartSummary = [
      for (final b in data.bars)
        if (b.cents > 0) '${b.label} ${formatKsh(b.cents)}',
    ].join(', ');

    Widget bar(PaidToBar b) => Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (data.valueLabels && b.cents > 0)
            Text(
              paidToCompact(b.cents),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
                fontFeatures: tabularFigures,
                color: p.softInk,
              ),
            ),
          Container(
            height: b.cents > 0 ? math.max(3.0, b.cents / maxBar * 70) : 2,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: b.cents > 0 ? col : p.track,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
            ),
          ),
          SizedBox(
            height: 14,
            child: Text(
              b.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(fontSize: 9.5, color: p.mutedInk),
            ),
          ),
        ],
      ),
    );

    // S7c: the two buttons share one row (equal widths, 8 px apart, each at least 44 px high). The
    // label may wrap to two lines at large text; the screen-reader label keeps the full sentence.
    Widget action(Key key, String text, Color bg, Color fg, VoidCallback onTap, {String? semantics}) => Expanded(
      child: Semantics(
        label: semantics,
        button: semantics != null ? true : null,
        excludeSemantics: semantics != null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: FilledButton(
            key: key,
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: bg,
              foregroundColor: fg,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
            ),
            child: Text(text, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ),
        ),
      ),
    );

    return BottomSheetShell(
      palette: p,
      children: [
        Row(
          children: [
            TypeIconTile(code: g.sourceType, color: col),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.name,
                    key: const Key('paidToSheetName'),
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink),
                  ),
                  Text(
                    '${sourceTypeName(g.sourceType)}${g.detail.isNotEmpty ? ' · ${g.detail}' : ''}',
                    style: TextStyle(fontSize: 11, color: p.mutedInk),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Close',
              excludeSemantics: true,
              child: Material(
                color: p.track,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('paidToSheetX'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(width: 34, height: 34, child: Icon(Icons.close_rounded, size: 16, color: p.ink)),
                ),
              ),
            ),
          ],
        ),
        if (g.phones.length > 1)
          Text(
            'Combined numbers (as stored): ${g.phones.join(' · ')}',
            key: const Key('paidToSheetCombined'),
            style: TextStyle(fontSize: 11.5, height: 1.4, color: p.mutedInk),
          ),
        // The 2x2 grid (two rows of two equal boxes, as tall as their text needs).
        Column(
          children: [
            Row(
              children: [
                Expanded(child: stat(w ? 'Total withdrawn' : 'Total paid', formatKsh(data.totalCents))),
                const SizedBox(width: 8),
                Expanded(child: stat(w ? 'Withdrawals' : 'Payments', '${data.count}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: stat('Average', formatKsh(data.averageCents))),
                const SizedBox(width: 8),
                Expanded(child: stat('Transaction cost', formatKsh(data.feeCents))),
              ],
            ),
          ],
        ),
        Row(
          children: [
            Expanded(child: date('First payment', _date(data.first), CrossAxisAlignment.start)),
            const SizedBox(width: 8),
            Expanded(child: date('Last payment', _date(data.last), CrossAxisAlignment.end)),
          ],
        ),
        Text.rich(
          key: const Key('paidToSheetChartTitle'),
          TextSpan(
            style: label,
            children: [
              TextSpan(text: data.perWeek ? 'PER WEEK ' : 'PER MONTH '),
              TextSpan(
                text: '· $periodWords${data.perWeek ? ' (days 1–7, 8–14 ...)' : ''}',
                style: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        Semantics(
          image: true,
          label: chartSummary,
          excludeSemantics: true,
          child: SizedBox(
            key: const Key('paidToSheetChart'),
            // Grows with the text size so the value labels never overflow the bars' column.
            height: 96 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final b in data.bars) bar(b)]),
          ),
        ),
        Text('BY CATEGORY', style: label),
        Column(
          children: [
            for (final (i, c) in data.categories.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                ),
                child: Row(
                  key: Key('paidToSheetCat-${c.name}'),
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${c.count}× · ${kshTrim(c.cents)}',
                      style: TextStyle(fontSize: 12, fontFeatures: tabularFigures, color: p.mutedInk),
                    ),
                  ],
                ),
              ),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              action(
                const Key('paidToSheetAnalytics'),
                'See in Analytics',
                p.primary,
                p.onPrimary,
                () => Navigator.of(context).pop(true),
                semantics: 'See these payments in Analytics',
              ),
              const SizedBox(width: 8),
              action(const Key('paidToSheetClose'), 'Close', p.track, p.ink, () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ],
    );
  }
}
