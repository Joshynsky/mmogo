import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../../domain/format/money.dart';
import '../../../domain/format/source_types.dart';
import '../../../domain/paid_to/paid_to.dart';
import '../../../domain/paid_to/paid_to_sheet.dart';
import '../../theme/app_colors.dart';
import '../../widgets/bottom_sheet_shell.dart';
import '../../widgets/tabular.dart';
import '../../widgets/type_icon.dart';
import 'accounts_block.dart';
import 'paid_to_chart.dart';

/// §PAIDTO.SHEET — the recipient sheet INSIDE Paid to (mock `openRecipient`): header (tile, name,
/// "Type · detail", close X), the combined-numbers note when more than one stored phone form, a 2x2
/// grid (Total paid / Total withdrawn for an agent, Payments / Withdrawals, Average, Transaction
/// cost), First and Last payment, a bar chart ([PaidToChart]: PER 7 DAYS for Month, PER MONTH for
/// Year and All time) and BY CATEGORY rows, then the Analytics ("See in Analytics") and Close
/// buttons side by side. Figures are the row's own (shown period, the row's category filter).
/// Closed by Close, the X, a scrim tap or Back.
///
/// 0.2.1 #4 (MK-12): a Paybill name with several accounts lets you tap an account row to see it
/// alone: a "Showing" chip says which, "All accounts" goes back, the grid, First / Last, chart and
/// BY CATEGORY follow the choice (the ACCOUNTS list and Total row stay combined), and "See in
/// Analytics" is on only while one account is chosen (a line above the buttons says why).
/// Pops a [PaidToSheetExit] when "See in Analytics" was chosen, else `null`.
Future<PaidToSheetExit?> showPaidToRecipientSheet(
  BuildContext context, {
  required AppPalette palette,
  required PaidToRecipient recipient,
  required PaidToSheetData data,
  required String periodWords,
  PaidToSheetData Function(int? account)? dataFor,
}) {
  return showModalBottomSheet<PaidToSheetExit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true, // keep the header (title, Delete) below the status bar
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.35),
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => PaidToRecipientSheet(
      palette: palette,
      recipient: recipient,
      data: data,
      periodWords: periodWords,
      dataFor: dataFor,
    ),
  );
}

/// What the sheet hands back for "See in Analytics": [account] = the one account chosen (a Paybill
/// name with several accounts), else null.
class PaidToSheetExit {
  const PaidToSheetExit({this.account});

  final String? account;
}

class PaidToRecipientSheet extends StatefulWidget {
  const PaidToRecipientSheet({
    super.key,
    required this.palette,
    required this.recipient,
    required this.data,
    required this.periodWords,
    this.dataFor,
  });

  final AppPalette palette;
  final PaidToRecipient recipient;

  /// The figures for all accounts.
  final PaidToSheetData data;
  final String periodWords;

  /// The figures for one account (an index into `recipient.accounts`); null = no account choosing.
  final PaidToSheetData Function(int? account)? dataFor;

  @override
  State<PaidToRecipientSheet> createState() => _PaidToRecipientSheetState();
}

class _PaidToRecipientSheetState extends State<PaidToRecipientSheet> {
  int? _sel;

  bool get _canPick => widget.dataFor != null && widget.recipient.hasManyAccounts;
  PaidToSheetData get _data => _sel == null ? widget.data : widget.dataFor!(_sel);
  String? get _account => _sel == null ? null : widget.recipient.accounts[_sel!].account;
  String get _accountName => (_account ?? '').isEmpty ? 'No account saved' : _account!;

  static String _date(DateTime d) => '${fmtDayMonth(d)} ${d.year}';

