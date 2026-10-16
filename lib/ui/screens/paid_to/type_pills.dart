import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_counts.dart';
import '../../theme/app_colors.dart';

/// The short code on a collapsed pill (mock `SC`).
String paidToTypeCode(String type) => switch (type) {
  'SEND_MONEY' => 'SM',
  'PAYBILL' => 'PB',
  'BUY_GOODS' => 'BG',
  paidToPochi => 'P',
  _ => 'W',
};

/// §PAIDTO.TYPES — the expand/collapse type pills (mock `renderPills`): All | SM | PB | BG | P | W
/// in the type colours. Only the selected pill shows its full name and count; All shows ONLY the
/// recipient count ("All 14"), W its agents; the aria (semantics) label carries the full wording
/// ("N recipients, M agents"). The strip scrolls sideways and keeps the open pill in view. The
/// counts follow the search and the category, like the sections ([counts] is
/// `paidToCounts(payments, classification, term)`).
class PaidToTypePills extends StatefulWidget {
  const PaidToTypePills({
    super.key,
    required this.palette,
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final AppPalette palette;
  final PaidToCounts counts;

  /// The selected type; `null` = All.
  final String? selected;
  final void Function(String? type) onSelect;

  @override
  State<PaidToTypePills> createState() => _PaidToTypePillsState();
}

class _PaidToTypePillsState extends State<PaidToTypePills> {
  final _keys = <String?, GlobalKey>{};

  GlobalKey _keyOf(String? t) => _keys.putIfAbsent(t, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(PaidToTypePills old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _revealSelected();
  }

  /// The open pill scrolls into view in the sideways strip (mock: 14 px of margin).
  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keyOf(widget.selected).currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: const Duration(milliseconds: 180));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.counts;
    final tabs = <(String?, String)>[(null, 'All'), for (final t in paidToAllTypes) (t, sourceTypeName(t))];
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
              anchorKey: _keyOf(type),
              palette: widget.palette,
              type: type,
              label: label,
              code: type == null ? 'All' : paidToTypeCode(type),
              // The open pill's number: All = recipients only; a type = its own count.
              short: type == null ? '${c.rec}' : '${c.by[type]}',
              full: paidToCountLabel(c, tab: type),
              selected: widget.selected == type,
              onTap: () => widget.onSelect(type),
            ),
          ],
        ],
      ),
    );
  }
}

/// One pill (mock `.pt-pill`): collapsed = the code in the type colour on a 10% tint; open = the
/// name and the count on the solid type colour.
class _TypePill extends StatelessWidget {
  const _TypePill({
    super.key,
    required this.anchorKey,
    required this.palette,
    required this.type,
    required this.label,
    required this.code,
    required this.short,
    required this.full,
    required this.selected,
    required this.onTap,
  });

  final GlobalKey anchorKey;
  final AppPalette palette;
  final String? type;
  final String label;
  final String code;
  final String short;
  final String full;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const pill = BorderRadius.all(Radius.circular(999));
    final pc = type == null ? palette.primary : palette.typePillFill(type!);
    final onPc = type == null ? palette.onPrimary : palette.typePillText(type!);
    final ink = type == null ? palette.ink : palette.typePillInk(type!, page: palette.card);
    final fg = selected ? onPc : ink;
    return Semantics(
      selected: selected,
      button: true,
      label: '$label, $full',
      excludeSemantics: true,
      child: Material(
        key: anchorKey,
        color: selected ? pc : Color.alphaBlend(pc.withValues(alpha: 0.10), palette.card),
        shape: RoundedRectangleBorder(
          borderRadius: pill,
          side: BorderSide(
            color: selected ? pc : Color.alphaBlend(pc.withValues(alpha: 0.45), palette.line),
            width: 1.5,
          ),
        ),
        child: InkWell(
          customBorder: const RoundedRectangleBorder(borderRadius: pill),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: selected ? 11 : 9, vertical: 7),
            child: selected
                ? Text.rich(
                    TextSpan(
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                      children: [
                        TextSpan(text: label),
                        TextSpan(
                          text: ' $short',
                          style: TextStyle(fontWeight: FontWeight.w600, color: fg), // S11b: full colour, 80% failed 4.5:1
                        ),
                      ],
                    ),
                  )
                : Text(
                    code,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.24, color: fg),
                  ),
          ),
        ),
      ),
    );
  }
}
