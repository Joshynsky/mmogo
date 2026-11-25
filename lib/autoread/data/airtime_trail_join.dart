/// §AUTOREAD.AIRTIME_TRAIL_JOIN - turns the stored trail (row numbers and
/// times) into the rows the page shows, by looking each one up in the ledger.
///
/// An entry is shown only when its row exists and was written from an SMS
/// (`raw_parse_source = 'SMS_PARSE'`; 0.2.2: any kind, so a suggested-chip record and an Ask first Yes
/// are listed too, with the person and the category name); otherwise it is hidden (nothing to undo, no stored "could not undo"). The
/// amount, the kind (the row's category seed key) and "moved to Recently
/// deleted" (`deleted_at` set) all come from the row. One bounded, parameterised
/// query (at most [kTrailMaxEntries] ids).
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/airtime/airtime_kind.dart';
import '../logic/airtime_auto.dart';
import 'airtime_trail_store.dart';

Future<List<AutoRecorded>> joinTrail(
  Database db,
  List<TrailEntry> entries,
) async {
  if (entries.isEmpty) return const [];
  final ids = [for (final e in entries.take(kTrailMaxEntries)) e.rowId];
  final marks = List.filled(ids.length, '?').join(',');
  final rows = await db.rawQuery(
    'SELECT t.id AS id, t.amount_cents AS amount_cents, t.deleted_at AS deleted_at, c.seed_key AS seed_key, '
    't.source_type AS source_type, t.counterparty_label AS label, t.counterparty_phone AS phone, '
    'c.name AS category_name '
    'FROM transactions t JOIN classifications c ON c.id = t.classification_id '
    "WHERE t.raw_parse_source = 'SMS_PARSE' AND t.id IN ($marks)",
    ids,
  );
  final byId = {for (final r in rows) r['id'] as int: r};
  return [
    for (final e in entries)
      if (byId[e.rowId] case final r?)
        AutoRecorded(
          rowId: e.rowId,
          amountCents: r['amount_cents'] as int,
          at: e.at,
          airtimeOther: r['seed_key'] == kAirtimeSeedOther,
          partyLabel: r['source_type'] == 'AIRTIME' ? null : _party(r),
          categoryName: r['source_type'] == 'AIRTIME' ? null : r['category_name'] as String?,
          inRecentlyDeleted: r['deleted_at'] != null,
        ),
  ];
}

/// Who the money went to: the name, else the number, else a plain word (never empty).
String _party(Map<String, Object?> r) {
  for (final k in ['label', 'phone']) {
    final v = r[k];
    if (v is String && v.trim().isNotEmpty) return v.trim();
  }
  return 'Payment';
}
