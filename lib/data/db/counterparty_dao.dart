import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// One `counterparty_classification_map` row resolved for display —
/// returned by [CounterpartyDao.lookup].
class CounterpartySuggestion {
  const CounterpartySuggestion({
    required this.classificationId,
    required this.classificationName,
    required this.groupDisplayName,
    required this.autoApply,
  });

  final int classificationId;
  final String classificationName;
  final String groupDisplayName;
  final bool autoApply;
}

/// One row of the "recent classifications" quick-pick list — returned by
/// [CounterpartyDao.fetchRecent].
class RecentClassificationEntry {
  const RecentClassificationEntry({
    required this.sourceType,
    required this.counterpartyKey,
    required this.classificationId,
    required this.classificationName,
    required this.groupDisplayName,
    required this.updatedAt,
  });

  final String sourceType;
  final String counterpartyKey;
  final int classificationId;
  final String classificationName;
  final String groupDisplayName;
  final int updatedAt;
}

/// T12 — Suggestion pill / counterparty auto-suggest system.
///
/// Query layer for `counterparty_classification_map`
/// (`lib/data/db/schema.dart`),
/// following the exact convention `classification_dao.dart` established:
/// static methods, an already-open [Database] parameter, raw SQL via
/// `db.rawQuery`/`db.rawInsert`/`db.update`, no ORM, no Dart-side
/// pre-check anywhere SQLite's own constraints already enforce the
/// invariant. [upsertOnConfirm]'s real `ON CONFLICT ... DO UPDATE` upsert
/// below leans on this table's own `UNIQUE (source_type, counterparty_key)`
/// index — same discipline `classification_dao.dart`'s
/// `createClassification`/`renameClassification`/`restoreClassification`
/// already use for their own unique-index violations, except a collision
/// on THIS table is the expected, desired outcome (an update), not an
/// error to surface to the caller.
///
/// Every method's `sourceType`/`counterpartyKey` pair must be produced by
/// `deriveCounterpartyKey` (`lib/domain/counterparty/counterparty_key.dart`)
/// on both the caller's read side and write side — this file does not
/// re-derive or validate the key itself; it is a pure storage-layer
/// pass-through to whatever string it is given, by design, so this DAO has
/// zero normalization logic of its own that could ever drift from the
/// domain-layer function the OPEN flag-ledger item is actually about.
class CounterpartyDao {
  CounterpartyDao._();

