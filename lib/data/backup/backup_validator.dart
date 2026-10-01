import 'dart:convert';
import 'dart:typed_data';

import 'backup_limits.dart';
import 'backup_setting_keys.dart';

/// Why a file was refused. Names follow architecture D5.
enum RestoreRejectReason {
  /// Not a backup of this app (no or wrong `app` marker).
  notMmogo,

  /// Written by a newer mmogo (`format_version` or `schema_version` too high).
  newer,

  /// Not parseable, truncated, wrong envelope shape, counts do not match.
  corrupt,

  /// Over the 20 MB cap.
  tooLarge,

  /// Over a row cap.
  tooMany,

  /// A row, or the settings block, broke a rule (type, range, length, enum,
  /// date, pattern, forbidden character, duplicate, trigger or CHECK rule).
  invalidRow,

  /// A transaction or map row points at a classification the file lacks.
  danglingRef,
}

/// Thrown by [BackupValidator]. Names the table, row index and field, NEVER
/// the offending value (it is hostile text).
class RestoreRejected implements Exception {
  const RestoreRejected(
    this.reason, {
    this.table,
    this.rowIndex,
    this.field,
  });

  final RestoreRejectReason reason;
  final String? table;
  final int? rowIndex;
  final String? field;

  @override
  String toString() =>
      'RestoreRejected(${reason.name}, table: $table, row: $rowIndex, field: $field)';
}

/// A file that passed every check. Plain data (sendable out of an isolate):
/// copies of the validated rows, nothing from the file that was not checked.
class ValidatedBackup {
  const ValidatedBackup({
    required this.formatVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.classifications,
    required this.transactions,
    required this.counterpartyMap,
    required this.prefs,
  });

  final int formatVersion;
  final int schemaVersion;
  final int createdAt;

  /// Keys per `kBackupClassificationKeys`; `id` is a file-local handle only.
  final List<Map<String, Object?>> classifications;

  /// Keys per `kBackupTransactionKeys`; `classification` is a file-local id.
  final List<Map<String, Object?>> transactions;

  /// Keys per `kBackupMapKeys`.
  final List<Map<String, Object?>> counterpartyMap;

  /// Only allowlisted settings (unknown keys are dropped), each already
  /// checked; safe to hand to `BackupSettings.applyAfterCommit`.
  final Map<String, Object?> prefs;
}

/// Restore Stage 1: bytes in, [ValidatedBackup] or [RestoreRejected] out.
///
/// PURE. No database handle, no file, no network: it imports only
/// `dart:convert`, `dart:typed_data` and the constant files, so it runs in
/// `Isolate.run`. Nothing in the file is opened, followed or executed:
/// strings that look like paths, URLs or ids are just checked text.
///
/// The cash-on-disabled-group rule needs one fact from the database; the
/// caller passes it as [enabledGroupCodes] (read once from
/// `classification_groups`), so this class never touches a DB.
class BackupValidator {
  BackupValidator._();

  /// Groups enabled on a fresh install (Pochi is off).
  static const Set<String> defaultEnabledGroups = {
    'SEND_MONEY',
    'PAYBILL',
    'BUY_GOODS',
  };

  /// Reads a stream into memory, aborting THE MOMENT the running total passes
  /// the 20 MB cap (a lying `declaredSize` is covered: it is only a first
  /// cheap check, the running count is the real one).
  static Future<Uint8List> readCapped(
    Stream<List<int>> stream, {
    int? declaredSize,
  }) async {
    if (declaredSize != null && declaredSize > kBackupMaxBytes) {
      throw const RestoreRejected(RestoreRejectReason.tooLarge);
    }
    final out = BytesBuilder();
    var total = 0;
    await for (final chunk in stream) {
      total += chunk.length;
      if (total > kBackupMaxBytes) {
        // Leaving the loop cancels the subscription: the rest is never read.
        throw const RestoreRejected(RestoreRejectReason.tooLarge);
      }
      out.add(chunk);
    }
    return out.takeBytes();
  }

