import 'dart:convert';
import 'dart:typed_data';

import 'backup_limits.dart';
import 'backup_links.dart';
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
    this.fulizaEvents = const [],
    this.receiverRules = const [],
  });

  final int formatVersion;
  final int schemaVersion;
  final int createdAt;

  /// Keys per `kBackupClassificationKeys`; `id` is a file-local handle only.
  final List<Map<String, Object?>> classifications;

  /// Keys per `kBackupTransactionKeys`, plus `parent_id` / `cash_only_decided` ONLY when the
  /// file wrote them (an absent key means null / 0, readers use `?? 0`); `classification`
  /// and `parent_id` are file-local ids.
  final List<Map<String, Object?>> transactions;

  /// Keys per `kBackupMapKeys`.
  final List<Map<String, Object?>> counterpartyMap;

  /// Keys per `kBackupFulizaKeys`. Empty for a schema < 4 file (which has no
  /// such section); use [hasFulizaSection] to tell "none" from "not in file".
  final List<Map<String, Object?>> fulizaEvents;

  /// Keys per `kBackupRuleKeys` (schema >= 9), each row checked. A Paybill row at level 2 is
  /// ACCEPTED here as written; the restore (S-4b) turns it into Ask first. Category ids never
  /// appear: `cat_seed` / `cat_name` name the category. Empty for an older file; use
  /// [hasRulesSection] to tell "none" from "not in file" (a Replace from a file without the
  /// section leaves the phone with no rules, a Merge leaves them alone).
  final List<Map<String, Object?>> receiverRules;

  /// True when the file's schema carries the `receiver_rules` section (>= 9).
  bool get hasRulesSection => schemaVersion >= kBackupFirstSchemaWithRules;

  /// True when the file's schema carries the `fuliza_events` section (>= 4).
  /// A Replace from a file without it leaves the phone's Fuliza ledger alone.
  bool get hasFulizaSection => schemaVersion >= kBackupFirstSchemaWithFuliza;

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

  /// Groups enabled on a fresh install (all six since 0.1.2: Pochi is on).
  static const Set<String> defaultEnabledGroups = {
    'SEND_MONEY',
    'PAYBILL',
    'BUY_GOODS',
    'POCHI_LA_BIASHARA',
    'AGENT_WITHDRAWAL',
    'AIRTIME',
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

    final v4 = schemaVersion >= kBackupFirstSchemaWithFuliza;
    final v9 = schemaVersion >= kBackupFirstSchemaWithRules;
    if (!_hasExactKeys(root, v9 ? kBackupTopLevelKeys : (v4 ? kBackupTopLevelKeysV8 : kBackupTopLevelKeysV3))) {
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
    final fulizaRows = v4 ? root['fuliza_events'] : const [];
    if (fulizaRows is! List) _fail(RestoreRejectReason.corrupt, field: 'fuliza_events');
    final ruleRows = v9 ? root['receiver_rules'] : const [];
    if (ruleRows is! List) _fail(RestoreRejectReason.corrupt, field: 'receiver_rules');

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
    if (fulizaRows.length > kBackupMaxFulizaEvents) {
      _fail(RestoreRejectReason.tooMany, table: 'fuliza_events');
    }
    if (ruleRows.length > kBackupMaxRules) {
      _fail(RestoreRejectReason.tooMany, table: 'receiver_rules');
    }
    final counts = root['counts'];
    if (counts is! Map ||
        !_hasExactKeys(counts, v9 ? kBackupCountsKeys : (v4 ? kBackupCountsKeysV8 : kBackupCountsKeysV3))) {
      _fail(RestoreRejectReason.corrupt, field: 'counts');
    }
    if (counts['classifications'] is! int ||
        counts['classifications'] != classRows.length ||
        counts['transactions'] is! int ||
        counts['transactions'] != txRows.length ||
        counts['counterparty_map'] is! int ||
        counts['counterparty_map'] != mapRows.length ||
        (v4 && (counts['fuliza_events'] is! int || counts['fuliza_events'] != fulizaRows.length)) ||
        (v9 && (counts['receiver_rules'] is! int || counts['receiver_rules'] != ruleRows.length))) {
      _fail(RestoreRejectReason.corrupt, field: 'counts');
    }

    // --- rows.
    final classGroupById = <int, String>{};
    final classifications =
        _classifications(classRows, classGroupById, schemaVersion);
    final transactions =
        _transactions(txRows, classGroupById, enabledGroupCodes, schemaVersion);
    // 0.2.1: a link to a missing or non-withdrawal row (or past the withdrawal's amount)
    // is dropped, the Cash entry kept as plain Cash; never a refusal.
    resolveBackupLinks(transactions);
    final counterpartyMap = _map(mapRows, classGroupById);
    final fulizaEvents = _fulizaEvents(fulizaRows);
    final receiverRules = _receiverRules(ruleRows);
    final prefs = _prefs(root['prefs'], schemaVersion);

    return ValidatedBackup(
      formatVersion: formatVersion,
      schemaVersion: schemaVersion,
      createdAt: createdAt as int,
      classifications: classifications,
      transactions: transactions,
      counterpartyMap: counterpartyMap,
      prefs: prefs,
      fulizaEvents: fulizaEvents,
      receiverRules: receiverRules,
    );
  }

  // ---------------------------------------------------------------------------
  // classifications

  static List<Map<String, Object?>> _classifications(
    List rows,
    Map<int, String> classGroupById,
    int schemaVersion,
  ) {
    const t = 'classifications';
    // New group codes and seed keys are valid only in a schema >= 3 file.
    final v3 = schemaVersion >= kBackupFirstSchemaWithAgentAndAirtime;
    // `CASH_USE` (the withdrawal Cash list) only from schema 7; older files never carry it.
    final groupCodes = schemaVersion >= kBackupFirstSchemaWithCashGroup
        ? kBackupGroupCodesV7
        : (v3 ? kBackupGroupCodes : kBackupGroupCodesV2);
    final seedKeys = schemaVersion >= kBackupFirstSchemaWithAirtimeKinds
        ? kBackupSeedKeys
        : (v3 ? kBackupSeedKeysV3V4 : kBackupSeedKeysV2);
    final out = <Map<String, Object?>>[];
    final seedKeysSeen = <String>{};
    final activeNames = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupClassificationKeys, t, i);
      final id = _int(row['id'], 1, kBackupMaxClassificationFileId, t, i, 'id');
      if (classGroupById.containsKey(id)) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'id');
      final group = _enum(row['group'], groupCodes, t, i, 'group');
      final name = _text(row['name'], 1, kBackupMaxClassificationNameLength, t, i, 'name');
      final active = _int(row['active'], 0, 1, t, i, 'active');
      final seedKey = row['seed_key'];
      if (seedKey != null) {
        if (seedKey is! String ||
            !seedKeys.contains(seedKey) ||
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
    int schemaVersion,
  ) {
    const t = 'transactions';
    // Schema 2: the exact 12 keys and the original four source types; the row
    // is copied with `agent_number: null` so later code sees one shape.
    final v3 = schemaVersion >= kBackupFirstSchemaWithAgentAndAirtime;
    final v6 = schemaVersion >= kBackupFirstSchemaWithLinkedCash;
    final v8 = schemaVersion >= kBackupFirstSchemaWithAutoMarker;
    final rowKeys = v3 ? kBackupTransactionKeys : kBackupTransactionKeysV2;
    final sourceTypes = v3 ? kBackupSourceTypes : kBackupSourceTypesV2;
    final out = <Map<String, Object?>>[];
    final ids = <int>{};
    final mpesaCodes = <String>{};
    final cashKeys = <String>{};
    for (var i = 0; i < rows.length; i++) {
      // Schema 6: the two link keys are optional (written only when not the default).
      final row = _row(rows[i], rowKeys, t, i, optional: [if (v6) ...kBackupTransactionLinkKeys, if (v8) kBackupRecordedAutoKey]);
      final id = _int(row['id'], 1, 9007199254740991, t, i, 'id');
      if (!ids.add(id)) _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'id');

      final source = _enum(row['source_type'], sourceTypes, t, i, 'source_type');
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
      final agent = v3 ? row['agent_number'] : null;
      if (label != null) {
        // Mirrors the v3 label CHECK: only the identity-carrying types hold a label.
        if (!kBackupLabelSourceTypes.contains(source)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'counterparty_label');
        }
        _text(label, 1, kBackupMaxLabelLength, t, i, 'counterparty_label');
      }
      if (agent != null) {
        // Mirrors the v3 agent-number CHECK: Withdrawal rows only, 1 to 20 digits.
        if (source != 'AGENT_WITHDRAWAL' ||
            agent is! String ||
            !kBackupAgentNumberPattern.hasMatch(agent)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'agent_number');
        }
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

      // Shape only; whether a link is usable is `resolveBackupLinks`' call.
      final pid = row['parent_id'];
      if (pid != null) _int(pid, 1, 9007199254740991, t, i, 'parent_id');
      if (row.containsKey('cash_only_decided')) _int(row['cash_only_decided'], 0, 1, t, i, 'cash_only_decided');

      final raw = _enum(row['raw_parse_source'], kBackupRawParseSources, t, i, 'raw_parse_source');
      if (isCash && raw != 'MANUAL') {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'raw_parse_source');
      }
      // Schema 8: the auto-record marker is 0 or 1, and 1 only on a non-Cash row from a parse.
      if (row.containsKey(kBackupRecordedAutoKey)) {
        final auto = _int(row[kBackupRecordedAutoKey], 0, 1, t, i, 'recorded_auto');
        if (auto == 1 && (isCash || raw != 'SMS_PARSE')) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'recorded_auto');
        }
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

      final copy = Map<String, Object?>.from(row);
      if (!v3) copy['agent_number'] = null;
      out.add(copy);
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
  // fuliza_events (schema >= 4)

  /// Mirrors the table's CHECKs and its UNIQUE (kind, code): kind is an enum
  /// name, amount > 0, fee >= 0, printed total null or >= 0, code non-empty
  /// clean text, time in the epoch range. Money is capped like transactions.
  static List<Map<String, Object?>> _fulizaEvents(List rows) {
    const t = 'fuliza_events';
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupFulizaKeys, t, i);
      final kind = _enum(row['kind'], kBackupFulizaKinds, t, i, 'kind');
      final code = _text(row['code'], 1, kBackupMaxFulizaCodeLength, t, i, 'code');
      _int(row['occurred_at'], kBackupMinEpochMs, kBackupMaxEpochMs - 1, t, i, 'occurred_at');
      _int(row['amount_cents'], 1, kBackupMaxFulizaCents, t, i, 'amount_cents');
      _int(row['fee_cents'], 0, kBackupMaxFulizaCents, t, i, 'fee_cents');
      final printed = row['printed_total_cents'];
      if (printed != null) {
        _int(printed, 0, kBackupMaxFulizaCents, t, i, 'printed_total_cents');
      }
      // The same message twice in one file, like a repeated transaction code.
      if (!seen.add('$kind $code')) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'code');
      }
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // receiver_rules (schema >= 9)

  /// Exact 9 keys per row. Kind from the four codes, key 1..200 clean trimmed text, label as a
  /// receiver label, level 0..2, at most one of cat_seed (a built-in key) / cat_name, ceiling null
  /// or 1..100,000,000, ap 0 or 1, `sc` a list of chosen categories ([_chosenList]), no repeated
  /// (kind, key). A Paybill row at level 2 is accepted
  /// (the restore degrades it: refusing a whole backup for it would lose the person's data).
  static List<Map<String, Object?>> _receiverRules(List rows) {
    const t = 'receiver_rules';
    final out = <Map<String, Object?>>[];
    final seen = <String>{};
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], kBackupRuleKeys, t, i);
      final type = _enum(row['t'], kBackupRuleTypes, t, i, 't');
      final key = _text(row['k'], 1, kBackupMaxRuleKeyLength, t, i, 'k');
      _text(row['name'], 1, kBackupMaxLabelLength, t, i, 'name');
      _int(row['lv'], 0, kBackupMaxRuleLevel, t, i, 'lv');
      final seed = row['cat_seed'];
      final catName = row['cat_name'];
      if (seed != null && (seed is! String || !kBackupSeedKeys.contains(seed))) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'cat_seed');
      }
      if (catName != null) {
        _text(catName, 1, kBackupMaxClassificationNameLength, t, i, 'cat_name');
      }
      if (seed != null && catName != null) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'cat_name');
      }
      if (row['ceil'] != null) {
        _int(row['ceil'], kBackupMinCeilingCents, kBackupMaxCeilingCents, t, i, 'ceil');
      }
      _int(row['ap'], 0, 1, t, i, 'ap');
      _chosenList(row['sc'], t, i);
      if (!seen.add('$type\u0000$key')) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'k');
      }
      out.add(Map<String, Object?>.from(row));
    }
    return out;
  }

  /// A rule row's `sc` (0.2.2 item 2, B-BK; strict, PM 25-11): a list of at most
  /// [kBackupMaxChosenCategories] entries, each a map with exactly one key: `cat_seed` (a built-in
  /// key in [kBackupSeedKeys]) or `cat_name` (clean trimmed text, as the rule's own `cat_name`).
  /// Anything else refuses the file (field `sc`), like every other field of the row.
  static void _chosenList(Object? sc, String t, int i) {
    if (sc is! List || sc.length > kBackupMaxChosenCategories) {
      _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'sc');
    }
    for (final e in sc) {
      if (e is! Map || e.length != 1) {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'sc');
      }
      if (e.containsKey('cat_seed')) {
        final seed = e['cat_seed'];
        if (seed is! String || !kBackupSeedKeys.contains(seed)) {
          _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'sc');
        }
      } else if (e.containsKey('cat_name')) {
        _text(e['cat_name'], 1, kBackupMaxClassificationNameLength, t, i, 'sc');
      } else {
        _fail(RestoreRejectReason.invalidRow, table: t, rowIndex: i, field: 'sc');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // prefs

  /// Unknown keys are dropped (never applied, never an error); an allowlisted
  /// key with a wrong type or range rejects the whole file.
  ///
  /// The Fuliza limit is a schema >= 4 setting: an older file never carries it,
  /// so it is dropped (not applied) if one does.
  static Map<String, Object?> _prefs(Object? raw, int schemaVersion) {
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
      if (key == kFulizaLimitFileKey && schemaVersion < kBackupFirstSchemaWithFuliza) continue;
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

  /// Exactly [keys], plus any subset of [optional] and nothing else.
  static bool _hasKeys(Map m, List<String> keys, List<String> optional) {
    if (optional.isEmpty) return _hasExactKeys(m, keys);
    for (final k in keys) {
      if (!m.containsKey(k)) return false;
    }
    return m.keys.every((k) => keys.contains(k) || optional.contains(k));
  }

  static bool _hasExactKeys(Map m, List<String> keys) {
    if (m.length != keys.length) return false;
    for (final k in keys) {
      if (!m.containsKey(k)) return false;
    }
    return true;
  }

  static bool _isEpoch(Object? v) =>
      v is int && v >= kBackupMinEpochMs && v < kBackupMaxEpochMs;

  static Map _row(Object? raw, List<String> keys, String table, int i, {List<String> optional = const []}) {
    if (raw is! Map || !_hasKeys(raw, keys, optional)) {
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
