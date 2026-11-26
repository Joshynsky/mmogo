/// §AUTOREAD.LEVELS.SETUP_TYPE_CHIPS: the payment type chips of the Set up sheet (0.2.2 item 2, slice U-SETUP;
/// mock-remembered-v2 setup-half / setup-sm / setup-pb / setup-bg). "All", then Send Money, Paybill, Buy Goods
/// and Pochi: one chosen at a time. A chip not chosen shows its short code; the chosen chip shows its name and
/// count (the change is in words, not colour only). Screen readers hear "{name}, {count}" and the chosen state.
/// PM Q3 (25-11): Airtime has no rule in 0.2.2, so its chip is only a LINK to the existing Airtime switches
/// ([SetupTypeChips.onAirtime]; null = no Airtime chip). Words come from hard_rule_copy.dart.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';

/// The chip of [t] in [kHardTypeChips]: (short code, name).
(String, String) setupTypeChip(ReceiverType t) => kHardTypeChips[switch (t) {
      ReceiverType.sendMoney => 0,
      ReceiverType.payBill => 1,
      ReceiverType.buyGoods => 2,
      ReceiverType.pochi => 3,
    }];

/// The Airtime chip: (short code, name).
(String, String) get setupAirtimeChip => kHardTypeChips[4];

/// The order of the type chips after "All".
const List<ReceiverType> kSetupChipTypes = [
  ReceiverType.sendMoney,
  ReceiverType.payBill,
  ReceiverType.buyGoods,
  ReceiverType.pochi,
];

class SetupTypeChips extends StatelessWidget {
  const SetupTypeChips({
    super.key,
    required this.selected,
    required this.counts,
    required this.total,
    required this.onSelect,
    this.onAirtime,
  });

  /// The chosen type; null = All.
  final ReceiverType? selected;

  /// How many listed rows each type has (after the search).
  final Map<ReceiverType, int> counts;

  /// How many rows All has (after the search).
  final int total;
  final ValueChanged<ReceiverType?> onSelect;

  /// Opens the existing Airtime switches; null hides the Airtime chip.
  final VoidCallback? onAirtime;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: kHardTypeChipsGroup,
      explicitChildNodes: true,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 2, 14, 4),
        child: Wrap(
          key: const Key('setupTypeChips'),
          spacing: 8,
          runSpacing: 8,
          children: [
            SetupTypeChip(
              key: const Key('setupType.all'),
              short: kHardTypeChipAll,
              name: kHardTypeChipAll,
              count: total,
              on: selected == null,
              onTap: () => onSelect(null),
            ),
            for (final t in kSetupChipTypes)
              SetupTypeChip(
                key: Key('setupType.${t.code}'),
                short: setupTypeChip(t).$1,
                name: setupTypeChip(t).$2,
                count: counts[t] ?? 0,
                on: selected == t,
                onTap: () => onSelect(selected == t ? null : t),
              ),
            if (onAirtime != null)
              SetupTypeChip(
                key: const Key('setupType.airtime'),
                short: setupAirtimeChip.$1,
                name: setupAirtimeChip.$2,
                on: false,
                link: true,
                onTap: onAirtime!,
              ),
          ],
        ),
      ),
    );
  }
}

/// One chip. [link]: opens somewhere else (Airtime); it shows an arrow and is announced as a link, never as
/// chosen.
class SetupTypeChip extends StatelessWidget {
  const SetupTypeChip({
    super.key,
    required this.short,
    required this.name,
    this.count,
    required this.on,
    this.link = false,
    required this.onTap,
  });

  final String short;
  final String name;
  final int? count;
  final bool on;
  final bool link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final fg = on ? p.onPrimary : p.ink;
    final visible = on && count != null ? '$name $count' : short;
    final spoken = count == null ? name : '$name, $count';
    return Semantics(
      button: !link,
      link: link,
      selected: link ? null : on,
      inMutuallyExclusiveGroup: !link,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: on ? p.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: on ? p.primary : p.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      visible,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg, height: 1.2),
                    ),
                  ),
                  if (link) ...[
                    const SizedBox(width: 4),
                    // arrow_forward follows the text direction (it points left in RTL).
                    Icon(Icons.arrow_forward, size: 16, color: fg),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
