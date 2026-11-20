import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../widgets/pill_toast.dart';
import '../../../data/db/analytics_dao.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../domain/format/money.dart';
import '../../../domain/fuliza/fuliza_rebuild.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../analytics/edit_lock_parts.dart' show FulizaPaidInfo;
import '../analytics/edit_sheet.dart';
import '../analytics/sheet_parts.dart';
import 'fuliza_sections.dart';
import 'fuliza_source.dart';

/// §FULIZA.SCREEN — 0.2.0 S9: the Fuliza page (mock `plugins/fuliza.js` route `fuliza`). Summary (owing,
/// taken, repaid, cost), Fees, History by day, Related transactions, Events not matched, and what
/// "estimated" means. Fuliza is a loan: nothing here is spending.
///
/// The Related arrow ([FulizaRelatedRow.onShow]) pushes a SECOND Fuliza page with [focusCode] set: it scrolls
/// to that borrowing in History and lights it; Back returns to the first page where it was. Tapping a
/// row's body opens the normal edit sheet. Data: [FulizaSource.load] (in-memory fake until slice 12).
/// WORDING-DRAFT labels: "Fuliza", "Fees this period", "Access fees (1% of each borrowing)", "Daily fees
/// (estimated)", "Fuliza cost (estimated)", "Kept apart from Transaction cost on Home.", "History", "Related
/// transactions", "Events not matched to a spend", "What estimated means", the notes under them.
class FulizaScreen extends StatefulWidget {
  const FulizaScreen({super.key, this.db, this.loader, this.focusCode, this.openEdit});

  final Database? db;

  /// Test seam: replaces the database read.
  final Future<FulizaSnapshot?> Function()? loader;

  /// When set, History scrolls to this borrowing's code and lights it (opened from a Related arrow).
  final String? focusCode;

  /// Test seam: replaces the edit sheet when a spend is tapped.
  final Future<void> Function(AnalyticsTransactionRow tx)? openEdit;

  @override
  State<FulizaScreen> createState() => _FulizaScreenState();
}

class _FulizaScreenState extends State<FulizaScreen> {
  FulizaSnapshot? _snap;
  bool _loading = true;
  final _focusKey = GlobalKey(debugLabel: 'fulizaFocusEntry');
  bool _rebuilding = false;
  String? _rebuildLine;

  /// Rebuild from my messages: ADDS only (never deletes), then reloads. WORDING-DRAFT line.
  Future<void> _rebuild() async {
    if (_rebuilding) return;
    setState(() => _rebuilding = true);
    final added = await FulizaRebuild.run();
    if (!mounted) return;
    setState(() {
      _rebuilding = false;
      _rebuildLine = 'Added $added ${added == 1 ? 'record' : 'records'}. Only messages mmogo still holds can be used.'; // WORDING-DRAFT
    });
    await _load();
  }

