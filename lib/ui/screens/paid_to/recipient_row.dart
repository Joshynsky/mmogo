import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import '../../widgets/type_icon.dart';
import 'format.dart';

/// §PAIDTO.ROW — one recipient row (mock `.prow`): rank, type tile, name + "Last (date) ·
/// phone/acc", amount + "n× · fees X", and a share bar under it. Unnamed
/// rows (T15): italic muted name, a muted tile with a person icon.
class PaidToRecipientRow extends StatelessWidget {
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
  final VoidCallback onTap;

  String _last(DateTime at) {
    final d = dateOnly(at);
    if (d == today) return 'today';
    if (d == addDays(today, -1)) return 'yesterday';
    return fmtDayMonth(d);
  }

  @override
  Widget build(BuildContext context) {
    final g = recipient;
    final color = palette.typeColor(g.sourceType);
    final fees = 'fees ${paidToPlain(g.feeCents)}';
    final byCount = sort == PaidToSort.timesPaid;
    final main = byCount ? '${g.count}×' : formatKsh(g.totalCents);
    final second = byCount ? '${kshTrim(g.totalCents)} · $fees' : '${g.count}× · $fees';
    final last = _last(g.lastAt);
    final sub = 'Last $last${g.detail.isNotEmpty ? ' · ${g.detail}' : ''}';
    final small = TextStyle(fontSize: 11, color: palette.mutedInk, fontFeatures: tabularFigures);

    final top = Row(
      children: [
        if (g.isUnnamed)
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: palette.track, borderRadius: const BorderRadius.all(Radius.circular(11))),
            child: Icon(Icons.person_outline_rounded, size: 18, color: palette.mutedInk),
          )
        else
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: g.isUnnamed ? FontWeight.w600 : FontWeight.w700,
                  fontStyle: g.isUnnamed ? FontStyle.italic : FontStyle.normal,
                  color: g.isUnnamed ? palette.softInk : palette.ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              main,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: tabularFigures,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(second, style: small),
          ],
        ),
      ],
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
                widthFactor: share!.clamp(0.0, 1.0),
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
          '${g.name}, ${formatKsh(g.totalCents)}, ${g.count} payment${g.count == 1 ? '' : 's'}, '
          'fees ${formatKsh(g.feeCents)}, last $last. Show every payment',
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        child: InkWell(
          onTap: onTap,
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
