import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// §DATA.DB.MIGRATION_V3_REKEY — the one-time SEND_MONEY re-key of `_toV3`
/// (S3b, C-A4, DBE T3.5). FROZEN: this file never reads the live phone rule.
///
/// 0.1.1 keyed Send Money learned receivers by the TRIMMED stored phone. 0.1.2
/// keys them by the canonical phone key, so `0712345678`, `+254712345678`,
/// `254712345678` and `00254712345678` are one person. This step rewrites the old
/// keys once. There is NO runtime fallback to the old key.
///
/// Rules (Judge C-A4(c)):
///  - only `source_type = 'SEND_MONEY'` rows change; PAYBILL / BUY_GOODS keys are
///    never touched;
///  - rows are grouped by their new key; the winner of a group is the row with
///    the greatest (`updated_at`, `id`);
///  - losers are DELETED FIRST (chunks of 400), then surviving keys are updated,
///    so UNIQUE(source_type, counterparty_key) never clashes;
///  - the winner keeps its own category and `auto_apply` (not OR-ed);
///  - transactions and stored phones are never touched.

final RegExp _v3Separators = RegExp(r'[\s-]');
final RegExp _v3Prefixed = RegExp(r'^(\+254|254|00254)([17][0-9]{8})$');
final RegExp _v3Local = RegExp(r'^0[17][0-9]{8}$');

/// Frozen private copy of the phone key rule as it stood at 0.1.2. A
/// differential test pins it equal to the live `normalizePhoneKey` over a
/// fixed-seed corpus; if the live rule ever changes, that test fails and this
/// copy must NOT follow it.
String normalizePhoneKeyV3(String? raw) {
  if (raw == null) return '';
  final s = raw.trim();
  final t = s.replaceAll(_v3Separators, '');
  final m = _v3Prefixed.firstMatch(t);
  if (m != null) return '0${m.group(2)}';
  if (_v3Local.hasMatch(t)) return t;
  return s;
}

/// What the re-key did, counts only (never keys or names). DB8 prints it for the
/// real-copy gate; the app later writes the loser count to a device pref.
class PhoneRekeyReport {
  const PhoneRekeyReport({
    required this.mapBefore,
    required this.mapAfter,
    required this.keysRewritten,
    required this.groupsMerged,
    required this.losersDeleted,
    required this.losersWithDifferentCategory,
    required this.losersWithAutoApply,
  });

  /// Rows in `counterparty_classification_map` (all source types) before / after.
  final int mapBefore;
  final int mapAfter;

  /// Surviving SEND_MONEY rows whose key text changed.
  final int keysRewritten;

  /// New-key groups that held more than one row.
  final int groupsMerged;

  /// Rows deleted (every row of a merged group except its winner).
  final int losersDeleted;

  /// Losers whose `classification_id` differs from their winner's (learned
  /// category lost).
  final int losersWithDifferentCategory;

  /// Losers that had `auto_apply = 1` (auto-apply lost).
  final int losersWithAutoApply;

  @override
  String toString() => 'PhoneRekeyReport(mapBefore: $mapBefore, mapAfter: $mapAfter, '
      'keysRewritten: $keysRewritten, groupsMerged: $groupsMerged, '
      'losersDeleted: $losersDeleted, '
      'losersWithDifferentCategory: $losersWithDifferentCategory, '
      'losersWithAutoApply: $losersWithAutoApply)';

