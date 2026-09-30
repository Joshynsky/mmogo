import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import 'analytics_view.dart';
import 'format.dart';

/// §ANALYTICS.BY_TYPE — the segmented By type | Where it went switch (mock
/// `.bswitch`), and below it the By type tile grid.
class AnalyticsBreakdownSwitch extends StatelessWidget {
  const AnalyticsBreakdownSwitch({super.key, required this.palette, required this.whereTab, required this.onChanged});

  final AppPalette palette;
  final bool whereTab;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = palette.brightness == Brightness.dark;
    Widget tab(String label, bool where) {
      final on = whereTab == where;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            key: Key(where ? 'analyticsTabWhere' : 'analyticsTabType'),
            onTap: () => onChanged(where),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? (dark ? palette.primary : palette.card) : Colors.transparent,
                borderRadius: const BorderRadius.all(Radius.circular(9)),
                boxShadow: on && !dark
                    ? const [BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))]
                    : null,
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: on ? (dark ? palette.onPrimary : palette.ink) : palette.softInk,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: palette.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Row(children: [tab('By type', false), tab('Where it went', true)]),
    );
  }
}

/// The By type panel: respects an active classification filter.
class AnalyticsTypePanel extends StatelessWidget {
  const AnalyticsTypePanel({
    super.key,
    required this.palette,
    required this.view,
    required this.typeFilter,
    required this.classFilter,
    required this.onToggleType,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final String? typeFilter;
  final String? classFilter;
  final ValueChanged<String> onToggleType;

  @override
  Widget build(BuildContext context) {
    final v = view;
    final total = v.totalCents;
    // T26: respects an active classification filter (the amounts within
    // that class), so By-type stays consistent with the transactions list.
    final byType = [
      for (final (code, _) in analyticsTypeOrder)
        v.inc
            .where((r) => r.sourceType == code)
            .where((r) => classFilter == null || r.classificationName == classFilter)
            .fold<int>(0, (s, r) => s + r.amountCents),
    ];
    Widget tile(int i) {
      final (code, name) = analyticsTypeOrder[i];
      final on = typeFilter == code;
      final pct = total > 0 ? '${(byType[i] / total * 100).round()}%' : '—';
      return _TypeTile(
        key: Key('analyticsTypeTile-$code'),
        palette: palette,
        color: palette.typeColor(code),
        name: name,
        percent: pct,
        amount: formatKsh(byType[i]),
        pressed: on,
        faded: typeFilter != null && !on,
        semanticsLabel:
            '$name, ${formatKsh(byType[i])}. ${on ? 'Showing only these; tap to show all' : 'Tap to show only these'}',
        onTap: () => onToggleType(code),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: tile(0)),
            const SizedBox(width: 8),
            Expanded(child: tile(1)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: tile(2)),
            const SizedBox(width: 8),
            Expanded(child: tile(3)),
          ],
        ),
      ],
    );
  }
}

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    super.key,
    required this.palette,
    required this.color,
    required this.name,
    required this.percent,
    required this.amount,
    required this.pressed,
    required this.faded,
    required this.semanticsLabel,
    required this.onTap,
  });

  final AppPalette palette;
  final Color color;
  final String name;
  final String percent;
  final String amount;
  final bool pressed;
  final bool faded;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(14));
    final ink = pressed ? palette.tintInk : null;
    return Opacity(
      opacity: faded ? 0.5 : 1,
      child: Semantics(
        button: true,
        toggled: pressed,
        label: semanticsLabel,
        excludeSemantics: true,
        child: Material(
          color: pressed ? palette.tint : palette.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: pressed ? palette.primary : palette.line, width: 1.5),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 26,
                    decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.all(Radius.circular(5))),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ink ?? palette.softInk,
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              percent,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: ink ?? palette.mutedInk,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            amount,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              fontFeatures: tabularFigures,
                              color: ink ?? palette.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