  static ValidatedBackup validate(
    Uint8List bytes, {
    Set<String> enabledGroupCodes = defaultEnabledGroups,
  }) {
    if (bytes.isEmpty) _fail(RestoreRejectReason.corrupt);
    if (bytes.length > kBackupMaxBytes) _fail(RestoreRejectReason.tooLarge);

    // Pathologically nested input is refused before any parser sees it.
    if (!_depthWithinLimit(bytes)) _fail(RestoreRejectReason.corrupt, field: 'depth');

    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes)); // strict UTF-8: malformed throws
    } on FormatException {
      throw const RestoreRejected(RestoreRejectReason.corrupt);
    }
    if (root is! Map) _fail(RestoreRejectReason.corrupt);

    // --- envelope: marker and versions first, so a foreign or newer file is
    // reported as that and not as "wrong keys".
    if (root['app'] != kBackupAppMarker) {
      _fail(RestoreRejectReason.notMmogo, field: 'app');
    }
    final formatVersion = root['format_version'];
    if (formatVersion is! int) {
      _fail(RestoreRejectReason.corrupt, field: 'format_version');
    }
    if (formatVersion > kBackupFormatVersion) {
      _fail(RestoreRejectReason.newer, field: 'format_version');
    }
    if (formatVersion != kBackupFormatVersion) {
      _fail(RestoreRejectReason.corrupt, field: 'format_version');
    }
    final schemaVersion = root['schema_version'];
    if (schemaVersion is! int) {
      _fail(RestoreRejectReason.corrupt, field: 'schema_version');
    }
    if (schemaVersion > kBackupSchemaVersion) {
      _fail(RestoreRejectReason.newer, field: 'schema_version');
    }
    if (schemaVersion < kBackupMinSchemaVersion) {
      _fail(RestoreRejectReason.corrupt, field: 'schema_version');
    }

    if (!_hasExactKeys(root, kBackupTopLevelKeys)) {
      _fail(RestoreRejectReason.corrupt, field: '(keys)');
    }
    final createdAt = root['created_at'];
    if (!_isEpoch(createdAt)) {
      _fail(RestoreRejectReason.corrupt, field: 'created_at');
    }
    if (root['end'] != kBackupEndMarker) {
      _fail(RestoreRejectReason.corrupt, field: 'end');
    }

    final classRows = root['classifications'];
    final txRows = root['transactions'];
    final mapRows = root['counterparty_map'];
    if (classRows is! List) _fail(RestoreRejectReason.corrupt, field: 'classifications');
    if (txRows is! List) _fail(RestoreRejectReason.corrupt, field: 'transactions');
    if (mapRows is! List) _fail(RestoreRejectReason.corrupt, field: 'counterparty_map');

    // --- caps, then counts equal array lengths (catches truncation).
    if (classRows.length > kBackupMaxClassifications) {
      _fail(RestoreRejectReason.tooMany, table: 'classifications');
    }
    if (txRows.length > kBackupMaxTransactions) {
      _fail(RestoreRejectReason.tooMany, table: 'transactions');
    }
    if (mapRows.length > kBackupMaxMapRows) {
      _fail(RestoreRejectReason.tooMany, table: 'counterparty_map');
    }
    final counts = root['counts'];
    if (counts is! Map || !_hasExactKeys(counts, kBackupCountsKeys)) {
      _fail(RestoreRejectReason.corrupt, field: 'counts');
    }
    if (counts['classifications'] is! int ||
        counts['classifications'] != classRows.length ||
        counts['transactions'] is! int ||
        counts['transactions'] != txRows.length ||
        counts['counterparty_map'] is! int ||
        counts['counterparty_map'] != mapRows.length) {
      _fail(RestoreRejectReason.corrupt, field: 'counts');
    }

    // --- rows.
    final classGroupById = <int, String>{};
    final classifications = _classifications(classRows, classGroupById);
    final transactions =
        _transactions(txRows, classGroupById, enabledGroupCodes);
    final counterpartyMap = _map(mapRows, classGroupById);
    final prefs = _prefs(root['prefs']);

    return ValidatedBackup(
      formatVersion: formatVersion,
      schemaVersion: schemaVersion,
      createdAt: createdAt as int,
      classifications: classifications,
      transactions: transactions,
      counterpartyMap: counterpartyMap,
      prefs: prefs,
    );
  }

  // ---------------------------------------------------------------------------
  // classifications

  static List<Map<String, Object?>> _classifications(
    List rows,
    Map<int, String> classGroupById,
  ) {
    const t = 'classifications';
    final out = <Map<String, Object?>>[];
    final seedKeysSeen = <String>{};
    final activeNames = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupClassificationKeys, t, i);
      final id = _int(row['id'], 1, kBackupMaxClassificationFileId, t, i, 'id');
      if (classGroupById.containsKey(id)) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'id');
      final group = _enum(row['group'], kBackupGroupCodes, t, i, 'group');
      final name = _text(row['name'], 1, kBackupMaxClassificationNameLength, t, i, 'name');
      final active = _int(row['active'], 0, 1, t, i, 'active');
      final seedKey = row['seed_key'];
      if (seedKey != null) {
        if (seedKey is! String ||
            !kBackupSeedKeys.contains(seedKey) ||
            !seedKey.startsWith('$group:') ||
            !seedKeysSeen.add(seedKey)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'seed_key');
        }
      }
      _int(row['created_at'], kBackupMinEpochMs, kBackupMaxEpochMs - 1, t, i, 'created_at');
      // Mirrors idx_classifications_active_name.
      if (active == 1 && !activeNames.add('$group\u0000$name')) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'name');
      }
      classGroupById[id] = group;
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // transactions

  static List<Map<String, Object?>> _transactions(
    List rows,
    Map<int, String> classGroupById,
    Set<String> enabledGroupCodes,
  ) {
    const t = 'transactions';
    final out = <Map<String, Object?>>[];
    final ids = <int>{};
    final mpesaCodes = <String>{};
    final cashKeys = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupTransactionKeys, t, i);
      final id = _int(row['id'], 1, 9007199254740991, t, i, 'id');
      if (!ids.add(id)) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'id');

      final source = _enum(row['source_type'], kBackupSourceTypes, t, i, 'source_type');
      final isCash = source == 'CASH';
      final code = row['display_code'];
      final codePattern = isCash ? kBackupCashCodePattern : kBackupMpesaCodePattern;
      if (code is! String || !codePattern.hasMatch(code)) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'display_code');
      }
      _int(row['amount_cents'], 1, kBackupMaxAmountCents, t, i, 'amount_cents');

      final cost = row['transaction_cost_cents'];
      if (isCash) {
        if (cost != null) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'transaction_cost_cents');
      } else {
        _int(cost, 0, kBackupMaxCostCents, t, i, 'transaction_cost_cents');
      }

      final label = row['counterparty_label'];
      final phone = row['counterparty_phone'];
      final account = row['paybill_account_number'];
      if (label != null) {
        if (isCash) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_label');
        _text(label, 1, kBackupMaxLabelLength, t, i, 'counterparty_label');
      }
      if (phone != null) {
        if (source != 'SEND_MONEY' || phone is! String || !kBackupPhonePattern.hasMatch(phone)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_phone');
        }
      }
      if (account != null) {
        if (source != 'PAYBILL') _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'paybill_account_number');
        _text(account, 1, kBackupMaxPaybillAccountLength, t, i, 'paybill_account_number');
      }
      // Mirrors the paired-optionality CHECKs.
      if (source == 'SEND_MONEY' && (label == null) != (phone == null)) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_phone');
      }
      if (source == 'PAYBILL' && (label == null) != (account == null)) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'paybill_account_number');
      }

      final raw = _enum(row['raw_parse_source'], kBackupRawParseSources, t, i, 'raw_parse_source');
      if (isCash && raw != 'MANUAL') {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'raw_parse_source');
      }
      _int(row['transaction_occurred_at'], kBackupMinEpochMs, kBackupMaxEpochMs - 1, t, i, 'transaction_occurred_at');
      final createdAt = _int(row['created_at'], kBackupMinEpochMs, kBackupMaxEpochMs - 1, t, i, 'created_at');

      // Reference and the trigger rules (group matches source type; a CASH
      // row may not sit on a disabled group).
      final classId = row['classification'];
      if (classId is! int) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'classification');
      final group = classGroupById[classId];
      if (group == null) _fail(RestoreRejectReason.danglingRef, table: t, rowIndex: i, field: 'classification');
      if (isCash) {
        if (!enabledGroupCodes.contains(group)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'classification');
        }
      } else if (group != source) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'classification');
      }

      // Duplicate codes inside the file.
      final dupOk = isCash
          ? cashKeys.add('$code|$createdAt')
          : mpesaCodes.add(code);
      if (!dupOk) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'display_code');

      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // counterparty_map

  static List<Map<String, Object?>> _map(
    List rows,
    Map<int, String> classGroupById,
  ) {
    const t = 'counterparty_map';
    final out = <Map<String, Object?>>[];
    final keys = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupMapKeys, t, i);
      final source = _enum(row['source_type'], kBackupMapSourceTypes, t, i, 'source_type');
      final key = _text(row['counterparty_key'], 1, kBackupMaxCounterpartyKeyLength, t, i, 'counterparty_key');
      if (source == 'PAYBILL' && !key.contains('#')) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_key');
      }
      _int(row['auto_apply'], 0, 1, t, i, 'auto_apply');
      _int(row['updated_at'], kBackupMinEpochMs, kBackupMaxEpochMs - 1, t, i, 'updated_at');
      final classId = row['classification'];
      if (classId is! int) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'classification');
      final group = classGroupById[classId];
      if (group == null) _fail(RestoreRejectReason.danglingRef, table: t, rowIndex: i, field: 'classification');
      if (group != source) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'classification');
      if (!keys.add('$source\u0000$key')) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_key');
      }
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // prefs

  /// Unknown keys are dropped (never applied, never an error); an allowlisted
  /// key with a wrong type or range rejects the whole file.
  static Map<String, Object?> _prefs(Object? raw) {
    if (raw is! Map) _fail(RestoreRejectReason.corrupt, field: 'prefs');
    if (raw.length > kBackupMaxPrefsKeys) {
      _fail(RestoreRejectReason.invalidRow, table: 'prefs', field: '(keys)');
    }
    final out = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) _fail(RestoreRejectReason.invalidRow, table: 'prefs', field: '(keys)');
      final spec = backupSettingSpecFor(key);
      if (spec == null) continue;
      if (!spec.accepts(entry.value)) {
        _fail(RestoreRejectReason.invalidRow, table: 'prefs', field: key);
      }
      out[key] = entry.value;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // helpers

  static Never _fail(
    RestoreRejectReason reason, {
    String? table,
    int? rowIndex,
    String? field,
  }) =>
      throw RestoreRejected(reason, table: table, rowIndex: rowIndex, field: field);

  static bool _hasExactKeys(Map m, List<String> keys) {
    if (m.length != keys.length) return false;
    for (final k in keys) {
      if (!m.containsKey(k)) return false;
    }
    return true;
  }

  static bool _isEpoch(Object? v) =>
      v is int && v >= kBackupMinEpochMs && v < kBackupMaxEpochMs;

  static Map _row(Object? raw, List<String> keys, String table, int i) {
    if (raw is! Map || !_hasExactKeys(raw, keys)) {
      _fail(RestoreRejectReason.invalidRow, table: table, rowIndex: i, field: '(keys)');
    }
    return raw;
  }

  static int _int(Object? v, int min, int max, String table, int i, String field) {
    if (v is! int || v < min || v > max) {
      _fail(RestoreRejectReason.invalidRow, table: table, rowIndex: i, field: field);
    }
    return v;
  }

  static String _enum(Object? v, List<String> allowed, String table, int i, String field) {
    if (v is! String || !allowed.contains(v)) {
      _fail(RestoreRejectReason.invalidRow, table: table, rowIndex: i, field: field);
    }
    return v;
  }

  /// Non-empty text, trimmed, within [maxLength], no control or bidi chars.
  static String _text(Object? v, int minLength, int maxLength, String table, int i, String field) {
    if (v is! String ||
        v.length < minLength ||
        v.length > maxLength ||
        v != v.trim() ||
        !backupTextIsClean(v)) {
      _fail(RestoreRejectReason.invalidRow, table: table, rowIndex: i, field: field);
    }
    return v;
  }

  /// True when no bracket nesting outside a string goes deeper than
  /// [kBackupMaxJsonDepth]. Byte-level and allocation-free, so a file of a
  /// million `[` is refused in microseconds instead of being parsed.
  static bool _depthWithinLimit(Uint8List bytes) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (b == 0x5C) {
          escaped = true;
        } else if (b == 0x22) {
          inString = false;
        }
        continue;
      }
      if (b == 0x22) {
        inString = true;
      } else if (b == 0x5B || b == 0x7B) {
        if (++depth > kBackupMaxJsonDepth) return false;
      } else if (b == 0x5D || b == 0x7D) {
        depth--;
      }
    }
    return true;
  }
}
