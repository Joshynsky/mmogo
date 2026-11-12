import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/sqlite_fuliza_repository.dart' show LazySqliteFulizaRepository;
import '../../../data/db/analytics_dao.dart';
import '../../../data/db/app_database.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../domain/fuliza/fuliza_demo.dart';
import '../../../domain/fuliza/fuliza_ledger.dart';
import '../../../domain/fuliza/fuliza_page_data.dart';
import '../../../domain/fuliza/fuliza_repository.dart';

/// §FULIZA.SOURCE — 0.2.0 S9: where the Fuliza page and the Home line get their data. Persistence is
/// held (schema change, slice 12), so this reads a [FulizaRepository] that only exists when something
/// installed one: in a normal build NOTHING does, [load] returns null, and Home shows no Fuliza line
/// and the page is unreachable (main-flavor behaviour is unchanged). The debug demo installs an
/// [InMemoryFulizaRepository] with invented events ([fulizaDemoOn]); tests install their own.
class FulizaSource {
  FulizaSource._();

  /// null = no Fuliza data source in this build.
  static FulizaRepository? repository;

  /// Kill-switch (pref `fuliza_show`, default true). Fails toward ON, like the other switches.
  static Future<bool> readShow() async {
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      return p.getBool(AppPrefs.keyFulizaShow) ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> writeShow(bool value) async {
    try {
      final p = await SharedPreferences.getInstance().timeout(const Duration(seconds: 2));
      await p.setBool(AppPrefs.keyFulizaShow, value);
    } catch (_) {}
  }

  /// Debug demo only: installs the in-memory fake with the invented events. No-op unless [fulizaDemoOn].
  static Future<void> installDemoIfOn(DateTime now) async {
    if (!fulizaDemoOn || repository != null) return;
    final repo = InMemoryFulizaRepository();
    for (final e in demoFulizaEvents(now)) {
      await repo.addEvent(e);
    }
    await repo.setLimitCents(5000000);
    repository = repo;
  }

  /// Real builds (S12 slice D): reads the stored events. Keeps an installed repository (the demo's).
  static void installReal() {
    repository ??= LazySqliteFulizaRepository(() => AppDatabase.instance.database);
  }

  /// The page data and the ordinary payments the borrowings paid for, or null when there is no Fuliza
  /// data (no repository, or no events).
  static Future<FulizaSnapshot?> load(Database db) async {
    final repo = repository;
    if (repo == null) return null;
    // Kill-switch off: nothing is shown; events are still saved by the writer (PM choice C6 B).
    if (!await readShow()) return null;
    final events = await repo.events();
    if (events.isEmpty) return null;
    final codes = {
      for (final e in events)
        if (e.kind == FulizaEventKind.draw) e.code,
    };
    final spends = await AnalyticsDao.byCodes(db, codes);
    final state = FulizaCalculator.compute(events, {
      for (final s in spends) s.displayCode,
    }, limitCents: await repo.limitCents());
    final data = buildFulizaPage(state, events);
    if (data == null) return null;
    return FulizaSnapshot(data, {for (final s in spends) s.displayCode: s});
  }
}

/// What one load returns.
class FulizaSnapshot {
  const FulizaSnapshot(this.data, this.spendsByCode);

  final FulizaPageData data;

  /// Draw code -> the ordinary payment with that code.
  final Map<String, AnalyticsTransactionRow> spendsByCode;

  /// The spends paid with Fuliza, newest first (the Related list).
  List<AnalyticsTransactionRow> get related =>
      spendsByCode.values.toList()..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  /// The borrowing of [code], if any (amount of the draw in cents).
  int? drawCentsFor(String code) {
    for (final d in data.days) {
      for (final e in d.entries) {
        if (e.isDraw && e.event.code == code) return e.event.amountCents;
      }
    }
    return null;
  }
}
