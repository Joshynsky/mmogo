import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_validator.dart';

/// What is already on this phone, read once at the start of a restore (inside
/// the restore transaction, or read-only for the preview). Keys are built in
/// Dart only; nothing here is ever put into SQL text.
class RestoreLookups {
  RestoreLookups._({
    required this.groupIdByCode,
    required this.seedIdByKey,
    required this.activeByName,
    required this.anyByName,
    required this.liveCodes,
    required this.liveCash,
    required this.mapKeys,
  });

  /// `classification_groups.code` -> id (system rows, never written).
  final Map<String, int> groupIdByCode;

  /// `classifications.seed_key` -> id (the 12 built-ins).
  final Map<String, int> seedIdByKey;

  /// `(group code, name)` -> id of the ACTIVE row.
  final Map<String, int> activeByName;

  /// `(group code, name)` -> id, active row preferred, else the lowest id.
  final Map<String, int> anyByName;

  /// M-Pesa codes of live (not recently deleted) non-CASH rows. A code held
  /// only by a recently deleted row is NOT here, so the file's live row is
  /// restored as a new entry (A6).
  final Set<String> liveCodes;

  /// `(display_code, created_at)` of live CASH rows.
  final Set<String> liveCash;

  /// `(source_type, counterparty_key)` of the learned receivers.
  final Set<String> mapKeys;

  static String nameKey(String group, String name) => '$group\u0000$name';
  static String cashKey(String code, int createdAt) => '$code\u0000$createdAt';
  static String mapKey(String source, String key) => '$source\u0000$key';

  static Future<RestoreLookups> load(DatabaseExecutor ex) async {
    final groups = <String, int>{
      for (final r in await ex.rawQuery('SELECT id, code FROM classification_groups'))
        r['code']! as String: r['id']! as int,
    };
    final seeds = <String, int>{};
    final active = <String, int>{};
    final any = <String, int>{};
    for (final r in await ex.rawQuery(
      'SELECT c.id AS id, g.code AS code, c.name AS name, c.active AS active, '
      'c.seed_key AS seed_key FROM classifications c '
      'JOIN classification_groups g ON g.id = c.group_id '
      'ORDER BY c.active DESC, c.id',
    )) {
      final id = r['id']! as int;
      final key = nameKey(r['code']! as String, r['name']! as String);
      final seedKey = r['seed_key'] as String?;
      if (seedKey != null) seeds[seedKey] = id;
      if (r['active'] == 1) active.putIfAbsent(key, () => id);
      any.putIfAbsent(key, () => id);
    }
    final codes = <String>{};
    final cash = <String>{};
    for (final r in await ex.rawQuery(
      'SELECT display_code, source_type, created_at FROM transactions '
      'WHERE deleted_at IS NULL',
    )) {
      final code = r['display_code']! as String;
      if (r['source_type'] == 'CASH') {
        cash.add(cashKey(code, r['created_at']! as int));
      } else {
        codes.add(code);
      }
    }
    final map = <String>{
      for (final r in await ex.rawQuery(
        'SELECT source_type, counterparty_key FROM counterparty_classification_map',
      ))
        mapKey(r['source_type']! as String, r['counterparty_key']! as String),
    };
    return RestoreLookups._(
      groupIdByCode: groups,
      seedIdByKey: seeds,
      activeByName: active,
      anyByName: any,
      liveCodes: codes,
      liveCash: cash,
      mapKeys: map,
    );
  }
}

/// Where a file classification lands: an existing row ([dbId]) or the
/// [pending]-th row this restore will insert.
class ClassTarget {
  const ClassTarget.existing(int this.dbId) : pending = null;
  const ClassTarget.pending(int this.pending) : dbId = null;

  final int? dbId;
  final int? pending;
}

