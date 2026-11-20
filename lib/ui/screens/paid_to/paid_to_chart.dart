import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to_account_view.dart';
import '../../../domain/paid_to/paid_to_sheet.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';
import 'account_shade.dart';
import 'pager_dots.dart';

/// §PAIDTO.CHART — the recipient sheet's bar chart (0.2.1 #4, MK-12). Plain single-colour bars as
/// built; for a Paybill name with several accounts each bar is STACKED, one segment per account in
/// its [paidToAccountShade] (one account chosen = only its segments). A Year or Month chart fits the
/// width. An All time chart longer than one window ([PaidToSheetData.window] months) is a row of
/// WINDOWS: swipe sideways (it snaps window by window, the latest in view), dots and a range line
/// ("Aug to Nov 2026") say where you are; no arrows. Only the chart itself scrolls sideways; a
/// vertical drag on it still scrolls the sheet.
/// WORDING-DRAFT: "swipe the chart", the window labels ("Aug to Nov 2026", "Window n of N").
class PaidToChart extends StatefulWidget {
  const PaidToChart({super.key, required this.palette, required this.data, required this.color});

  final AppPalette palette;
  final PaidToSheetData data;

  /// The single bar colour (the type's), used when a bar has no account segments.
  final Color color;

  @override
  State<PaidToChart> createState() => _PaidToChartState();
}

class _PaidToChartState extends State<PaidToChart> {
  late final PageController _pages = PageController(initialPage: _count - 1);
  late int _page = _count - 1;

  int get _w => widget.data.window;
  int get _count => _w == 0 ? 1 : widget.data.bars.length ~/ _w;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Widget _bar(PaidToBar b, int maxBar) {
    final p = widget.palette;
    final data = widget.data;
    final h = b.cents > 0 ? math.max(3.0, b.cents / maxBar * 70) : 2.0;
    Widget body;
    if (b.pad) {
      body = const SizedBox.shrink();
    } else if (b.cents > 0 && b.segments.isNotEmpty) {
      // Lowest index (biggest account) at the bottom: the Column lists top to bottom.
      final segs = b.segments.reversed.toList();
      body = Container(
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        constraints: const BoxConstraints(maxWidth: 48),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          child: Column(
            children: [
              for (final (j, s) in segs.indexed)
                Expanded(
                  flex: math.max(1, s.$2),
                  child: Container(
                    decoration: BoxDecoration(
                      color: paidToAccountShade(p, s.$1),
                      border: j == 0 ? null : Border(top: BorderSide(color: p.ink.withValues(alpha: 0.3))),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      body = Container(
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: b.cents > 0 ? widget.color : p.track,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      );
    }
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (data.valueLabels && b.cents > 0)
            Text(
              paidToCompact(b.cents),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                height: 1.2,
                fontFeatures: tabularFigures,
                color: p.softInk,
              ),
            ),
          body,
          SizedBox(
            height: 14,
            child: Text(
              b.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: TextStyle(fontSize: 9.5, color: p.mutedInk),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(List<PaidToBar> bars, int maxBar) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [for (final b in bars) _bar(b, maxBar)],
  );

  String _windowLabel(int k) => paidToWindowLabel(widget.data.bars.sublist(k * _w, (k + 1) * _w));

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final data = widget.data;
    final maxBar = data.bars.fold<int>(1, (m, b) => math.max(m, b.cents));
    final summary = [
      for (final b in data.bars)
        if (b.cents > 0) '${b.label} ${formatKsh(b.cents)}',
    ].join(', ');
    // Grows with the text size so the value labels never overflow the bars' column.
    final double height = 96.0 * math.max(1.0, MediaQuery.textScalerOf(context).scale(1));
    final chart = _w == 0
        ? _row(data.bars, maxBar)
        : PageView.builder(
            key: const Key('paidToChartPages'),
            controller: _pages,
            itemCount: _count,
            onPageChanged: (k) => setState(() => _page = k),
            itemBuilder: (_, k) => _row(data.bars.sublist(k * _w, (k + 1) * _w), maxBar),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          image: true,
          label: summary,
          excludeSemantics: true,
          child: SizedBox(key: const Key('paidToSheetChart'), height: height, child: chart),
        ),
        if (_w != 0) ...[
          PaidToPagerDots(
            palette: p,
            count: _count,
            current: _page,
            keyPrefix: 'paidToChartDot-',
            labelOf: (k) => 'Window ${k + 1} of $_count, ${_windowLabel(k)}',
            onTap: (k) => _pages.animateToPage(k, duration: const Duration(milliseconds: 220), curve: Curves.easeOut),
          ),
          Text(
            '${_windowLabel(_page)} · swipe the chart',
            key: const Key('paidToChartRange'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: p.mutedInk),
          ),
        ],
      ],
    );
  }
}
