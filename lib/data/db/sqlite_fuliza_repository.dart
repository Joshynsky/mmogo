import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/fuliza/fuliza_repository.dart';

/// §DATA.DB.FULIZA — The real `fuliza_events` table behind [FulizaRepository].
///
/// The message text is never stored: only the six columns of the table.
/// The limit lives in preferences under [limitPrefsKey] (a device value; a
/// backup file also carries it).
class SqliteFulizaRepository implements FulizaRepository {
  SqliteFulizaRepository(this._db, {Future<SharedPreferences> Function()? prefs})
      : _prefs = prefs ?? _defaultPrefs;

  static const String limitPrefsKey = 'fuliza_limit_cents';

  final Database _db;
  final Future<SharedPreferences> Function() _prefs;

  static Future<SharedPreferences> _defaultPrefs() =>
      SharedPreferences.getInstance().timeout(const Duration(seconds: 2));

  @override
  Future<bool> addEvent(FulizaEvent event) async {
    try {
      final id = await _db.insert(
        'fuliza_events',
        {
          'kind': event.kind.name,
          'code': event.code,
          'occurred_at': event.at.millisecondsSinceEpoch,
          'amount_cents': event.amountCents,
          'fee_cents': event.feeCents,
          'printed_total_cents': event.printedTotalCents,
        },
      );
      return id > 0;
    } on DatabaseException catch (e) {
      // A repeat of (kind, code) is reported as false, never thrown. Any other
      // failure (a CHECK on a bad figure) is a real error and goes up. (INSERT OR
      // IGNORE is NOT used: it would swallow a CHECK failure as a quiet false.)
      if (e.isUniqueConstraintError()) return false;
      rethrow;
    }
  }

  @override
  Future<List<FulizaEvent>> events() async {
    final rows = await _db.query('fuliza_events', orderBy: 'occurred_at ASC, id ASC');
    return [
      for (final r in rows)
        FulizaEvent(
          kind: FulizaEventKind.values.byName(r['kind']! as String),
          code: r['code']! as String,
          at: DateTime.fromMillisecondsSinceEpoch((r['occurred_at']! as num).toInt()),
          amountCents: (r['amount_cents']! as num).toInt(),
          feeCents: (r['fee_cents']! as num).toInt(),
          printedTotalCents: (r['printed_total_cents'] as num?)?.toInt(),
        ),
    ];
  }

  /// The codes of live (not soft-deleted) ordinary payments: the same
  /// `display_code` that `AnalyticsDao.byCodes` joins on.
  @override
  Future<Set<String>> paymentCodes() async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT display_code FROM transactions WHERE deleted_at IS NULL');
    return {for (final r in rows) r['display_code']! as String};
  }

  @override
  Future<int?> limitCents() async {
    try {
      final p = await _prefs();
      final v = p.get(limitPrefsKey);
      return v is int ? v : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setLimitCents(int cents) async {
    final p = await _prefs();
    await p.setInt(limitPrefsKey, cents);
  }
}

/// A [FulizaRepository] over the real table that opens the database only when
/// first used (startup installs it before the database is open, and Delete
/// data / Restore can swap the database file, so the handle is looked up on
/// every call).
class LazySqliteFulizaRepository implements FulizaRepository {
  LazySqliteFulizaRepository(this._db);
  final Future<Database> Function() _db;

  Future<FulizaRepository> _repo() async => SqliteFulizaRepository(await _db());

  @override
  Future<bool> addEvent(FulizaEvent event) async => (await _repo()).addEvent(event);
  @override
  Future<List<FulizaEvent>> events() async => (await _repo()).events();
  @override
  Future<Set<String>> paymentCodes() async => (await _repo()).paymentCodes();
  @override
  Future<int?> limitCents() async => (await _repo()).limitCents();
  @override
  Future<void> setLimitCents(int cents) async => (await _repo()).setLimitCents(cents);
}
