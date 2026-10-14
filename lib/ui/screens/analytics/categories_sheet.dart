import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import '../../widgets/tap_target.dart';

/// §ANALYTICS.CATEGORIES — the Categories button (right end of the tab row,
/// Where it went tab only) and the Categories sheet it opens (0.1.2 S6c, MS1;
/// mock M1b-final / M1b-multi).
///
/// The grid button: a 32 px face with the grid icon and a count badge in a
/// 44 px tap area (TS1; the mock's slot is 40). [selected] is how many
/// categories are in the filter set; [available] how many there are to choose.
class AnalyticsCategoriesButton extends StatelessWidget {
  const AnalyticsCategoriesButton({super.key, required this.palette, required this.available, required this.selected, required this.onTap});

  final AppPalette palette;
  final int available;
  final int selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = available > 0;
    final on = selected > 0 && enabled;
    final label = !enabled
        ? 'Choose categories, nothing to choose in this period'
        : 'Choose categories, ${selected > 0 ? '$selected selected' : 'none selected'}';
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: TapTarget(
          onTap: enabled ? onTap : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: on ? palette.tint : palette.card,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                  side: BorderSide(color: on ? palette.primary : palette.line, width: 1.5),
                ),
                child: InkWell(
                  key: const Key('analyticsCategoriesButton'),
                  customBorder: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
                  onTap: enabled ? onTap : null,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Icon(Icons.grid_view_rounded, size: 16, color: on ? palette.tintInk : palette.ink),
                  ),
                ),
              ),
              if (on)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    key: const Key('analyticsCategoriesBadge'),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: palette.primary,
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      border: Border.all(color: palette.card, width: 1.5),
                    ),
                    child: Text(
                      '$selected',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, height: 1, color: palette.onPrimary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Categories sheet. It works on a DRAFT copy of the set: rows tick and
/// untick, the sheet stays open. Pops with
///  - the draft set on Apply (only when it differs from [selected]),
///  - an empty set on Clear (applies at once),
///  - `null` on Close, scrim tap or Back (the draft is thrown away).
class AnalyticsCategoriesSheet extends StatefulWidget {
  const AnalyticsCategoriesSheet({super.key, required this.palette, required this.ranking, required this.selected});

  final AppPalette palette;

  /// The period's categories, largest first.
  final List<NamedSpend> ranking;

  /// The committed set.
  final Set<String> selected;

  @override
  State<AnalyticsCategoriesSheet> createState() => _AnalyticsCategoriesSheetState();
}

class _AnalyticsCategoriesSheetState extends State<AnalyticsCategoriesSheet> {
  late Set<String> _draft = {...widget.selected};
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  bool get _pending => _draft.length != widget.selected.length || _draft.any((c) => !widget.selected.contains(c));

  void _toggle(String name) => setState(() => _draft = _draft.contains(name) ? ({..._draft}..remove(name)) : {..._draft, name});

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final all = widget.ranking;
    final big = all.length > 8;
    final q = _query.text.trim().toLowerCase();
    final items = [
      for (final g in all)
        if (q.isEmpty || g.name.toLowerCase().contains(q)) g,
    ];
    final max = all.isEmpty || all.first.cents < 1 ? 1 : all.first.cents;
    final total = all.fold<int>(0, (s, g) => s + g.cents);
    final n = _draft.length;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Categories (${all.length})',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink),
                          ),
                          Text(
                            'Total of these: ${kshTrim(total)} in this period',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mutedInk),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      key: const Key('analyticsCatClose'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: p.primary,
                        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Close'),
                    ),
                  ],
                ),
                if (big) ...[
                  const SizedBox(height: 10),
                  TextField(
                    key: const Key('analyticsCatSearch'),
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    style: TextStyle(fontSize: 13, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search categories',
                      hintStyle: TextStyle(color: p.mutedInk),
                      filled: true,
                      fillColor: p.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: p.line, width: 1.5),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(10)),
                        borderSide: BorderSide(color: p.line, width: 1.5),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Flexible(
                  child: items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No category matches.',
                            key: const Key('analyticsCatNone'),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12.5, color: p.mutedInk),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final g in items)
                              _CatRow(
                                key: Key('analyticsCatRow-${g.name}'),
                                palette: p,
                                spend: g,
                                share: g.cents / max,
                                ticked: _draft.contains(g.name),
                                onTap: () => _toggle(g.name),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _pill(
                      const Key('analyticsCatClear'),
                      'Clear',
                      p.track,
                      p.ink,
                      (n == 0 && widget.selected.isEmpty) ? null : () => Navigator.of(context).pop(<String>{}),
                    ),
                    const SizedBox(width: 8),
                    _pill(
                      const Key('analyticsCatApply'),
                      n > 0 ? 'Apply ($n)' : 'Close',
                      p.primary,
                      p.onPrimary,
                      () => Navigator.of(context).pop(n > 0 && _pending ? _draft : null),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pill(Key key, String label, Color bg, Color fg, VoidCallback? onTap) => Expanded(
    child: SizedBox(
      height: 44,
      child: FilledButton(
        key: key,
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: bg.withValues(alpha: 0.5),
          disabledForegroundColor: fg.withValues(alpha: 0.7),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        child: Text(label),
      ),
    ),
  );
}

class _CatRow extends StatelessWidget {
  const _CatRow({super.key, required this.palette, required this.spend, required this.share, required this.ticked, required this.onTap});

  final AppPalette palette;
  final NamedSpend spend;
  final double share;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = ticked ? palette.tintInk : null;
    final amount = formatKsh(spend.cents);
    return Semantics(
      checked: ticked,
      label: '${spend.name}, ${spend.count} transaction${spend.count == 1 ? '' : 's'}, $amount',
      excludeSemantics: true,
      child: Material(
        color: ticked ? palette.tint : Colors.transparent,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    key: Key('analyticsCatTick-${spend.name}'),
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: ticked ? palette.primary : Colors.transparent,
                      borderRadius: const BorderRadius.all(Radius.circular(6)),
                      border: Border.all(color: ticked ? palette.primary : palette.mutedInk, width: 1.5),
                    ),
                    child: ticked ? Icon(Icons.check_rounded, size: 13, color: palette.onPrimary) : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                spend.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ink ?? palette.ink),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${spend.count}×',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: ink ?? palette.mutedInk),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              amount,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                fontFeatures: tabularFigures,
                                color: ink ?? palette.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