  Widget _rebuildBlock(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton(
        key: const Key('fulizaRebuild'),
        onPressed: _rebuilding ? null : _rebuild,
        child: Text('Rebuild from my messages', style: TextStyle(color: p.mutedInk, fontSize: 12.5)), // WORDING-DRAFT
      ),
      if (_rebuildLine != null)
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _rebuildLine!,
              key: const Key('fulizaRebuildResult'),
              style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk),
            ),
          ),
        ),
    ],
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<FulizaSnapshot?> _read() async {
    final loader = widget.loader;
    if (loader != null) return loader();
    return FulizaSource.load(widget.db ?? await AppDatabase.instance.database);
  }

  Future<void> _load() async {
    final snap = await _read();
    if (!mounted) return;
    setState(() {
      _snap = snap;
      _loading = false;
    });
    if (widget.focusCode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _focusKey.currentContext;
        if (ctx != null && mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.4,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _edit(AnalyticsTransactionRow tx) async {
    if (widget.openEdit != null) {
      await widget.openEdit!(tx);
      return;
    }
    final db = widget.db ?? await AppDatabase.instance.database;
    if (!mounted) return;
    final p = AppPalette.of(context);
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (ctx) => Theme(
        data: analyticsPickerTheme(p),
        child: AnalyticsEditSheet(
          db: db,
          tx: tx,
          palette: p,
          fulizaPaid: _snap?.drawCentsFor(tx.displayCode) == null
              ? null
              : FulizaPaidInfo(drawCents: _snap!.drawCentsFor(tx.displayCode)!),
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result is AnalyticsDeleteRequest) {
      await TransactionDao.softDelete(db, id: tx.id);
    } else if (result is AnalyticsEditResult) {
      try {
        await TransactionDao.update(
          db,
          id: tx.id,
          amountCents: result.amountCents,
          transactionOccurredAt: result.transactionOccurredAt,
          classificationId: result.classificationId,
          counterpartyLabel: result.counterpartyLabel,
          counterpartyPhone: result.counterpartyPhone,
          paybillAccountNumber: result.paybillAccountNumber,
          transactionCostCents: result.transactionCostCents,
          agentNumber: result.agentNumber,
        );
      } on DatabaseException {
        if (!mounted) return;
        PillToast.show('Could not save the changes. If you fill in a name, fill in its phone or account number too.');
        return;
      }
    }
    await _load();
  }

  /// The Related arrow: a second Fuliza page on that borrowing. Back pops it.
  void _show(String code) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'fuliza-focus'),
        builder: (_) => FulizaScreen(db: widget.db, loader: widget.loader, focusCode: code, openEdit: widget.openEdit),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return SecondaryScaffold(title: 'Fuliza', followPalette: true, body: _body(p));
  }

  Widget _body(AppPalette p) {
    if (_loading) return Center(child: CircularProgressIndicator(color: p.primary));
    final snap = _snap;
    if (snap == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Nothing here yet. This page only exists after the first Fuliza message is recorded.',
            key: const Key('fulizaEmpty'),
            style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk),
          ),
          const SizedBox(height: 8),
          _rebuildBlock(p),
        ],
      );
    }
    final d = snap.data;
    final related = snap.related;
    final focusing = widget.focusCode != null && snap.drawCentsFor(widget.focusCode!) != null;
    Widget gap() => const SizedBox(height: 12);
    final banner = Container(
      key: const Key('fulizaFocusBanner'),
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: p.track, borderRadius: const BorderRadius.all(Radius.circular(10))),
      child: Semantics(
        liveRegion: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Showing this borrowing in the History',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: p.ink),
            ),
            Text('Press Back to return to Related transactions.', style: TextStyle(fontSize: 12, color: p.mutedInk)),
          ],
        ),
      ),
    );
    final list = ListView(
      key: const Key('fulizaScroll'),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        FulizaSummaryCard(palette: p, data: d),
        gap(),
        FulizaSection(
          palette: p,
          title: 'Fees this period',
          note: 'Kept apart from Transaction cost on Home.',
          children: [
            FulizaFigureLine(
              palette: p,
              label: 'Access fees (1% of each borrowing)',
              value: formatKsh(d.accessFeesCents),
            ),
            FulizaFigureLine(palette: p, label: 'Daily fees (estimated)', value: formatKsh(d.dailyFeesCents)),
            FulizaFigureLine(palette: p, label: 'Fuliza cost (estimated)', value: formatKsh(d.costCents), strong: true),
          ],
        ),
        gap(),
        FulizaSection(
          palette: p,
          title: 'History',
          note: 'Newest first. Tap a borrowing to open the spend it paid for.',
          children: [
            FulizaHistory(
              palette: p,
              data: d,
              spends: snap.spendsByCode,
              onOpenSpend: _edit,
              focusCode: widget.focusCode,
              focusKey: _focusKey,
            ),
          ],
        ),
        gap(),
        FulizaSection(
          palette: p,
          title: 'Related transactions',
          note: related.isEmpty
              ? null
              : '“On Fuliza” = all paid by Fuliza. “Part on Fuliza” = some from Fuliza, the rest from your own money.',
          children: [
            if (related.isEmpty)
              Text('None yet.', style: TextStyle(fontSize: 12.5, color: p.mutedInk))
            else ...[
              Text(
                '${related.length} ${related.length == 1 ? 'spend' : 'spends'} paid with Fuliza.',
                style: TextStyle(fontSize: 12.5, color: p.mutedInk),
              ),
              for (final tx in related)
                FulizaRelatedRow(
                  palette: p,
                  tx: tx,
                  drawCents: snap.drawCentsFor(tx.displayCode) ?? 0,
                  onOpen: () => _edit(tx),
                  onShow: () => _show(tx.displayCode),
                ),
            ],
          ],
        ),
        gap(),
        FulizaSection(
          palette: p,
          title: 'Events not matched to a spend',
          children: [
            Text(
              d.unmatchedCount == 0
                  ? 'None. Every borrowing matched a spend by its transaction code.'
                  : '${d.unmatchedCount} ${d.unmatchedCount == 1 ? 'borrowing is' : 'borrowings are'} waiting for their spend message.',
              key: const Key('fulizaUnmatched'),
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk),
            ),
          ],
        ),
        gap(),
        FulizaSection(
          palette: p,
          title: 'What “estimated” means',
          children: [
            Text(
              'The access fee is in the message, so it is exact. Safaricom sends no message for the daily fee. We work it out: the balance in the next Fuliza message (or the repayment) minus what we expected. So the daily fee shows late and can be a few shillings off.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk),
            ),
          ],
        ),
        gap(),
        _rebuildBlock(p),
      ],
    );
    // The banner stays pinned above the list so it is never scrolled out of sight.
    return focusing
        ? Column(
            children: [
              banner,
              Expanded(child: list),
            ],
          )
        : list;
  }
}
