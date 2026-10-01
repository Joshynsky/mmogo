import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// B3: longest classification name the Add and Manage inputs accept (typing is
/// cut here; longer names already saved are loaded as they are).
const classificationNameMaxLength = 100;

/// One row of `classification_groups` — includes disabled groups (Pochi La
/// Biashara, `enabled = 0`) unfiltered; the disabled Pochi La
/// Biashara group tab must always be
/// visibly rendered, just non-interactive, so this DAO never hides it.
class ClassificationGroup {
  const ClassificationGroup({
    required this.id,
    required this.code,
    required this.displayName,
    required this.enabled,
  });

  final int id;
  final String code;
  final String displayName;
  final bool enabled;
}

/// One row of `classifications` (active=1 only, per the query methods
/// below — the soft-delete convention).
class ClassificationItem {
  const ClassificationItem({
    required this.id,
    required this.groupId,
    required this.name,
  });

  final int id;
  final int groupId;
  final String name;
}

/// Minimal, ad hoc query layer against `AppDatabase`/`AppSchema` directly,
/// following the same idiom `home_dashboard_dao.dart` (T4) already
/// established for this project: raw/plain `db.query`/`db.insert` calls,
/// no repository/DAO base class, no ORM — sqlite already enforces
/// everything that matters here (the `idx_classifications_active_name`
/// partial unique index, group-scoped) so this layer stays a thin,
/// direct pass-through.
class ClassificationDao {
  ClassificationDao._();

  /// All `classification_groups` rows, ordered by `id` (seed order:
  /// SEND_MONEY, PAYBILL, BUY_GOODS, POCHI_LA_BIASHARA). Deliberately
  /// unfiltered on `enabled` — callers decide how to render a disabled
  /// group (this dispatch: greyed out, non-interactive), never drop it
  /// from the result set.
  static Future<List<ClassificationGroup>> fetchGroups(Database db) async {
    final rows = await db.query('classification_groups', orderBy: 'id');
    return rows
        .map(
          (row) => ClassificationGroup(
            id: row['id'] as int,
            code: row['code'] as String,
            displayName: row['display_name'] as String,
            enabled: (row['enabled'] as int) == 1,
          ),
        )
        .toList();
  }

