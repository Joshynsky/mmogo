import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/tabular.dart';
import 'analytics_view.dart';
import 'parts.dart';

/// §ANALYTICS.WHERE — the "Where it went" panel: classification totals with
/// share bars; respects an active type filter.
class AnalyticsWherePanel extends StatelessWidget {
  const AnalyticsWherePanel({
    super.key,
    required this.palette,
    required this.view,
    required this.typeFilter,
    required this.classFilter,
    required this.showAll,
    required this.onToggleClass,
    required this.onToggleShowAll,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final String? typeFilter;
  final String? classFilter;
  final bool showAll;
  final ValueChanged<String> onToggleClass;
  final VoidCallback onToggleShowAll;

  @override
  Widget build(BuildContext context) {
    final v = view;
    // T26: respects an active type filter (only that type's classifications).
    final inc = typeFilter == null ? v.inc : v.inc.where((r) => r.sourceType == typeFilter);
    final groups = groupSpendByName(inc.map((r) => (r.classificationName, r.amountCents)));
    const limit = 4;
    final shown = showAll ? groups : groups.take(limit).toList();
    final max = groups.isEmpty ? 1 : math.max(groups.first.cents, 1);
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      final g = shown[i];
      if (i > 0) children.add(Container(height: 1, color: palette.line));
      children.add(
        _WhereRow(
          key: Key('analyticsWhere-${g.name}'),
          palette: palette,
          spend: g,
          share: g.cents / max,
          pressed: classFilter == g.name,
          onTap: () => onToggleClass(g.name),
        ),
      );
    }
    if (groups.length > limit) {
      children.add(Container(height: 1, color: palette.line));
      children.add(
        InkWell(
          key: const Key('analyticsWhereMore'),
          onTap: onToggleShowAll,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              showAll ? 'Show fewer' : 'Show all ${groups.length}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.primary),
            ),
          ),
        ),
      );
    }
    return AppCard(
      palette: palette,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: groups.isEmpty
          ? AnalyticsEmpty(palette: palette, text: 'Nothing to break down in this period.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _WhereRow extends StatelessWidget {
  const _WhereRow({
    super.key,
    required this.palette,
    required this.spend,
    required this.share,
    required this.pressed,
    required this.onTap,
  });

  final AppPalette palette;
  final NamedSpend spend;
  final double share;
  final bool pressed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = pressed ? palette.tintInk : palette.ink;
    return Semantics(
      button: true,
      toggled: pressed,
      child: Material(
        color: pressed ? palette.tint : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: spend.name,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink),
                          children: [
                            const WidgetSpan(child: SizedBox(width: 4)),
                            TextSpan(
                              text: '${spend.count}×',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.mutedInk),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatKsh(spend.cents),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabularFigures,
                        color: ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                  child: Container(
                    height: 6,
                    color: palette.track,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: share.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.primary,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(3)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
