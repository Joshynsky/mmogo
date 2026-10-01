import 'dart:convert';
import 'dart:typed_data';

import 'backup_limits.dart';

/// Writes the backup file: ONE compact UTF-8 JSON object, no encryption.
///
/// ```
/// {"app":"mmogo","format_version":1,"schema_version":2,"created_at":...,
///  "counts":{...},"classifications":[...],"transactions":[...],
///  "counterparty_map":[...],"prefs":{...},"end":"mmogo-v1"}
/// ```
/// `app` is deliberately the FIRST key and the output is compact, so the
/// literal `"app":"mmogo"` sits in the first 256 bytes (the auto-backup prune
/// looks for it) and `"end":"mmogo-v1"}` is the very tail of the file.
///
/// Rows arrive already in file shape (see the key lists in
/// `backup_limits.dart`); the codec copies ONLY those keys, in that order, so
/// an extra column in a query can never leak into a file. Decoding and
/// validation are `BackupValidator`'s job.
class BackupCodec {
  BackupCodec._();

  static Uint8List encode({
    required int createdAtMs,
    required List<Map<String, Object?>> classifications,
    required List<Map<String, Object?>> transactions,
    required List<Map<String, Object?>> counterpartyMap,
    Map<String, Object?> prefs = const {},
  }) {
    final envelope = <String, Object?>{
      'app': kBackupAppMarker,
      'format_version': kBackupFormatVersion,
      'schema_version': kBackupSchemaVersion,
      'created_at': createdAtMs,
      'counts': <String, Object?>{
        'classifications': classifications.length,
        'transactions': transactions.length,
        'counterparty_map': counterpartyMap.length,
      },
      'classifications': [
        for (final r in classifications) _pick(r, kBackupClassificationKeys),
      ],
      'transactions': [
        for (final r in transactions) _pick(r, kBackupTransactionKeys),
      ],
      'counterparty_map': [
        for (final r in counterpartyMap) _pick(r, kBackupMapKeys),
      ],
      'prefs': Map<String, Object?>.of(prefs),
      'end': kBackupEndMarker,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static Map<String, Object?> _pick(Map<String, Object?> row, List<String> keys) =>
      <String, Object?>{for (final k in keys) k: row[k]};
}
