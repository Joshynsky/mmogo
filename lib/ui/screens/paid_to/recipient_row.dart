import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import '../../widgets/type_icon.dart';

/// §PAIDTO.ROW — one recipient row (mock `rowHtml`): rank (unless sorted by Most recent), type
/// tile, name + "Last (date) · phone/acc/agent", amount + a second line by the sort, and a share
/// bar. A tap opens the recipient sheet and hands over the row's [FocusNode], so focus returns to
/// the row when the sheet closes.
///
///  - Amount / Most recent: total, then "n× · + Ksh X fee" (no fee note when the cost is 0);
///  - Times paid: "n×", then "total · + Ksh X fee";
///  - Transaction cost: the fee, then "n× · total paid" ("withdrawn" for an agent).
class PaidToRecipientRow extends StatefulWidget {
  const PaidToRecipientRow({
    super.key,
    required this.palette,
    required this.recipient,
    required this.rank,
    required this.share,
    required this.sort,
    required this.today,
    required this.onTap,
  });

  final AppPalette palette;
  final PaidToRecipient recipient;
  final int? rank;
  final double? share;
  final PaidToSort sort;
  final DateTime today;
  final void Function(FocusNode row) onTap;

  @override
  State<PaidToRecipientRow> createState() => _PaidToRecipientRowState();
}

class _PaidToRecipientRowState extends State<PaidToRecipientRow> {
  final _focus = FocusNode(debugLabel: 'paidToRow');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String _last(DateTime at) {
    final d = dateOnly(at);
    if (d == widget.today) return 'today';
    if (d == addDays(widget.today, -1)) return 'yesterday';
    return fmtDayMonth(d);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final g = widget.recipient;
    final share = widget.share;
    final rank = widget.rank;
    final color = palette.typeColor(g.sourceType);
    final feeNote = g.feeCents > 0 ? '+ ${kshTrim(g.feeCents)} fee' : '';
    final (main, second) = switch (widget.sort) {
      PaidToSort.timesPaid => ('${g.count}×', '${kshTrim(g.totalCents)}${feeNote.isEmpty ? '' : ' · $feeNote'}'),
      PaidToSort.fees => (
        formatKsh(g.feeCents),
        '${g.count}× · ${kshTrim(g.totalCents)} ${g.sourceType == paidToWithdrawal ? 'withdrawn' : 'paid'}',
      ),
      _ => (formatKsh(g.totalCents), '${g.count}×${feeNote.isEmpty ? '' : ' · $feeNote'}'),
    };
    final last = _last(g.lastAt);
    final sub = 'Last $last${g.detail.isNotEmpty ? ' · ${g.detail}' : ''}';
    final small = TextStyle(fontSize: 11, color: palette.mutedInk, fontFeatures: tabularFigures);

    final top = LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          TypeIconTile(code: g.sourceType, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                ),
                const SizedBox(height: 1),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // The amount column keeps its natural width but never takes more than ~60% of the row
          // (a very long second line ends in an ellipsis instead of pushing the name out).
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: box.maxWidth * 0.6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  main,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 1),
                Text(second, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
              ],
            ),
          ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        top,
        if (share != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(3)),
            child: Container(
              height: 5,
              color: palette.track,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: share.clamp(0.0, 1.0),
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return Semantics(
      button: true,
      label:
          '${g.name}, ${formatKsh(g.totalCents)}, ${g.count} ${paidToPayWord(g.sourceType, g.count)}, '
          'Transaction cost ${formatKsh(g.feeCents)}, last $last. Show details',
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        child: InkWell(
          focusNode: _focus,
          onTap: () => widget.onTap(_focus),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
            child: rank == null
                ? body
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 34,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 14),
                          child: Center(
                            child: Text(
                              '$rank',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFeatures: tabularFigures,
                                color: palette.mutedInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: body),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