  @override
  bool operator ==(Object other) =>
      other is PhoneRekeyReport && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// Runs the re-key on [db] (inside the caller's transaction). [before] is the
/// `@visibleForTesting` failure-injection hook of `_toV3`; it is awaited ahead
/// of each logical statement group with the labels `rekey_read`, `rekey_delete`,
/// `rekey_update` (called even when there is nothing to delete or update, so the
/// label list never depends on the data).
///
/// Throws [StateError] if an invariant breaks (the caller's transaction then
/// rolls the whole of `_toV3` back).
Future<PhoneRekeyReport> rekeySendMoneyKeys(
  DatabaseExecutor db, {
  Future<void> Function(String label)? before,
}) async {
  Future<void> hook(String l) async => before == null ? null : await before(l);

  await hook('rekey_read');
  final mapBefore = _count(await db.rawQuery('SELECT COUNT(*) FROM counterparty_classification_map'));
  final sendBefore = _count(await db.rawQuery(
      "SELECT COUNT(*) FROM counterparty_classification_map WHERE source_type = 'SEND_MONEY'"));
  final otherBefore = await _otherRowsDump(db);

  final rows = await db.rawQuery(
    'SELECT id, counterparty_key, classification_id, auto_apply, updated_at '
    "FROM counterparty_classification_map WHERE source_type = 'SEND_MONEY' ORDER BY id",
  );

  // Group by the NEW key (insertion-ordered map, so the run is deterministic).
  final groups = <String, List<Map<String, Object?>>>{};
  for (final r in rows) {
    final newKey = normalizePhoneKeyV3(r['counterparty_key'] as String?);
    (groups[newKey] ??= []).add(r);
  }

  final loserIds = <int>[];
  final updates = <int, String>{}; // survivor id -> new key
  var groupsMerged = 0;
  var diffCategory = 0;
  var withAuto = 0;
  groups.forEach((newKey, members) {
    var winner = members.first;
    if (members.length > 1) {
      groupsMerged++;
      for (final m in members.skip(1)) {
        if (_newer(m, winner)) winner = m;
      }
    }
    for (final m in members) {
      if (identical(m, winner)) continue;
      loserIds.add(m['id'] as int);
      if (m['classification_id'] != winner['classification_id']) diffCategory++;
      if (m['auto_apply'] == 1) withAuto++;
    }
    if (winner['counterparty_key'] != newKey) {
      updates[winner['id'] as int] = newKey;
    }
  });

  await hook('rekey_delete');
  for (var i = 0; i < loserIds.length; i += 400) {
    final chunk = loserIds.sublist(i, i + 400 > loserIds.length ? loserIds.length : i + 400);
    final marks = List.filled(chunk.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM counterparty_classification_map WHERE id IN ($marks)',
      chunk,
    );
  }

  await hook('rekey_update');
  for (final e in updates.entries) {
    await db.rawUpdate(
      'UPDATE counterparty_classification_map SET counterparty_key = ? '
      "WHERE id = ? AND source_type = 'SEND_MONEY'",
      [e.value, e.key],
    );
  }

  // Invariants (any breach throws and rolls `_toV3` back).
  final mapAfter = _count(await db.rawQuery('SELECT COUNT(*) FROM counterparty_classification_map'));
  final sendAfter = _count(await db.rawQuery(
      "SELECT COUNT(*) FROM counterparty_classification_map WHERE source_type = 'SEND_MONEY'"));
  if (sendAfter != sendBefore - loserIds.length) {
    throw StateError('rekey: SEND_MONEY map count did not fall by exactly the losers');
  }
  if (mapAfter != mapBefore - loserIds.length) {
    throw StateError('rekey: total map count did not fall by exactly the losers');
  }
  final left = await db.rawQuery(
      "SELECT counterparty_key FROM counterparty_classification_map WHERE source_type = 'SEND_MONEY'");
  for (final r in left) {
    final k = r['counterparty_key'] as String?;
    if (normalizePhoneKeyV3(k) != k) {
      throw StateError('rekey: a SEND_MONEY key is still not canonical');
    }
  }
  if (await _otherRowsDump(db) != otherBefore) {
    throw StateError('rekey: rows of other source types changed');
  }

  return PhoneRekeyReport(
    mapBefore: mapBefore,
    mapAfter: mapAfter,
    keysRewritten: updates.length,
    groupsMerged: groupsMerged,
    losersDeleted: loserIds.length,
    losersWithDifferentCategory: diffCategory,
    losersWithAutoApply: withAuto,
  );
}

/// True when [a] is more recent than [b]: greater `updated_at`, ties broken by
/// the higher `id`.
bool _newer(Map<String, Object?> a, Map<String, Object?> b) {
  final au = a['updated_at'] as int;
  final bu = b['updated_at'] as int;
  if (au != bu) return au > bu;
  return (a['id'] as int) > (b['id'] as int);
}

int _count(List<Map<String, Object?>> rows) => rows.first.values.first as int;

Future<String> _otherRowsDump(DatabaseExecutor db) async {
  final rows = await db.rawQuery(
    'SELECT id, source_type, counterparty_key, classification_id, auto_apply, updated_at '
    "FROM counterparty_classification_map WHERE source_type != 'SEND_MONEY' ORDER BY id",
  );
  return rows.map((r) => r.values.join('|')).join('\n');
}
