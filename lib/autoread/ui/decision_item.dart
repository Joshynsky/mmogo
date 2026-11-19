/// §AUTOREAD.DECISION_ITEM (0.2.1) - the ONE To do item "N withdrawals need a decision" and its
/// Review sheet. Every recorded withdrawal that is neither Cash only nor categorized waits here
/// (fed by `LinkedCashDao.undecidedWithdrawals`, no date limit); each row has two side-by-side
/// buttons, Cash only | Categorize (filled like Parse). The item counts as ONE row in To
/// categorize. No Details / Remove: a withdrawal here is already recorded. Autoread build only.
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../domain/format/money.dart';
import '../../ui/copy/withdrawal_copy.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/error_notes.dart';
import '../../ui/widgets/two_button_dialog.dart';
import 'notifications_autoread_copy.dart' show kActionCategorize;

/// The item card in To categorize: title with the count, one grey line, Review.
class DecisionItem extends StatelessWidget {
  const DecisionItem({super.key, required this.count, required this.onReview});

  final int count;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      container: true,
      label: '${wdDecisionTitle(count)}. $kWdDecisionHelp',
      child: Container(
        key: const Key('decision-item'),
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(wdDecisionTitle(count), style: TextStyle(color: p.ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(kWdDecisionHelp, style: TextStyle(color: p.mutedInk, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const Key('decision-review'),
                onPressed: onReview,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  backgroundColor: p.primary,
                  foregroundColor: p.onPrimary,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                child: const Text(kWdDecisionReview),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Review sheet: [rows] is the live list (a row leaves it once decided; the sheet closes when none is left).
Future<void> showDecisionReview(
  BuildContext context, {
  required ValueListenable<List<AnalyticsTransactionRow>> rows,
  required Future<void> Function(AnalyticsTransactionRow row) onCashOnly,
  required Future<void> Function(AnalyticsTransactionRow row) onCategorize,
  Future<void> Function(List<AnalyticsTransactionRow> rows)? onCashOnlyAll,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DecisionReviewSheet(rows: rows, onCashOnly: onCashOnly, onCategorize: onCategorize, onCashOnlyAll: onCashOnlyAll),
  );
}

class DecisionReviewSheet extends StatefulWidget {
  const DecisionReviewSheet({super.key, required this.rows, required this.onCashOnly, required this.onCategorize, this.onCashOnlyAll});

  final ValueListenable<List<AnalyticsTransactionRow>> rows;
  final Future<void> Function(AnalyticsTransactionRow row) onCashOnly;
  final Future<void> Function(AnalyticsTransactionRow row) onCategorize;

  /// Null: no "Cash only for all" button. Shown only while two or more withdrawals wait.
  final Future<void> Function(List<AnalyticsTransactionRow> rows)? onCashOnlyAll;

  @override
  State<DecisionReviewSheet> createState() => _DecisionReviewSheetState();
}

class _DecisionReviewSheetState extends State<DecisionReviewSheet> {
  String? _error;
  bool _busy = false;

  Future<void> _all(List<AnalyticsTransactionRow> list) async {
    if (_busy) return;
    final ok = await showTwoButtonDialog(
      context,
      title: wdCashOnlyAllTitle(list.length),
      body: kWdCashOnlyAllBody,
      leftLabel: kWdCashOnlyAllCancel,
      rightLabel: kWdCashOnlyAll,
    );
    if (ok != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCashOnlyAll!(list);
    } catch (_) {
      if (mounted) setState(() => _error = kWdCashOnlyAllError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _when(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}, '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
      child: Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: ValueListenableBuilder<List<AnalyticsTransactionRow>>(
          valueListenable: widget.rows,
          builder: (context, list, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          list.isEmpty ? kWdDecisionDone : wdDecisionTitle(list.length),
                          key: const Key('decision-sheet-title'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('decision-close'),
                      tooltip: 'Close',
                      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      icon: Icon(Icons.close, color: p.ink),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(kWdDecisionReviewHelp, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
                    ),
                    if (widget.onCashOnlyAll != null && list.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            key: const Key('decision-cash-all'),
                            onPressed: _busy ? null : () => _all(list),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: p.ink,
                              side: BorderSide(color: p.mutedInk),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                            child: const Text(kWdCashOnlyAll),
                          ),
                        ),
                      ),
                    if (_error != null) FieldError(_error!, padding: const EdgeInsets.only(bottom: 8)),
                    for (final r in list)
                      Container(
                        key: Key('decision-row-${r.id}'),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Withdrew ${kshTrim(r.amountCents)}${(r.counterpartyLabel ?? '').isEmpty ? '' : ' from ${r.counterpartyLabel}'}',
                              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.ink),
                            ),
                            const SizedBox(height: 2),
                            Text(_when(r.occurredAt), style: TextStyle(fontSize: 12, color: p.mutedInk)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _Btn(key: Key('decision-cash-${r.id}'), label: kWdTodoRowCashOnly, onTap: () => widget.onCashOnly(r))),
                                const SizedBox(width: 8),
                                Expanded(child: _Btn(key: Key('decision-cat-${r.id}'), label: kActionCategorize, fill: true, onTap: () => widget.onCategorize(r))),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({super.key, required this.label, required this.onTap, this.fill = false});
  final String label;
  final VoidCallback onTap;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SizedBox(
      height: 44,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: fill ? p.primary : p.track,
          foregroundColor: fill ? p.onPrimary : p.ink,
          shape: const StadiumBorder(),
          textStyle: TextStyle(fontSize: 13, fontWeight: fill ? FontWeight.w800 : FontWeight.w700),
        ),
        child: Text(label),
      ),
    );
  }
}
