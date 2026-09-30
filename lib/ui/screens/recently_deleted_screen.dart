import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/app_database.dart';
import '../../data/db/recently_deleted_dao.dart';
import '../../data/db/transaction_dao.dart';
import '../../domain/format/money.dart';
import '../shell/secondary_scaffold.dart';
import '../theme/app_colors.dart';

/// T13 — Recently Deleted Transactions. Own dedicated Settings-linked page
/// (relocated off
/// Analytics, PM direct decision, 2026-09-17): soft-deleted transactions
/// still within their 1-hour restore grace window, most-recently-deleted
/// first, each with a live per-row relative countdown ("42m 15s left",
/// ticking every second) and a Restore action. The disabled "Coming soon"
/// companion-web-page placeholder row and the empty state's exact copy are
/// both carried over verbatim from the earlier prototype.
///
/// Purge-sweep judgment call (disclosed in this dispatch's FLAGS): this
/// page ALSO runs `TransactionDao.purgeExpiredSoftDeletes` on its own
/// load (the spec only mandates the app-launch
/// sweep, wired separately into `home_screen.dart`'s `_bootstrap()`) and
/// re-runs it whenever the live countdown tick observes a row that just
/// hit 0 — exactly the prototype's own `purgeExpired()`-on-load +
/// `tickCountdowns()`'s `if (anyExpired) render();` behavior. Without
/// this, a user who opens this page and watches a countdown reach 0:00
/// would see a stale "0s left" row lingering until they happen to
/// relaunch the app from Home.
///
/// T26 "i think it should recolor the entire app": follows the chosen
/// palette (`SecondaryScaffold(followPalette: true)`, every colour a
/// palette token), same as T24's Profile rework. The countdown's danger
/// red and the delete-confirmation language are unchanged; only the
/// underlying colour values now come from [AppPalette].
class RecentlyDeletedScreen extends StatefulWidget {
  const RecentlyDeletedScreen({super.key, this.db, this.now = DateTime.now});

  /// Test-only injection seam — same convention every other Phase 6
  /// screen in this codebase uses (`analytics_screen.dart`/
  /// `manage_classifications_screen.dart`): `null` in real app usage
  /// resolves via `AppDatabase.instance.database` at bootstrap; a fake
  /// `Database` drives this screen's widget tests instead, since a real
  /// `sqflite_common_ffi` `Database` hangs indefinitely inside
  /// `testWidgets` in this environment.
  final Database? db;

  /// Test-only clock seam, defaulting to the real `DateTime.now`. Exists
  /// solely so a widget test can deterministically prove the live-tick
  /// "a countdown crossing 0 while this page is open re-purges and
  /// re-renders immediately" behavior (this file's own doc comment /
  /// FLAGS) without racing real wall-clock time: `flutter_test`'s fake
  /// async `pump(duration)` advances `Timer.periodic`'s own firing
  /// schedule, but does NOT change what a raw `DateTime.now()` call
  /// returns, so without this seam a test could only assert the
  /// purge-on-load path (already at time zero), never the "expired
  /// mid-visit" path.
  final DateTime Function() now;

  @override
  State<RecentlyDeletedScreen> createState() => _RecentlyDeletedScreenState();
}

class _RecentlyDeletedScreenState extends State<RecentlyDeletedScreen> {
  static const _graceMs = 3600000; // 1 hour — the PM-decided v1 window.

  Database? _db;
  bool _loading = true;
  List<DeletedTransactionRow> _rows = const [];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    if (!mounted) return;
    _db = db;
    await _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _load() async {
    final db = _db;
    if (db == null) return;
    // This page's own purge-on-load, on top of the app-launch sweep —
    // see this file's own doc comment / this dispatch's FLAGS.
    await TransactionDao.purgeExpiredSoftDeletes(db);
    final rows = await RecentlyDeletedDao.deletedTransactions(db);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  /// Runs every second while this page is open. Purely a repaint (no
  /// re-query) UNLESS a row's own countdown has actually reached zero,
  /// in which case a real purge+reload runs — matching the prototype's
  /// `tickCountdowns()`: recompute every row's remaining time and only
  /// call `render()` (a real re-fetch there too) `if (anyExpired)`.
  void _tick() {
    if (!mounted) return;
    final now = widget.now().millisecondsSinceEpoch;
    final anyExpired = _rows.any(
      (r) => (_graceMs - (now - r.deletedAt.millisecondsSinceEpoch)) <= 0,
    );
    if (anyExpired) {
      _load();
    } else {
      setState(() {}); // repaint the live countdown text only
    }
  }

  Future<void> _restore(DeletedTransactionRow row) async {
    final db = _db;
    if (db == null) return;
    try {
      await TransactionDao.restore(db, id: row.id);
    } on DatabaseException {
      // Its M-Pesa code was recorded again while it was deleted (the unique
      // index); the row stays here.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That code is already recorded')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Transaction restored')),
    );
    await _load();
  }

  String _countdownText(DeletedTransactionRow row) {
    final remaining = _graceMs - (widget.now().millisecondsSinceEpoch - row.deletedAt.millisecondsSinceEpoch);
    if (remaining <= 0) return '0m 00s left';
    final mins = remaining ~/ 60000;
    final secs = (remaining % 60000) ~/ 1000;
    return '${mins}m ${secs.toString().padLeft(2, '0')}s left';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Recently Deleted',
      followPalette: true,
      body: _loading ? Center(child: CircularProgressIndicator(color: palette.primary)) : _buildBody(palette),
    );
  }

  Widget _buildBody(AppPalette palette) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          "Deleted transactions stay recoverable for 1 hour, then they're purged for good — "
          'silently, with no further prompt.',
          style: TextStyle(fontSize: 12, color: palette.mutedInk),
        ),
        const SizedBox(height: 12),
        _comingSoonRow(palette),
        if (_rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              'Nothing here right now.',
              style: TextStyle(fontSize: 13, color: palette.mutedInk),
            ),
          )
        else
          for (final row in _rows) _deletedRow(row, palette),
      ],
    );
  }

  Widget _comingSoonRow(AppPalette palette) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.background,
        border: Border.all(color: palette.line, style: BorderStyle.solid),
        borderRadius: const BorderRadius.all(Radius.circular(10)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'View & restore from the companion web page',
              style: TextStyle(fontSize: 12, color: palette.mutedInk),
            ),
          ),
          Text('Coming soon', style: TextStyle(fontSize: 12, color: palette.mutedInk)),
        ],
      ),
    );
  }

  Widget _deletedRow(DeletedTransactionRow row, AppPalette palette) {
    return Container(
      key: Key('deletedRow_${row.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)), // Profile's own card radius (T24)
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  row.displayName,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
                ),
              ),
              Text(
                formatKsh(row.amountCents),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(row.displayCode, style: TextStyle(fontSize: 12, color: palette.mutedInk)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _countdownText(row),
                key: Key('deletedRowCountdown_${row.id}'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.diffUp,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              OutlinedButton(
                key: Key('deletedRowRestoreButton_${row.id}'),
                onPressed: () => _restore(row),
                style: OutlinedButton.styleFrom(foregroundColor: palette.primary, side: BorderSide(color: palette.line)),
                child: const Text('Restore'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