  /// The single matching row for `(sourceType, counterpartyKey)`, or
  /// `null` if this exact pair has never been classified before — "no
  /// suggestion" (a suggestion is shown only
  /// when counterparty_classification_map has a matching row).
  static Future<CounterpartySuggestion?> lookup(
    Database db, {
    required String sourceType,
    required String counterpartyKey,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT m.classification_id, m.auto_apply, c.name AS classification_name,
             g.display_name AS group_display_name
      FROM counterparty_classification_map m
      JOIN classifications c ON c.id = m.classification_id
      JOIN classification_groups g ON g.id = c.group_id
      WHERE m.source_type = ? AND m.counterparty_key = ?
      ''',
      [sourceType, counterpartyKey],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return CounterpartySuggestion(
      classificationId: row['classification_id'] as int,
      classificationName: row['classification_name'] as String,
      groupDisplayName: row['group_display_name'] as String,
      autoApply: (row['auto_apply'] as int) == 1,
    );
  }

  /// Upsert-on-confirm — writes (inserts or updates) the
  /// `(sourceType, counterpartyKey)` row's `classification_id` and
  /// `updated_at = now`, via a real SQL `ON CONFLICT` upsert against the
  /// table's own `UNIQUE (source_type, counterparty_key)` constraint —
  /// not a Dart-side "SELECT then decide INSERT-or-UPDATE" race-prone
  /// pattern. Deliberately does NOT touch `auto_apply`:
  /// that column is set ONLY via the explicit "make
  /// automatic" checkbox ([setAutoApply]), never as a side effect of a
  /// plain classify-and-save. Omitting `auto_apply` from the `DO UPDATE`
  /// SET clause below relies on SQLite's own upsert semantics to leave an
  /// existing row's value untouched — asserted directly by this
  /// dispatch's DAO round-trip test, not just claimed in this comment.
  ///
  /// **Ordering requirement for T6 (the real caller, not yet built):**
  /// call this at the moment a transaction is actually saved (the real
  /// Add review sheet's `TransactionDao.insert` call), not earlier at
  /// mere suggestion-acceptance time — the mapping is written the moment
  /// the user classifies a transaction, read together with the
  /// mandatory post-parse confirmation step's own reasoning (the write
  /// should reflect what was actually saved, not an in-progress,
  /// still-editable choice). If a "make automatic" checkbox is also
  /// checked for the same save, call [setAutoApply] AFTER this method
  /// returns, not before — [setAutoApply] is a plain `UPDATE` against an
  /// already-existing row and is a silent no-op if the row doesn't exist
  /// yet (see its own doc comment).
  static Future<void> upsertOnConfirm(
    Database db, {
    required String sourceType,
    required String counterpartyKey,
    required int classificationId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.rawInsert(
      '''
      INSERT INTO counterparty_classification_map
        (source_type, counterparty_key, classification_id, auto_apply, updated_at)
      VALUES (?, ?, ?, 0, ?)
      ON CONFLICT (source_type, counterparty_key)
      DO UPDATE SET classification_id = excluded.classification_id,
                     updated_at = excluded.updated_at
      ''',
      [sourceType, counterpartyKey, classificationId, now],
    );
  }

  /// Sets `auto_apply = 1` on the EXISTING row for this specific
  /// `(sourceType, counterpartyKey)` — scoped to that one counterparty
  /// only ("for this specific counterparty_key going forward"). A plain
  /// `UPDATE`, not an upsert: the "make automatic" checkbox is actionable
  /// only after an active confirmed classification — i.e. [upsertOnConfirm]
  /// must already have run for this same counterparty by the time this is
  /// callable, so the row is expected to already exist. If it doesn't
  /// (e.g. a caller invokes this out of order), the `UPDATE` matches zero
  /// rows and silently does nothing — deliberately not an upsert that
  /// would fabricate a `classification_id`-less row (there is no sane
  /// default classification to invent), and deliberately not a thrown
  /// error either (matches this codebase's other fail-quiet DAO/prefs
  /// methods, e.g. `AppPrefs`'s read methods).
  static Future<void> setAutoApply(
    Database db, {
    required String sourceType,
    required String counterpartyKey,
  }) async {
    await db.update(
      'counterparty_classification_map',
      {'auto_apply': 1},
      where: 'source_type = ? AND counterparty_key = ?',
      whereArgs: [sourceType, counterpartyKey],
    );
  }

  /// Up to [limit] (default 5, the recent-classifications
  /// quick-pick list) most-recently-used `counterparty_classification_
  /// map` rows, `ORDER BY updated_at DESC`, resolved to classification
  /// name/group. Matches `idx_counterparty_map_recency`'s own schema
  /// comment ("supports the 'recent classifications' quick-pick list (top
  /// 5 by updated_at)") literally: no distinct-classification dedup, no
  /// per-source_type filter — the raw top-N rows by recency, exactly as
  /// specified (two different counterparties classified the same way both
  /// legitimately appear, since the mapping is many-to-one).
  static Future<List<RecentClassificationEntry>> fetchRecent(
    Database db, {
    int limit = 5,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT m.source_type, m.counterparty_key, m.classification_id, m.updated_at,
             c.name AS classification_name, g.display_name AS group_display_name
      FROM counterparty_classification_map m
      JOIN classifications c ON c.id = m.classification_id
      JOIN classification_groups g ON g.id = c.group_id
      ORDER BY m.updated_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows
        .map(
          (row) => RecentClassificationEntry(
            sourceType: row['source_type'] as String,
            counterpartyKey: row['counterparty_key'] as String,
            classificationId: row['classification_id'] as int,
            classificationName: row['classification_name'] as String,
            groupDisplayName: row['group_display_name'] as String,
            updatedAt: row['updated_at'] as int,
          ),
        )
        .toList();
  }
}