  // The two buttons share one row (equal widths, 8 px apart, each at least 44 px high). The label
  // may wrap to two lines at large text; the screen-reader label keeps the full sentence.
  Widget _action(Key key, String text, Color bg, Color fg, VoidCallback? onTap, {String? semantics}) => Expanded(
    child: Semantics(
      label: semantics,
      button: semantics != null ? true : null,
      excludeSemantics: semantics != null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: 0.45),
            disabledForegroundColor: fg.withValues(alpha: 0.8),
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.2),
          ),
          child: Text(text, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ),
      ),
    ),
  );

  /// "Showing: all accounts" / "Showing: account X" and the "All accounts" button (mock `m12-show`).
  Widget _showing() {
    final p = widget.palette;
    final one = _sel != null;
    return Row(
      children: [
        Expanded(
          child: Container(
            key: const Key('paidToShowingChip'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
            child: Semantics(
              liveRegion: true,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(fontSize: 12, color: p.mutedInk),
                  children: [
                    const TextSpan(text: 'Showing: '), // WORDING-DRAFT
                    if (one) ...[
                      const TextSpan(text: 'account '), // WORDING-DRAFT
                      TextSpan(
                        text: _accountName,
                        style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
                      ),
                    ] else
                      const TextSpan(text: 'all accounts'), // WORDING-DRAFT
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          key: const Key('paidToAllAccounts'),
          onPressed: one ? () => setState(() => _sel = null) : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            foregroundColor: p.primary,
            side: BorderSide(color: one ? p.primary : p.line, width: 1.5),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
          child: const Text('All accounts'), // WORDING-DRAFT
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final g = widget.recipient;
    final data = _data;
    final w = g.sourceType == paidToWithdrawal;
    final col = p.typeColor(g.sourceType);
    final label = TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.66, color: p.mutedInk);

    Widget stat(String l, String v) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(12))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.toUpperCase(),
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.42, color: p.mutedInk),
          ),
          const SizedBox(height: 1),
          Text(
            v,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, fontFeatures: tabularFigures, color: p.ink),
          ),
        ],
      ),
    );

    Widget date(String l, String v, CrossAxisAlignment a) => Column(
      crossAxisAlignment: a,
      children: [
        Text(l, style: TextStyle(fontSize: 12, color: p.mutedInk)),
        Text(
          v,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
        ),
      ],
    );

    return BottomSheetShell(
      palette: p,
      children: [
        Row(
          children: [
            TypeIconTile(code: g.sourceType, color: col),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.name,
                    key: const Key('paidToSheetName'),
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink),
                  ),
                  Text(
                    '${sourceTypeName(g.sourceType)}${g.detail.isNotEmpty ? ' · ${g.detail}' : ''}',
                    style: TextStyle(fontSize: 11, color: p.mutedInk),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: 'Close',
              excludeSemantics: true,
              child: Material(
                color: p.track,
                shape: const CircleBorder(),
                child: InkWell(
                  key: const Key('paidToSheetX'),
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.of(context).pop(),
                  child: SizedBox(width: 34, height: 34, child: Icon(Icons.close_rounded, size: 16, color: p.ink)),
                ),
              ),
            ),
          ],
        ),
        if (g.phones.length > 1)
          Text(
            'Combined numbers (as stored): ${g.phones.join(' · ')}',
            key: const Key('paidToSheetCombined'),
            style: TextStyle(fontSize: 11.5, height: 1.4, color: p.mutedInk),
          ),
        if (_canPick) _showing(),
        // The 2x2 grid (two rows of two equal boxes, as tall as their text needs).
        Column(
          children: [
            Row(
              children: [
                Expanded(child: stat(w ? 'Total withdrawn' : 'Total paid', formatKsh(data.totalCents))),
                const SizedBox(width: 8),
                Expanded(child: stat(w ? 'Withdrawals' : 'Payments', '${data.count}')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: stat('Average', formatKsh(data.averageCents))),
                const SizedBox(width: 8),
                Expanded(child: stat('Transaction cost', formatKsh(data.feeCents))),
              ],
            ),
          ],
        ),
        Row(
          children: [
            Expanded(child: date('First payment', _date(data.first), CrossAxisAlignment.start)),
            const SizedBox(width: 8),
            Expanded(child: date('Last payment', _date(data.last), CrossAxisAlignment.end)),
          ],
        ),
        Text.rich(
          key: const Key('paidToSheetChartTitle'),
          TextSpan(
            style: label,
            children: [
              TextSpan(text: data.perWeek ? 'PER 7 DAYS ' : 'PER MONTH '),
              TextSpan(
                text: '· ${widget.periodWords}${data.perWeek ? ' (days 1–7, 8–14 ...)' : ''}',
                style: const TextStyle(letterSpacing: 0, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        PaidToChart(palette: p, data: data, color: col),
        // 0.2.0 S8: a Paybill name with several accounts lists them, in pages of 5 above 5.
        if (g.hasManyAccounts)
          PaidToAccountsBlock(
            palette: p,
            recipient: g,
            selected: _sel,
            onSelect: _canPick ? (i) => setState(() => _sel = i) : null,
          ),
        Text('BY CATEGORY', style: label),
        Column(
          children: [
            for (final (i, c) in data.categories.indexed)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                ),
                child: Row(
                  key: Key('paidToSheetCat-${c.name}'),
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        c.name,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${c.count}× · ${kshTrim(c.cents)}',
                      style: TextStyle(fontSize: 12, fontFeatures: tabularFigures, color: p.mutedInk),
                    ),
                  ],
                ),
              ),
          ],
        ),
        // Several accounts under one name and none chosen yet: the line says why the button is off.
        if (g.hasManyAccounts)
          Text(
            _sel == null
                ? 'Pick one account to open it in Analytics' // WORDING-DRAFT
                : 'Opens account $_accountName in Analytics', // WORDING-DRAFT
            key: const Key('paidToAnalyticsWhy'),
            style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk),
          ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Several accounts: the button works while one account is chosen (Analytics' party
              // view is one name + account). Without choosing support (no [dataFor]) it stays off.
              if (!g.hasManyAccounts || _canPick) ...[
                _action(
                  const Key('paidToSheetAnalytics'),
                  'See in Analytics',
                  p.primary,
                  p.onPrimary,
                  g.hasManyAccounts && _sel == null
                      ? null
                      : () => Navigator.of(context).pop(PaidToSheetExit(account: _account)),
                  semantics: 'See these payments in Analytics',
                ),
                const SizedBox(width: 8),
              ],
              _action(const Key('paidToSheetClose'), 'Close', p.track, p.ink, () => Navigator.of(context).pop()),
            ],
          ),
        ),
      ],
    );
  }
}