  /// Active (`active = 1`) classifications scoped to one `group_id`,
  /// name-ordered. Uniqueness/soft-delete is per-group, not
  /// global, so this never queries across groups.
  static Future<List<ClassificationItem>> fetchActiveClassifications(
    Database db, {
    required int groupId,
  }) async {
    final rows = await db.query(
      'classifications',
      where: 'group_id = ? AND active = 1',
      whereArgs: [groupId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => ClassificationItem(
            id: row['id'] as int,
            groupId: row['group_id'] as int,
            name: row['name'] as String,
          ),
        )
        .toList();
  }

  /// Inserts a new classification scoped to [groupId]. Deliberately does
  /// NOT pre-check name uniqueness in Dart first — this dispatch's own
  /// instruction is to surface the real SQLite constraint violation
  /// (`idx_classifications_active_name`, a partial UNIQUE index on
  /// `(group_id, name) WHERE active = 1`) as the user-facing error, not to
  /// short-circuit the real DB round-trip with a Dart-side duplicate
  /// check. A duplicate active name in the same group throws a real
  /// `DatabaseException` (`isUniqueConstraintError()` true) — the caller
  /// (the classification picker / Manage classifications screen) catches it.
  static Future<int> createClassification(
    Database db, {
    required int groupId,
    required String name,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert('classifications', {
      'group_id': groupId,
      'name': name,
      'active': 1,
      'created_at': now,
    });
  }

  /// T8 — Manage Classifications. Inactive (`active = 0`, soft-deleted)
  /// classifications scoped to one `group_id`, name-ordered — the
  /// counterpart to [fetchActiveClassifications]. Manage
  /// Classifications keeps the inactive list reachable and
  /// restorable, not hidden.
  static Future<List<ClassificationItem>> fetchInactiveClassifications(
    Database db, {
    required int groupId,
  }) async {
    final rows = await db.query(
      'classifications',
      where: 'group_id = ? AND active = 0',
      whereArgs: [groupId],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows
        .map(
          (row) => ClassificationItem(
            id: row['id'] as int,
            groupId: row['group_id'] as int,
            name: row['name'] as String,
          ),
        )
        .toList();
  }

  /// T8 — renames a classification in place (`UPDATE classifications SET
  /// name = ? WHERE id = ?`). Deliberately does NOT
  /// pre-check name uniqueness in Dart first — same discipline as
  /// [createClassification]: a rename that collides with another active
  /// classification's name in the same group throws a real
  /// `DatabaseException` (`isUniqueConstraintError()` true) against the
  /// real `idx_classifications_active_name` partial unique index; the
  /// caller catches it.
  static Future<void> renameClassification(
    Database db, {
    required int id,
    required String newName,
  }) async {
    await db.update(
      'classifications',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// T8 — soft-deletes a classification (`active = 0`). Never a hard
  /// delete: existing `transactions
  /// .classification_id` rows are untouched (`ON DELETE RESTRICT`) and
  /// keep counting in Analytics' historical totals.
  static Future<void> softDeleteClassification(Database db, {required int id}) async {
    await db.update(
      'classifications',
      {'active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// T8 — restores a soft-deleted classification (`active = 0 -> 1`).
  /// Reactivating a soft-deleted classification is real, in-scope work —
  /// soft-delete is NOT a one-way mechanism. Same no-Dart-pre-check discipline:
  /// restoring into a group that already has a different active
  /// classification of the same name throws a real unique-constraint
  /// `DatabaseException`; the caller catches it (this is a genuine edge
  /// case — see this dispatch's FLAGS).
  static Future<void> restoreClassification(Database db, {required int id}) async {
    await db.update(
      'classifications',
      {'active': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// T8 — real `COUNT(*)` of (non-soft-deleted) `transactions` rows
  /// referencing [classificationId], for the delete-confirmation dialog's
  /// message ("N transactions use this classification; it will be hidden, not
  /// deleted, and can be restored later" — not a generic "are you sure").
  /// Filters `deleted_at IS NULL`, consistent with every other read in
  /// this codebase (`home_dashboard_dao.dart`'s same convention) — a
  /// transaction already on its way to permanent purge shouldn't inflate
  /// the count the user is shown.
  static Future<int> countTransactionsForClassification(
    Database db, {
    required int classificationId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM transactions
      WHERE classification_id = ? AND deleted_at IS NULL
      ''',
      [classificationId],
    );
    return (rows.first['c'] as num).toInt();
  }

  /// T3 — Add — Cash tab's classification picker.
  ///
  /// A flat, name-deduplicated list of active classifications drawn across
  /// every *enabled* `classification_group` (Send Money/Paybill/Buy Goods;
  /// Pochi La Biashara excluded while `enabled = 0`) — cash is a direct payment for
  /// whatever reason (rent, a person, a barber...) and was never
  /// conceptually "Send Money"/"Paybill"/"Buy Goods", so the group-tab step
  /// [fetchActiveClassifications]'s per-group callers use is skipped
  /// entirely for cash — this method is the query-layer half of that fix.
  ///
  /// Dedup rule (matches the earlier prototype's cash class list,
  /// re-derived fresh as SQL/Dart, not ported): the dedup key is the
  /// classification name, trimmed and lowercased (so "Transport" seeded
  /// under Send Money/Paybill/Buy Goods collapses to one row, not three).
  /// The winning row for a duplicate name is whichever has the lowest
  /// `id` — since `classifications.id` increases with seed/creation order
  /// and groups are seeded Send Money -> Paybill -> Buy Goods -> Pochi,
  /// this deterministically prefers the earliest-seeded group's copy,
  /// matching the prototype's own array-iteration-order tie-break. Which
  /// row wins is otherwise inert for correctness: the winning row's
  /// `group_id` is never surfaced to the user for cash
  /// (the classification chip drops the group-name parenthetical for cash
  /// specifically), and every enabled group's
  /// classification is equally valid for a CASH insert per the
  /// group-scope guard trigger.
  ///
  /// Final list is sorted alphabetically (case-insensitive) for display,
  /// matching the prototype's `list.sort((a,b) =>
  /// a.name.localeCompare(b.name))`.
  static Future<List<ClassificationItem>> fetchFlatActiveClassifications(
    Database db,
  ) async {
    final rows = await db.rawQuery('''
      SELECT c.id, c.group_id, c.name
      FROM classifications c
      JOIN classification_groups g ON g.id = c.group_id
      WHERE c.active = 1 AND g.enabled = 1
      ORDER BY c.id ASC
    ''');
    final seenNames = <String>{};
    final deduped = <ClassificationItem>[];
    for (final row in rows) {
      final name = row['name'] as String;
      final key = name.trim().toLowerCase();
      if (seenNames.add(key)) {
        deduped.add(
          ClassificationItem(
            id: row['id'] as int,
            groupId: row['group_id'] as int,
            name: name,
          ),
        );
      }
    }
    deduped.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return deduped;
  }
}
