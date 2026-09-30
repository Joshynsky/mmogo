import 'package:flutter/material.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/removable_chip.dart';
import '../../widgets/tabular.dart';
import 'analytics_view.dart';
import 'parts.dart';
import 'swipe_row.dart';

/// §ANALYTICS.TX_LIST — the transactions section: heading with filter chips,
/// day groups of swipe rows (or the empty card) and the swipe hint footer.
/// Returns a list, not a widget: the shell splices these into its spaced
/// column (the heading, the groups and the footer are separate children).
/// [rowKeyFor] is the shell's `_rowKeys.putIfAbsent` (keys are created in the
/// shell's build, never in the row).
List<Widget> analyticsTransactionSections({
  required AppPalette palette,
  required AnalyticsView view,
  required String? typeFilter,
  required String? classFilter,
  required int? highlightedId,
  required int? openRowId,
  required GlobalKey Function(int id) rowKeyFor,
  required void Function(int id, bool open) onOpened,
  required void Function(AnalyticsTransactionRow tx) onEdit,
  required void Function(AnalyticsTransactionRow tx) onDelete,
  required VoidCallback onClearType,
  required VoidCallback onClearClass,
}) {
  final v = view;
  // T26 "yes allow type and category": both can be active; the list shows
  // the AND of the two.
  final typeName = typeFilter != null ? sourceTypeName(typeFilter) : null;
  final className = classFilter;
  final fNames = [?typeName, ?className];
  final list = [
    for (final r in v.inc)
      if ((typeFilter == null || r.sourceType == typeFilter) &&
          (classFilter == null || r.classificationName == classFilter))
        r,
  ];
  final subtotal = list.fold<int>(0, (s, r) => s + r.amountCents);
  final subtotalLabel = kshTrim(subtotal);

  final heading = ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 30),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        children: [
          Text(
            'TRANSACTIONS',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: palette.mutedInk),
          ),
          const SizedBox(width: 8),
          const Spacer(),
          if (typeName != null)
            Flexible(
              flex: 8,
              child: Align(
                alignment: Alignment.centerRight,
                child: RemovableChip(
                  inkKey: const Key('analyticsFilterChipType'),
                  palette: palette,
                  label: '$typeName · $subtotalLabel',
                  semanticsLabel: 'Clear the $typeName filter',
                  onTap: onClearType,
                ),
              ),
            ),
          if (typeName != null && className != null) const SizedBox(width: 6),
          if (className != null)
            Flexible(
              flex: 8,
              child: Align(
                alignment: Alignment.centerRight,
                child: RemovableChip(
                  inkKey: const Key('analyticsFilterChipClass'),
                  palette: palette,
                  label: '$className · $subtotalLabel',
                  semanticsLabel: 'Clear the $className filter',
                  onTap: onClearClass,
                ),
              ),
            ),
        ],
      ),
    ),
  );

  final out = <Widget>[heading];
  if (list.isEmpty) {
    out.add(
      AppCard(
        palette: palette,
        child: AnalyticsEmpty(
          palette: palette,
          text: 'No ${fNames.isEmpty ? '' : '${fNames.join(' ')} '}transactions in this period.',
        ),
      ),
    );
  } else {
    final groups = <List<AnalyticsTransactionRow>>[];
    for (final r in list) {
      if (groups.isNotEmpty && sameDay(groups.last.first.occurredAt, r.occurredAt)) {
        groups.last.add(r);
      } else {
        groups.add([r]);
      }
    }
    final today = v.today;
    final txs = <Widget>[];
    for (final g in groups) {
      final d = g.first.occurredAt;
      final label = sameDay(d, today)
          ? 'Today'
          : sameDay(d, addDays(today, -1))
          ? 'Yesterday'
          : '${weekdayShort(d)}, ${fmtDayMonth(d)}${d.year != today.year ? ' ${d.year}' : ''}';
      txs.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 6, 2, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.mutedInk),
                ),
              ),
              Text(
                formatKsh(g.fold<int>(0, (s, r) => s + r.amountCents)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  fontFeatures: tabularFigures,
                  color: palette.softInk,
                ),
              ),
            ],
          ),
        ),
      );
      txs.add(
        AppCard(
          palette: palette,
          clip: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < g.length; i++) ...[
                if (i > 0) Container(height: 1, color: palette.line),
                AnalyticsSwipeRow(
                  key: ValueKey(g[i].id),
                  rowKey: rowKeyFor(g[i].id),
                  palette: palette,
                  tx: g[i],
                  highlighted: highlightedId == g[i].id,
                  forceClosed: openRowId != g[i].id,
                  onOpened: (open) => onOpened(g[i].id, open),
                  onEdit: () => onEdit(g[i]),
                  onDelete: () => onDelete(g[i]),
                ),
              ],
            ],
          ),
        ),
      );
    }
    out.add(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: txs));
  }
  out.add(
    Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        'Swipe a row right to edit, left to delete',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: palette.mutedInk),
      ),
    ),
  );
  return out;
}
