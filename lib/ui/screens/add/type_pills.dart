import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';
import 'form_row.dart';

/// §ADD.TYPES — the six M-Pesa type pills (0.1.2 S8c-1, AD1): SM, PB, BG, P, W, A
/// in the mock's order, always visible. The selected pill shows the type's NAME
/// in its type colour (the mock renders the name only: code plus name did not
/// fit 360 dp); the others show the short code. Each pill is a 44 dp tap target,
/// its screen-reader label and tooltip are the FULL name, and a locked row
/// (after a parse) keeps all six visible, the parsed one open, the others dimmed
/// but readable and ignoring taps. The row only scrolls sideways as a fallback
/// at a large text scale.
class TypePills extends StatefulWidget {
  const TypePills({super.key, required this.type, required this.onChanged, this.locked = false});

  /// A `transactions.source_type` of the six M-Pesa types, or null while a
  /// name-only message has no type yet (0.1.2 S8c-2: all six show their code).
  final String? type;
  final ValueChanged<String> onChanged;

  /// True after a parse: taps are ignored until Start over.
  final bool locked;

  /// (source_type, full name, short code), in display order.
  static const options = [
    ('SEND_MONEY', 'Send Money', 'SM'),
    ('PAYBILL', 'Paybill', 'PB'),
    ('BUY_GOODS', 'Buy Goods', 'BG'),
    ('POCHI_LA_BIASHARA', 'Pochi', 'P'),
    ('AGENT_WITHDRAWAL', 'Withdrawal', 'W'),
    ('AIRTIME', 'Airtime', 'A'),
  ];

  @override
  State<TypePills> createState() => _TypePillsState();

  static Widget orDivider(AppPalette palette) {
    final style = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: palette.mutedInk);
    return Builder(
      builder: (context) {
        // The text can't wrap between the two divider lines, so at a large
        // phone font it stands alone, centred, without them.
        if (MediaQuery.textScalerOf(context).scale(1) >= AddFormRow.stackAbove) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Center(child: Text('or enter it yourself', textAlign: TextAlign.center, style: style)),
          );
        }
        return Row(
          children: [
            Expanded(child: Divider(color: palette.line)),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('or enter it yourself', style: style)),
            Expanded(child: Divider(color: palette.line)),
          ],
        );
      },
    );
  }
}

class _TypePillsState extends State<TypePills> {
  final _keys = {for (final o in TypePills.options) o.$1: GlobalKey()};

  @override
  void initState() {
    super.initState();
    _scrollSelectedIntoView();
  }

  @override
  void didUpdateWidget(TypePills old) {
    super.didUpdateWidget(old);
    if (old.type != widget.type) _scrollSelectedIntoView();
  }

  /// A parsed SMS switches the pill; make sure it can be seen (only matters
  /// when the row scrolls, at a large text scale).
  void _scrollSelectedIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = widget.type == null ? null : _keys[widget.type]?.currentContext;
      if (!mounted || ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.5, duration: Duration.zero);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SingleChildScrollView(
      key: const Key('addTypePills'),
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in TypePills.options)
            KeyedSubtree(
              key: _keys[o.$1],
              child: _pill(palette, type: o.$1, name: o.$2, code: o.$3),
            ),
        ],
      ),
    );
  }

  Widget _pill(AppPalette palette, {required String type, required String name, required String code}) {
    final selected = widget.type == type;
    final locked = widget.locked;
    final tc = palette.typePillFill(type); // S11b: the pill fill, so the tint matches typePillInk
    final Color fill;
    final Color border;
    final Color ink;
    if (selected) {
      fill = palette.typePillFill(type);
      border = fill;
      ink = palette.typePillText(type);
    } else if (locked) {
      fill = palette.surface; // dimmed but readable: muted ink on the surface, no opacity
      border = palette.line;
      ink = palette.mutedInk;
    } else {
      fill = Color.alphaBlend(tc.withValues(alpha: 0.10), palette.surface);
      border = Color.alphaBlend(tc.withValues(alpha: 0.45), palette.line);
      ink = palette.typePillInk(type, page: palette.surface);
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: !locked,
      label: name,
      excludeSemantics: true,
      onTap: locked ? null : () => widget.onChanged(type),
      child: Tooltip(
        message: name,
        child: TapTarget(
          key: Key('addTypePill_$type'),
          expandWidth: false,
          onTap: locked ? null : () => widget.onChanged(type),
          // 3 px each side INSIDE the tap box: the gap between pills is also tap
          // area, so a coded pill (38 dp at least) is 44 dp wide to the finger.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              constraints: const BoxConstraints(minWidth: 38),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                selected ? name : code,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