/// The merge decisions for one validated file against [RestoreLookups]:
/// which rows are new, which are already here. Pure Dart, no I/O. Replace
/// mode uses the same plan after it has cleared the phone's rows.
///
/// Rules (data-model.md D, merge steps 2 to 4):
///  - a built-in (`seed_key`) maps to this phone's built-in, never inserted
///    (A3: a renamed built-in is still recognised);
///  - an active user classification maps to the active row with the same
///    `(group, name)`, else it is new; an inactive one maps to any row with
///    that `(group, name)` (active preferred), else it is new and inactive;
///    rows planned earlier in the same file count as "already here";
///  - a non-CASH transaction whose M-Pesa code is live here is skipped; a
///    CASH transaction is skipped when `(display_code, created_at)` matches;
///  - a learned receiver whose `(source_type, key)` exists here is skipped
///    (the phone's choice wins).
class RestorePlan {
  RestorePlan._({
    required this.newClassifications,
    required this.classTargets,
    required this.newTransactions,
    required this.newMapRows,
    required this.classSkipped,
    required this.txSkipped,
    required this.mapSkipped,
  });

  /// File classification rows to insert, in file order.
  final List<Map<String, Object?>> newClassifications;

  /// File classification id -> where it lands.
  final Map<int, ClassTarget> classTargets;

  final List<Map<String, Object?>> newTransactions;
  final List<Map<String, Object?>> newMapRows;
  final int classSkipped;
  final int txSkipped;
  final int mapSkipped;

  /// Throws [StateError] when the file names a built-in this phone does not
  /// have (cannot happen on a v2 database; it aborts the transaction).
  static RestorePlan build(ValidatedBackup file, RestoreLookups l) {
    final active = Map<String, ClassTarget>.of(
        l.activeByName.map((k, v) => MapEntry(k, ClassTarget.existing(v))));
    final any = Map<String, ClassTarget>.of(
        l.anyByName.map((k, v) => MapEntry(k, ClassTarget.existing(v))));
    final newClasses = <Map<String, Object?>>[];
    final targets = <int, ClassTarget>{};
    var classSkipped = 0;

    for (final row in file.classifications) {
      final fileId = row['id']! as int;
      final seedKey = row['seed_key'] as String?;
      if (seedKey != null) {
        final id = l.seedIdByKey[seedKey];
        if (id == null) throw StateError('built-in missing on this phone');
        targets[fileId] = ClassTarget.existing(id);
        classSkipped++;
        continue;
      }
      final key = RestoreLookups.nameKey(row['group']! as String, row['name']! as String);
      final isActive = row['active'] == 1;
      final match = isActive ? active[key] : any[key];
      if (match != null) {
        targets[fileId] = match;
        classSkipped++;
        continue;
      }
      final t = ClassTarget.pending(newClasses.length);
      newClasses.add(row);
      targets[fileId] = t;
      if (isActive) {
        active[key] = t;
        any[key] = t; // an active row is preferred over an inactive one
      } else {
        any.putIfAbsent(key, () => t);
      }
    }

    final codes = Set<String>.of(l.liveCodes);
    final cash = Set<String>.of(l.liveCash);
    final newTx = <Map<String, Object?>>[];
    var txSkipped = 0;
    for (final row in file.transactions) {
      final code = row['display_code']! as String;
      final isNew = row['source_type'] == 'CASH'
          ? cash.add(RestoreLookups.cashKey(code, row['created_at']! as int))
          : codes.add(code);
      if (isNew) {
        newTx.add(row);
      } else {
        txSkipped++;
      }
    }

    final mapKeys = Set<String>.of(l.mapKeys);
    final newMap = <Map<String, Object?>>[];
    var mapSkipped = 0;
    for (final row in file.counterpartyMap) {
      if (mapKeys.add(RestoreLookups.mapKey(
          row['source_type']! as String, row['counterparty_key']! as String))) {
        newMap.add(row);
      } else {
        mapSkipped++;
      }
    }

    return RestorePlan._(
      newClassifications: newClasses,
      classTargets: targets,
      newTransactions: newTx,
      newMapRows: newMap,
      classSkipped: classSkipped,
      txSkipped: txSkipped,
      mapSkipped: mapSkipped,
    );
  }
}
