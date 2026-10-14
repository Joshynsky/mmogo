import 'package:flutter/material.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/analytics/chart_blocks.dart' show WhereItWentStyle;
import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/tabular.dart';
import 'analytics_filters.dart';
import 'parts.dart';

/// "Where it went": the period's spending by category, largest first. Follows
/// the type SET (only those types' rows); a row that adds nothing to spent (a
/// withdrawal) is not "where it went". The same name under two types counts
/// as one.
List<NamedSpend> analyticsWhereRanking(Iterable<AnalyticsTransactionRow> inc, AnalyticsFilters filters) =>
    groupSpendByName(
      inc.where((r) => filters.matchesType(r) && r.spent > 0).map((r) => (r.classificationName, r.spent)),
    );

String _countWords(int n) => '$n transaction${n == 1 ? '' : 's'}';

/// §ANALYTICS.WHERE — the "Where it went" panel. Button style (default): a
/// ranked top-3 preview (tap toggles the category in the set) and "N
/// categories", which opens the Categories sheet. Strip style: two rows of
/// compact cards (top 6 by amount) and "See all N" when there are more.
class AnalyticsWherePanel extends StatelessWidget {
  const AnalyticsWherePanel({
    super.key,
    required this.palette,
    required this.ranking,
    required this.filters,
    required this.style,
    required this.onToggleClass,
    required this.onOpenSheet,
  });

  final AppPalette palette;

  /// [analyticsWhereRanking] of the period.
  final List<NamedSpend> ranking;
  final AnalyticsFilters filters;
  final WhereItWentStyle style;
  final ValueChanged<String> onToggleClass;
  final VoidCallback onOpenSheet;

  @override
  Widget build(BuildContext context) {
    if (ranking.isEmpty) {
      return AppCard(
        palette: palette,
        child: AnalyticsEmpty(palette: palette, text: 'Nothing to break down in this period.'),
      );
    }
    final max = ranking.first.cents < 1 ? 1 : ranking.first.cents;
    Widget card(NamedSpend g, {required bool strip}) {
      final on = filters.classes.contains(g.name);
      return _WhereCard(
        key: Key('analyticsWhere-${g.name}'),
        palette: palette,
        spend: g,
        share: g.cents / max,
        selected: on,
        faded: strip && filters.classes.isNotEmpty && !on,
        compact: strip,
        onTap: () => onToggleClass(g.name),
      );
    }

    if (style == WhereItWentStyle.strip) {
      final top = ranking.take(6).toList();
      final more = ranking.length > 6;
      return LayoutBuilder(
        builder: (context, c) {
          final w = (c.maxWidth - 16) / 2.5;
          Widget col(List<Widget> cards) => SizedBox(
            width: w,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 8), cards[i]],
              ],
            ),
          );
          final cols = <Widget>[
            for (var i = 0; i < top.length; i += 2)
              col([card(top[i], strip: true), if (i + 1 < top.length) card(top[i + 1], strip: true)]),
            if (more)
              SizedBox(
                width: w,
                child: _SeeAllCard(palette: palette, count: ranking.length, onTap: onOpenSheet),
              ),
          ];
          return SingleChildScrollView(
            key: const Key('analyticsWhereStrip'),
            scrollDirection: Axis.horizontal,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < cols.length; i++) ...[if (i > 0) const SizedBox(width: 8), cols[i]],
                ],
              ),
            ),
          );
        },
      );
    }

    final top3 = ranking.take(3).toList();
    final n = ranking.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < top3.length; i++) ...[if (i > 0) const SizedBox(height: 6), card(top3[i], strip: false)],
        Semantics(
          button: true,
          label: 'See all $n categor${n == 1 ? 'y' : 'ies'}',
          excludeSemantics: true,
          child: InkWell(
            key: const Key('analyticsWhereCount'),
            onTap: onOpenSheet,
            borderRadius: const BorderRadius.all(Radius.circular(10)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '$n categor${n == 1 ? 'y' : 'ies'}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.mutedInk),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One category: a preview row (Button style) or a compact card (Strip).
/// Name, "n x", amount and a share bar; selected = tinted.
class _WhereCard extends StatelessWidget {
  const _WhereCard({
    super.key,
    required this.palette,
    required this.spend,
    required this.share,
    required this.selected,
    required this.faded,
    required this.compact,
    required this.onTap,
  });

  final AppPalette palette;
  final NamedSpend spend;
  final double share;
  final bool selected;
  final bool faded;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = selected ? palette.tintInk : null;
    const radius = BorderRadius.all(Radius.circular(14));
    final amount = formatKsh(spend.cents);
    final name = Text(
      spend.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: compact ? 12 : 12.5, fontWeight: FontWeight.w700, color: ink ?? palette.softInk),
    );
    final times = Text(
      '${spend.count}×',
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: ink ?? palette.mutedInk),
    );
    final amountText = Text(
      amount,
      maxLines: 1,
      style: TextStyle(
        fontSize: compact ? 13.5 : 13,
        fontWeight: FontWeight.w800,
        fontFeatures: tabularFigures,
        color: ink ?? palette.ink,
      ),
    );
    final bar = ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(3)),
      child: Container(
        height: compact ? 6 : 5,
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
    );
    final Widget body = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [Expanded(child: name), const SizedBox(width: 6), times]),
              const SizedBox(height: 3),
              FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: amountText),
              const SizedBox(height: 5),
              bar,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: name),
                  const SizedBox(width: 8),
                  times,
                  const SizedBox(width: 8),
                  amountText,
                ],
              ),
              const SizedBox(height: 4),
              bar,
            ],
          );
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Semantics(
        button: true,
        toggled: selected,
        label:
            '${spend.name}, ${_countWords(spend.count)}, $amount. '
            '${selected ? 'Selected; tap to remove from the selection' : 'Tap to add to the selection'}',
        excludeSemantics: true,
        child: Material(
          color: selected ? palette.tint : palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: compact ? radius : const BorderRadius.all(Radius.circular(12)),
            side: BorderSide(color: selected ? palette.primary : palette.line, width: 1.5),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: compact ? radius : const BorderRadius.all(Radius.circular(12)),
            ),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 9 : 7),
                child: Center(child: body),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Strip style's last card: "See all N", spanning both rows.
class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard({required this.palette, required this.count, required this.onTap});

  final AppPalette palette;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));
    return Semantics(
      button: true,
      label: 'See all $count categories',
      excludeSemantics: true,
      child: Material(
        color: palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: palette.line, width: 1.5),
        ),
        child: InkWell(
          key: const Key('analyticsWhereSeeAll'),
          customBorder: const RoundedRectangleBorder(borderRadius: radius),
          onTap: onTap,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See all $count',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: palette.primary),
                ),
                const SizedBox(height: 4),
                Icon(Icons.chevron_right_rounded, size: 18, color: palette.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
