import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';

/// §PAIDTO.TYPES — the type pills: All | Send Money | Paybill | Buy Goods, each with a recipient count.
class PaidToTypePills extends StatelessWidget {
  const PaidToTypePills({
    super.key,
    required this.palette,
    required this.payments,
    required this.selected,
    required this.onSelect,
  });

  final AppPalette palette;
  final List<PaidToPayment> payments;

  /// The selected type; `null` = All.
  final String? selected;
  final void Function(String? type) onSelect;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String?, String)>[(null, 'All'), for (final t in paidToTypes) (t, sourceTypeName(t))];
    return SingleChildScrollView(
      key: const Key('paidToTypePills'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          for (final (i, (type, label)) in tabs.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            _TypePill(
              key: Key('paidToTab-${type ?? 'all'}'),
              palette: palette,
              label: label,
              count: countPaidToRecipients(payments, type: type),
              selected: selected == type,
              onTap: () => onSelect(type),
            ),
          ],
        ],
      ),
    );
  }
}

/// One type pill (mock `.ppills button`): label + a faded recipient count.
class _TypePill extends StatelessWidget {
  const _TypePill({
    super.key,
    required this.palette,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const pill = BorderRadius.all(Radius.circular(999));
    final fg = selected ? palette.onPrimary : palette.ink;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label, $count recipient${count == 1 ? '' : 's'}',
      excludeSemantics: true,
      child: Material(
        color: selected ? palette.primary : palette.card,
        shape: RoundedRectangleBorder(
          borderRadius: pill,
          side: BorderSide(color: selected ? palette.primary : palette.line, width: 1.5),
        ),
        child: InkWell(
          customBorder: const RoundedRectangleBorder(borderRadius: pill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg),
                children: [
                  TextSpan(text: '$label '),
                  TextSpan(
                    text: '$count',
                    style: TextStyle(fontWeight: FontWeight.w600, color: fg.withValues(alpha: 0.65)),
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
