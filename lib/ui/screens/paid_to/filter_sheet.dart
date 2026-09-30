import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';

/// §PAIDTO.FILTER_SHEET — the Filter & sort sheet (mock `#pSheet`): category (scoped to the type,
/// each with its payment count), sort, Reset, and "Show N recipients". A
/// draft until Show; pops `(category, sort)`.
class PaidToFilterSheet extends StatefulWidget {
  const PaidToFilterSheet({
    super.key,
    required this.palette,
    required this.payments,
    required this.type,
    required this.cls,
    required this.sort,
  });

  final AppPalette palette;
  final List<PaidToPayment> payments;
  final String? type;
  final String? cls;
  final PaidToSort sort;

  @override
  State<PaidToFilterSheet> createState() => _PaidToFilterSheetState();
}

class _PaidToFilterSheetState extends State<PaidToFilterSheet> {
  late String? _cls = widget.cls;
  late PaidToSort _sort = widget.sort;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final cats = paidToCategories(widget.payments, type: widget.type);
    final all = cats.fold<int>(0, (s, c) => s + c.$2);
    final n = countPaidToRecipients(widget.payments, type: widget.type, classification: _cls);
    final label = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.66, color: p.mutedInk);

    Widget catRow(String? cls, String name, int count, bool first) {
      final on = _cls == cls;
      return Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? p.tint : p.card,
          child: InkWell(
            key: Key('paidToCat-${cls ?? 'all'}'),
            onTap: () => setState(() => _cls = cls),
            child: Container(
              decoration: BoxDecoration(
                border: first ? null : Border(top: BorderSide(color: p.line)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? p.tintInk : p.ink),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$count payment${count == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.mutedInk),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget sortChip(PaidToSort s) {
      final on = _sort == s;
      const pill = BorderRadius.all(Radius.circular(999));
      return Semantics(
        button: true,
        selected: on,
        child: Material(
          color: on ? p.primary : p.card,
          shape: RoundedRectangleBorder(
            borderRadius: pill,
            side: BorderSide(color: on ? p.primary : p.line, width: 1.5),
          ),
          child: InkWell(
            key: Key('paidToSort-${s.name}'),
            customBorder: const RoundedRectangleBorder(borderRadius: pill),
            onTap: () => setState(() => _sort = s),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(
                paidToSortLabels[s]!,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on ? p.onPrimary : p.ink),
              ),
            ),
          ),
        ),
      );
    }

    Widget action(Key key, String text, Color bg, Color fg, VoidCallback onTap) => Expanded(
      child: SizedBox(
        height: 42,
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );

    final children = <Widget>[
      Text(
        'Filter & sort',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
      ),
      Text.rich(
        TextSpan(
          style: label,
          children: [
            const TextSpan(text: 'CATEGORY '),
            TextSpan(
              text: widget.type == null ? '· all types' : '· in ${sourceTypeName(widget.type!)}',
              style: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      Container(
        constraints: const BoxConstraints(maxHeight: 196),
        decoration: BoxDecoration(
          border: Border.all(color: p.line),
          borderRadius: const BorderRadius.all(Radius.circular(12)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              catRow(null, 'All categories', all, true),
              for (final (name, count) in cats) catRow(name, name, count, false),
            ],
          ),
        ),
      ),
      Text('SORT BY', style: label),
      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in PaidToSort.values) sortChip(s)]),
      Row(
        children: [
          action(const Key('paidToReset'), 'Reset', p.track, p.ink, () {
            setState(() {
              _cls = null;
              _sort = PaidToSort.amount;
            });
          }),
          const SizedBox(width: 8),
          action(
            const Key('paidToShow'),
            'Show $n recipient${n == 1 ? '' : 's'}',
            p.primary,
            p.onPrimary,
            () => Navigator.of(context).pop((_cls, _sort)),
          ),
        ],
      ),
    ];

    return BottomSheetShell(palette: p, children: children);
  }
}
