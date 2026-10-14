import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import '../../widgets/tap_target.dart';
import 'analytics_filters.dart';
import 'analytics_view.dart';
import 'categories_sheet.dart';
import 'format.dart';
import 'type_strip.dart';

/// §ANALYTICS.BY_TYPE — the tab row: the segmented By type | Where it went
/// switch (mock `.tabs`) filling the row, and at its right end the Categories
/// button (Where it went tab, Button style only; M1b-final). On By type the
/// 44 px slot stays, empty, so the switch keeps one width on both tabs; in the
/// Strip style there is no slot. Below it, the By type tile strip.
class AnalyticsBreakdownSwitch extends StatelessWidget {
  const AnalyticsBreakdownSwitch({
    super.key,
    required this.palette,
    required this.whereTab,
    required this.onChanged,
    this.showButtonSlot = false,
    this.categoriesAvailable = 0,
    this.categoriesSelected = 0,
    this.onCategories,
  });

  final AppPalette palette;
  final bool whereTab;
  final ValueChanged<bool> onChanged;

  /// Button style: reserve the slot at the right end of the row.
  final bool showButtonSlot;
  final int categoriesAvailable;
  final int categoriesSelected;
  final VoidCallback? onCategories;

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

    final tabs = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: palette.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Row(children: [tab('By type', false), tab('Where it went', true)]),
    );
    if (!showButtonSlot) return tabs;
    return Row(
      children: [
        Expanded(child: tabs),
        const SizedBox(width: 8),
        SizedBox(
          width: kMinTapTarget,
          height: kMinTapTarget,
          child: whereTab
              ? AnalyticsCategoriesButton(
                  palette: palette,
                  available: categoriesAvailable,
                  selected: categoriesSelected,
                  onTap: onCategories ?? () {},
                )
              : null,
        ),
      ],
    );
  }
}

/// The By type panel: respects the class set; a tile toggles its type in or
/// out of the type set.
class AnalyticsTypePanel extends StatelessWidget {
  const AnalyticsTypePanel({
    super.key,
    required this.palette,
    required this.view,
    required this.filters,
    required this.onToggleType,
  });

  final AppPalette palette;
  final AnalyticsView view;
  final AnalyticsFilters filters;
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
            .where(filters.matchesClass)
            .fold<int>(0, (s, r) => s + (code == 'AGENT_WITHDRAWAL' ? r.withdrawn : r.spent)),
    ];
    // The share base: the whole period's spending, or (a type set picked) the
    // picked types' own total; the others show a dash.
    final base = typeShareBase(filters, {for (var i = 0; i < analyticsTypeOrder.length; i++) analyticsTypeOrder[i].$1: byType[i]}, total);
    Widget tile(int i) {
      final (code, name) = analyticsTypeOrder[i];
      final on = filters.types.contains(code);
      // Withdrawal is tracked, not spent (S4a rule): it adds 0 to spent, so
      // its tile reads "tracked" instead of a percentage.
      final withdrawal = code == 'AGENT_WITHDRAWAL';
      final pct = typeShareText(filters, code, byType[i], base);
      // The Withdrawal tile shows the cash withdrawn in the period ('Ksh 0.00'
      // only when there is none), muted, with 'tracked' in place of a percent.
      // It is never added to the spent total or to another tile's percentage.
      final shown = byType[i];
      final tap = on ? 'Selected; tap to remove from the selection' : 'Tap to add to the selection';
      return _TypeTile(
        key: Key('analyticsTypeTile-$code'),
        palette: palette,
        color: palette.typeColor(code),
        name: name,
        percent: pct,
        amount: formatKsh(shown),
        mutedAmount: withdrawal,
        pressed: on,
        faded: filters.types.isNotEmpty && !on,
        semanticsLabel: withdrawal
            ? '$name, ${formatKsh(shown)} withdrawn. Tracked, not spending. $tap'
            : '$name, ${formatKsh(shown)}. $tap',
        onTap: () => onToggleType(code),
      );
    }

    // The signed mock's strip: two rows, the four 0.1.1 tiles in columns 1-2,
    // Pochi over Withdrawal in column 3, Airtime in column 4 (order =
    // sourceTypeOrder).
    return AnalyticsTypeStrip(
      palette: palette,
      columns: [
        [tile(0), tile(2)],
        [tile(1), tile(3)],
        [tile(4), tile(5)],
        [tile(6)],
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
    this.mutedAmount = false,
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

  /// Withdrawal: only the amount text is muted (mock `.tile.wd b`).
  final bool mutedAmount;
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
                              fontWeight: mutedAmount ? FontWeight.w700 : FontWeight.w800,
                              fontFeatures: tabularFigures,
                              color: ink ?? (mutedAmount ? palette.mutedInk : palette.ink),
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
