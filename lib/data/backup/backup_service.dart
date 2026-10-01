import 'dart:typed_data';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_codec.dart';
import 'backup_limits.dart';
import 'backup_settings.dart';
import 'backup_validator.dart';

/// The export would not fit what the app can read back: a row cap, or the
/// 20 MB file cap. The app never writes a file it could not itself restore.
class BackupTooLarge implements Exception {
  const BackupTooLarge({required this.what, this.size, this.limit});

  /// `transactions`, `classifications`, `counterparty_map` or `bytes`.
  final String what;
  final int? size;
  final int? limit;

  @override
  String toString() => 'BackupTooLarge($what, size: $size, limit: $limit)';
}

/// The export, run through the validator in memory, would be refused (for
/// example an over-long legacy classification name). Export aborts instead
/// of writing a file that could not be restored. Carries no row content.
class BackupNotRestorable implements Exception {
  const BackupNotRestorable(this.cause);
  final RestoreRejected cause;

  @override
  String toString() => 'BackupNotRestorable(${cause.toString()})';
}

/// What an export produced.
class BackupExport {
  const BackupExport({
    required this.bytes,
    required this.classifications,
    required this.transactions,
    required this.counterpartyMap,
    required this.excludedSoftDeleted,
  });

  final Uint8List bytes;
  final int classifications;
  final int transactions;
  final int counterpartyMap;

  /// Recently deleted (soft-deleted) transactions left OUT of the file (PM
  /// rule); the UI tells the user how many.
  final int excludedSoftDeleted;
}

/// Builds a backup file from the live database.
class BackupService {
  BackupService({
    required Future<Database> Function() db,
    DateTime Function()? now,
    BackupSettings? settings,
    this.maxBytes = kBackupMaxBytes,
  })  : _db = db,
        _now = now ?? DateTime.now,
        _settings = settings ?? BackupSettings();

  final Future<Database> Function() _db;
  final DateTime Function() _now;
  final BackupSettings _settings;

  /// The size guard. Always [kBackupMaxBytes] in the app; a test lowers it.
  final int maxBytes;

  /// `mmogo-backup-YYYYMMDD-HHMMSS.json` from [now]'s own fields (pass local
  /// time). The only variable part is the timestamp: no name, phone number or
  /// device name ever goes into the file name.
  String suggestedFileName(DateTime now) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${now.year.toString().padLeft(4, '0')}${two(now.month)}${two(now.day)}';
    final time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return 'mmogo-backup-$date-$time.json';
  }

  /// UTF-8 JSON bytes of the backup. See [export] for the counts.
  Future<Uint8List> exportToBytes() async => (await export()).bytes;

  /// Reads everything in ONE read transaction (so the counts agree), writes
  /// the file bytes, then checks them: the size cap, and a round trip through
  /// the validator. Soft-deleted transactions are excluded and counted.
  ///
  /// Throws [BackupTooLarge] or [BackupNotRestorable]; never returns a file
  /// the app would refuse to restore.
  Future<BackupExport> export() async {
    final db = await _db();
    late List<Map<String, Object?>> classes;
    late List<Map<String, Object?>> txs;
    late List<Map<String, Object?>> map;
    late int excluded;
    late Set<String> enabledGroups;

    await db.transaction((txn) async {
      classes = [
        for (final r in await txn.rawQuery(
          'SELECT c.id AS id, g.code AS "group", c.name AS name, '
          'c.active AS active, c.seed_key AS seed_key, c.created_at AS created_at '
          'FROM classifications c '
          'JOIN classification_groups g ON g.id = c.group_id '
          'ORDER BY c.id',
        ))
          Map<String, Object?>.of(r),
      ];
      txs = [
        for (final r in await txn.rawQuery(
          'SELECT id, display_code, source_type, amount_cents, '
          'transaction_cost_cents, counterparty_label, counterparty_phone, '
          'paybill_account_number, classification_id AS classification, '
          'raw_parse_source, transaction_occurred_at, created_at '
          'FROM transactions WHERE deleted_at IS NULL ORDER BY id',
        ))
          Map<String, Object?>.of(r),
      ];
      map = [
        for (final r in await txn.rawQuery(
          'SELECT source_type, counterparty_key, '
          'classification_id AS classification, auto_apply, updated_at '
          'FROM counterparty_classification_map ORDER BY id',
        ))
          Map<String, Object?>.of(r),
      ];
      final ex = await txn.rawQuery(
        'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NOT NULL',
      );
      excluded = (ex.first['n'] as int?) ?? 0;
      enabledGroups = {
        for (final r in await txn.rawQuery(
          'SELECT code FROM classification_groups WHERE enabled = 1',
        ))
          r['code'] as String,
      };
    });

    // Row caps first: cheaper than encoding.
    _guardRows('classifications', classes.length, kBackupMaxClassifications);
    _guardRows('transactions', txs.length, kBackupMaxTransactions);
    _guardRows('counterparty_map', map.length, kBackupMaxMapRows);

    final bytes = BackupCodec.encode(
      createdAtMs: _now().millisecondsSinceEpoch,
      classifications: classes,
      transactions: txs,
      counterpartyMap: map,
      prefs: await _settings.snapshot(),
    );

    if (bytes.length > maxBytes) {
      throw BackupTooLarge(what: 'bytes', size: bytes.length, limit: maxBytes);
    }

    // Round-trip guard: the file we are about to hand out must pass the same
    // checks a restore will apply.
    try {
      BackupValidator.validate(bytes, enabledGroupCodes: enabledGroups);
    } on RestoreRejected catch (e) {
      throw BackupNotRestorable(e);
    }

    return BackupExport(
      bytes: bytes,
      classifications: classes.length,
      transactions: txs.length,
      counterpartyMap: map.length,
      excludedSoftDeleted: excluded,
    );
  }

  static void _guardRows(String what, int n, int cap) {
    if (n > cap) throw BackupTooLarge(what: what, size: n, limit: cap);
  }
}
