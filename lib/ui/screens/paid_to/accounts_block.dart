import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_pages.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tabular.dart';

/// §PAIDTO.ACCOUNTS — 0.2.0 S8 (PM 03-11-2026): the ACCOUNTS block of a Paybill name with several
/// accounts, inside the recipient sheet. Up to 5 accounts are listed; more are PAGES of 5 records,
/// scrolled sideways and snapping to a page, with dots and "Page n of N" and NO Next / Previous
/// buttons (the pattern of Analytics' By type strip, `type_strip.dart`). A Total row closes the block.
/// WORDING-DRAFT labels: "ACCOUNTS", "under this name, biggest first", "No account saved", "Total",
/// "N accounts", "Page n of N", "swipe sideways", "no fee", "fee X", "Last".
class PaidToAccountsBlock extends StatefulWidget {
  const PaidToAccountsBlock({super.key, required this.palette, required this.recipient});

  final AppPalette palette;
  final PaidToRecipient recipient;

  @override
  State<PaidToAccountsBlock> createState() => _PaidToAccountsBlockState();
}

class _PaidToAccountsBlockState extends State<PaidToAccountsBlock> {
  final _controller = ScrollController();
  int _page = 0;
  double _pageW = 0;
  late final List<PaidToAccount> _accounts = widget.recipient.accounts;

  int get _pages => paidToPageCount(_accounts.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    if (!_controller.hasClients || _pageW <= 0) return;
    _controller.animateTo(page * _pageW, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  bool _onScroll(ScrollNotification n) {
    final p = n.metrics;
    final page = paidToPageAt(p.pixels, _pageW, _pages);
    if (page != _page) setState(() => _page = page);
    if (n is ScrollEndNotification && _pageW > 0) {
      final target = (page * _pageW).clamp(0.0, p.maxScrollExtent);
      if ((p.pixels - target).abs() > 0.5) {
        // Deferred like the By type strip: the end notification arrives while the activity is replaced.
        Future.microtask(() {
          if (mounted && _controller.hasClients) {
            _controller.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
          }
        });
      }
    }
    return false;
  }

  Color _shade(int i) {
    final p = widget.palette;
    return i < 6 ? Color.lerp(p.typePaybill, p.card, i * 0.13)! : p.line;
  }

  Widget _amounts(int cents, int fee) {
    final p = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          kshTrim(cents),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, fontFeatures: tabularFigures, color: p.ink),
        ),
        Text(
          fee > 0 ? 'fee ${kshTrim(fee)}' : 'no fee',
          style: TextStyle(fontSize: 11, fontFeatures: tabularFigures, color: p.mutedInk),
        ),
      ],
    );
  }

  Widget _row(PaidToAccount a, int i) {
    final p = widget.palette;
    final sub = '${a.count} ${a.count == 1 ? 'payment' : 'payments'} · Last ${fmtDayMonth(a.last)} ${a.last.year}';
    return Container(
      key: Key('paidToAccount-$i'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: i % paidToPageSize == 0 ? null : Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: _shade(i), shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.account.isEmpty ? 'No account saved' : a.account,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                ),
                Text(sub, style: TextStyle(fontSize: 11, color: p.mutedInk)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _amounts(a.totalCents, a.feeCents),
        ],
      ),
    );
  }

  Widget _total() {
    final p = widget.palette;
    final r = widget.recipient;
    return Container(
      key: const Key('paidToAccountsTotal'),
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                ),
                Text(
                  '${_accounts.length} accounts · ${r.count} payments',
                  style: TextStyle(fontSize: 11, color: p.mutedInk),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _amounts(r.totalCents, r.feeCents),
        ],
      ),
    );
  }

  Widget _dot(int k) {
    final p = widget.palette;
    final on = k == _page;
    return Semantics(
      button: true,
      selected: on,
      label: paidToPageLabel(k, _pages),
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('paidToAccountsDot-$k'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _goTo(k),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: on ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: on ? p.primary : p.line,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pager() {
    final p = widget.palette;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            _pageW = c.maxWidth;
            return NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Semantics(
                container: true,
                label: 'Accounts, ${paidToPageLabel(_page, _pages).toLowerCase()}, swipe sideways',
                child: SingleChildScrollView(
                  key: const Key('paidToAccountsPager'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var k = 0; k < _pages; k++)
                        SizedBox(
                          key: Key('paidToAccountsPage-$k'),
                          width: c.maxWidth,
                          child: Column(
                            children: [
                              for (final (j, a) in paidToPageItems(_accounts, k).indexed)
                                _row(a, k * paidToPageSize + j),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Wrap(alignment: WrapAlignment.center, children: [for (var k = 0; k < _pages; k++) _dot(k)]),
        Text(
          '${paidToPageLabel(_page, _pages)} · swipe sideways',
          key: const Key('paidToAccountsPageLabel'),
          style: TextStyle(fontSize: 11.5, color: p.mutedInk),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final n = _accounts.length;
    return Column(
      key: const Key('paidToAccounts'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.66, color: p.mutedInk),
            children: [
              const TextSpan(text: 'ACCOUNTS '),
              TextSpan(
                text: '· $n under this name, biggest first',
                style: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (paidToNeedsPages(n)) _pager() else ...[for (final (i, a) in _accounts.indexed) _row(a, i)],
        _total(),
      ],
    );
  }
}
