import '../../domain/counterparty/counterparty_key.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import 'backup_limits.dart';

/// One row left out of a backup, described WITHOUT its content: which table,
/// which row id, which field and which rule it broke. Safe to show and log.
class BackupSkippedRow {
  const BackupSkippedRow({
    required this.table,
    required this.rowId,
    required this.field,
    required this.rule,
  });

  final String table;

  /// The row's id in the database (null when it has none or it is unusable).
  final int? rowId;
  final String field;

  /// Short rule name, for example `empty`, `length`, `format`, `range`.
  final String rule;

  @override
  String toString() => '$table row ${rowId ?? '?'}: $field ($rule)';
}

class _Problem {
  const _Problem(this.field, this.rule);
  final String field;
  final String rule;
}

/// Repairs the exported COPY of the rows (never the database) so the backup
/// file passes the restore validator, and skips the rows that cannot be fixed.
///
/// Repairs (only on a value that breaks a rule): strip control and bidi
/// characters, turn tabs, newlines and no-break spaces into spaces, collapse
/// space runs, trim, cut to the length limit; a phone also gets its spacing
/// normalised. A row that still fails afterwards is skipped, with the table,
/// row id, field and rule recorded (never the value). Skipping a
/// classification also skips what points at it.
///
/// Rows are in file shape (see `backup_limits.dart`). A map row may carry an
/// extra `id` (used only for the report; the codec drops it).
class BackupRepair {
  BackupRepair({
    required List<Map<String, Object?>> classifications,
    required List<Map<String, Object?>> transactions,
    required List<Map<String, Object?>> counterpartyMap,
    required Set<String> enabledGroupCodes,
  })  : _enabled = enabledGroupCodes,
        classifications = [],
        transactions = [],
        counterpartyMap = [] {
    _run(classifications, transactions, counterpartyMap);
  }

  final Set<String> _enabled;

  /// The repaired, kept rows.
  final List<Map<String, Object?>> classifications;
  final List<Map<String, Object?>> transactions;
  final List<Map<String, Object?>> counterpartyMap;

  /// Rows that were changed and kept (a row counts once however many fields).
  int repairedCount = 0;
  final List<BackupSkippedRow> skipped = [];

  final Map<int, String> _groupById = {};
  final Set<int> _droppedClassIds = {};

  /// Skips the row at [index] of [table] (a row the validator still refused).
  /// A classification takes its transactions and map rows with it. Returns
  /// false when [index] is out of range.
  bool skipRow(String table, int index, String field, String rule) {
    final list = switch (table) {
      'classifications' => classifications,
      'transactions' => transactions,
      'counterparty_map' => counterpartyMap,
      _ => null,
    };
    if (list == null || index < 0 || index >= list.length) return false;
    final row = list.removeAt(index);
    final id = _idOf(row);
    skipped.add(BackupSkippedRow(table: table, rowId: id, field: field, rule: rule));
    if (table == 'classifications' && id != null) {
      _groupById.remove(id);
      _droppedClassIds.add(id);
      _cascade(id);
    }
    return true;
  }

  void _cascade(int classId) {
    for (final entry in [
      ('transactions', transactions),
      ('counterparty_map', counterpartyMap),
    ]) {
      for (var i = entry.$2.length - 1; i >= 0; i--) {
        if (entry.$2[i]['classification'] == classId) {
          final row = entry.$2.removeAt(i);
          skipped.add(BackupSkippedRow(
            table: entry.$1,
            rowId: _idOf(row),
            field: 'classification',
            rule: 'its classification was skipped',
          ));
        }
      }
    }
  }

  // ---------------------------------------------------------------------------

  void _run(
    List<Map<String, Object?>> classes,
    List<Map<String, Object?>> txs,
    List<Map<String, Object?>> map,
  ) {
    final ids = <int>{};
    final seeds = <String>{};
    final activeNames = <String>{};
    for (final src in classes) {
      final row = Map<String, Object?>.of(src);
      var changed = _fix(row, 'name', kBackupMaxClassificationNameLength);
      changed |= _makeNameUnique(row, activeNames);
      final p =_classProblem(row, ids, seeds, activeNames);
      if (p != null) {
        _drop('classifications', row, p);
        final id = _idOf(row);
        if (id != null) _droppedClassIds.add(id);
        continue;
      }
      _groupById[row['id']! as int] = row['group']! as String;
      if (changed) repairedCount++;
      classifications.add(row);
    }

    final txIds = <int>{};
    for (final src in txs) {
      final row = Map<String, Object?>.of(src);
      var changed = _fix(row, 'counterparty_label', kBackupMaxLabelLength);
      changed |= _fix(row, 'paybill_account_number', kBackupMaxPaybillAccountLength);
      changed |= _fixPhone(row);
      changed |= _fixCode(row);
      final p = _txProblem(row, txIds);
      if (p != null) {
        _drop('transactions', row, p);
        continue;
      }
      if (changed) {
        repairedCount++;
        _noteKeyRewrite(src, row);
      }
      transactions.add(row);
    }

    for (final src in map) {
      final row = Map<String, Object?>.of(src);
      // A key the app derived from a transaction we repaired follows that
      // transaction's repaired fields, so the two still agree.
      final rewritten = _keyRewrites['${row['source_type']}\u0000${row['counterparty_key']}'];
      var changed = false;
      if (rewritten != null) {
        row['counterparty_key'] = rewritten;
        changed = true;
      }
      changed |= _fix(row, 'counterparty_key', kBackupMaxCounterpartyKeyLength);
      final p = _mapProblem(row);
      if (p != null) {
        _drop('counterparty_map', row, p);
        continue;
      }
      if (changed) repairedCount++;
      counterpartyMap.add(row);
    }
  }

  void _drop(String table, Map<String, Object?> row, _Problem p) => skipped.add(
        BackupSkippedRow(table: table, rowId: _idOf(row), field: p.field, rule: p.rule),
      );

  static int? _idOf(Map<String, Object?> row) {
    final id = row['id'];
    return id is int ? id : null;
  }

  // --- repairs ----------------------------------------------------------------

  /// `source\0oldKey` -> newKey, for transactions whose identity fields were
  /// repaired (the app's own `deriveCounterpartyKey` on before and after).
  final Map<String, String> _keyRewrites = {};

  static String? _deriveKey(Map<String, Object?> r) {
    final SmsSourceType t;
    switch (r['source_type']) {
      case 'SEND_MONEY':
        t = SmsSourceType.sendMoney;
      case 'PAYBILL':
        t = SmsSourceType.payBill;
      case 'BUY_GOODS':
        t = SmsSourceType.buyGoods;
      default:
        return null;
    }
    String? s(String k) => r[k] is String ? r[k]! as String : null;
    return deriveCounterpartyKey(
      sourceType: t,
      counterpartyLabel: s('counterparty_label'),
      counterpartyPhone: s('counterparty_phone'),
      paybillAccountNumber: s('paybill_account_number'),
    );
  }

  void _noteKeyRewrite(Map<String, Object?> before, Map<String, Object?> after) {
    final oldKey = _deriveKey(before);
    final newKey = _deriveKey(after);
    if (oldKey == null || newKey == null || oldKey == newKey || oldKey.isEmpty) return;
    _keyRewrites['${after['source_type']}\u0000$oldKey'] = newKey;
  }

  /// A later active class whose cleaned name collides with an earlier one in
  /// the same group becomes "Name (2)", "Name (3)" ... (base cut to fit), so
  /// it and its transactions are kept. True when renamed.
  bool _makeNameUnique(Map<String, Object?> row, Set<String> activeNames) {
    final group = row['group'];
    final name = row['name'];
    if (row['active'] != 1 || group is! String || name is! String || name.isEmpty) {
      return false;
    }
    if (!activeNames.contains('$group\u0000$name')) return false;
    for (var n = 2;; n++) {
      final suffix = ' ($n)';
      final room = kBackupMaxClassificationNameLength - suffix.length;
      var base = name.length > room ? name.substring(0, room) : name;
      if (base.isNotEmpty && base.codeUnitAt(base.length - 1) >= 0xD800 &&
          base.codeUnitAt(base.length - 1) <= 0xDBFF) {
        base = base.substring(0, base.length - 1);
      }
      final candidate = '${base.trim()}$suffix';
      if (!activeNames.contains('$group\u0000$candidate')) {
        row['name'] = candidate;
        return true;
      }
    }
  }

  static bool _textOk(String s, int max) =>
      s.isNotEmpty && s.length <= max && s == s.trim() && backupTextIsClean(s);

  /// Cleaned copy of [s]: whitespace-like characters become spaces, control
  /// and bidi characters go, space runs collapse, trimmed, cut to [max]
  /// (never inside a surrogate pair).
  static String cleanText(String s, int max) {
    final b = StringBuffer();
    var lastSpace = true; // drops leading spaces
    for (final c in s.codeUnits) {
      final isSpace = c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0B ||
          c == 0x0C || c == 0x0D || c == 0xA0 || c == 0x2028 || c == 0x2029;
      if (isSpace) {
        if (!lastSpace) b.writeCharCode(0x20);
        lastSpace = true;
        continue;
      }
      final unit = String.fromCharCode(c);
      if (!backupTextIsClean(unit)) continue;
      b.writeCharCode(c);
      lastSpace = false;
    }
    var out = b.toString().trim();
    if (out.length > max) {
      var cut = max;
      final last = out.codeUnitAt(cut - 1);
      if (last >= 0xD800 && last <= 0xDBFF) cut--; // do not split a pair
      out = out.substring(0, cut).trim();
    }
    return out;
  }

  /// Repairs [field] in place when it is a string breaking the text rules.
  /// True when it changed.
  bool _fix(Map<String, Object?> row, String field, int max) {
    final v = row[field];
    if (v is! String || _textOk(v, max)) return false;
    final fixed = cleanText(v, max);
    row[field] = fixed;
    return fixed != v;
  }

  bool _fixPhone(Map<String, Object?> row) {
    final v = row['counterparty_phone'];
    if (v is! String || kBackupPhonePattern.hasMatch(v)) return false;
    // Spacing first, then harmless punctuation (dashes, dots, brackets,
    // slashes, commas, underscores) goes; a leading + and the digits stay.
    final fixed = cleanText(v, kBackupMaxLabelLength)
        .replaceAll(RegExp(r'[-.()\[\]{}/\\,_]'), '')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
    if (fixed == v) return false;
    row['counterparty_phone'] = fixed;
    return true;
  }

  bool _fixCode(Map<String, Object?> row) {
    final v = row['display_code'];
    if (v is! String) return false;
    final ok = row['source_type'] == 'CASH'
        ? kBackupCashCodePattern
        : kBackupMpesaCodePattern;
    if (ok.hasMatch(v)) return false;
    // M-Pesa and cash codes are upper case; whitespace and control characters go.
    final fixed =
        v.replaceAll(RegExp(r'[\s\u0000-\u001F\u007F-\u009F]'), '').toUpperCase();
    if (fixed == v) return false;
    row['display_code'] = fixed;
    return true;
  }

  // --- checks (mirror BackupValidator; the service re-validates as a backstop)

  static bool _isInt(Object? v, int min, int max) => v is int && v >= min && v <= max;
  static bool _isEpoch(Object? v) =>
      _isInt(v, kBackupMinEpochMs, kBackupMaxEpochMs - 1);

  /// Why a text field fails after repair: `empty`, `length` or `characters`.
  static _Problem? _text(Object? v, String field, int max, {bool nullable = false}) {
    if (v == null) return nullable ? null : _Problem(field, 'missing');
    if (v is! String) return _Problem(field, 'type');
    if (v.isEmpty) return _Problem(field, 'empty');
    if (v.length > max) return _Problem(field, 'length');
    if (!_textOk(v, max)) return _Problem(field, 'characters');
    return null;
  }

  _Problem? _classProblem(
    Map<String, Object?> row,
    Set<int> ids,
    Set<String> seeds,
    Set<String> activeNames,
  ) {
    final id = row['id'];
    if (!_isInt(id, 1, kBackupMaxClassificationFileId)) return const _Problem('id', 'range');
    if (!ids.add(id! as int)) return const _Problem('id', 'duplicate');
    final group = row['group'];
    if (group is! String || !kBackupGroupCodes.contains(group)) {
      return const _Problem('group', 'unknown value');
    }
    final name = _text(row['name'], 'name', kBackupMaxClassificationNameLength);
    if (name != null) return name;
    if (!_isInt(row['active'], 0, 1)) return const _Problem('active', 'range');
    final seed = row['seed_key'];
    if (seed != null) {
      if (seed is! String || !kBackupSeedKeys.contains(seed) || !seed.startsWith('$group:')) {
        return const _Problem('seed_key', 'format');
      }
      if (!seeds.add(seed)) return const _Problem('seed_key', 'duplicate');
    }
    if (!_isEpoch(row['created_at'])) return const _Problem('created_at', 'range');
    if (row['active'] == 1 && !activeNames.add('$group\u0000${row['name']}')) {
      return const _Problem('name', 'duplicate');
    }
    return null;
  }

  _Problem? _txProblem(Map<String, Object?> row, Set<int> ids) {
    final id = row['id'];
    if (!_isInt(id, 1, 9007199254740991)) return const _Problem('id', 'range');
    if (!ids.add(id! as int)) return const _Problem('id', 'duplicate');
    final source = row['source_type'];
    if (source is! String || !kBackupSourceTypes.contains(source)) {
      return const _Problem('source_type', 'unknown value');
    }
    final isCash = source == 'CASH';
    final code = row['display_code'];
    if (code is! String ||
        !(isCash ? kBackupCashCodePattern : kBackupMpesaCodePattern).hasMatch(code)) {
      return const _Problem('display_code', 'format');
    }
    if (!_isInt(row['amount_cents'], 1, kBackupMaxAmountCents)) {
      return const _Problem('amount_cents', 'range');
    }
    final cost = row['transaction_cost_cents'];
    if (isCash ? cost != null : !_isInt(cost, 0, kBackupMaxCostCents)) {
      return const _Problem('transaction_cost_cents', 'range');
    }
    final label = row['counterparty_label'];
    final phone = row['counterparty_phone'];
    final account = row['paybill_account_number'];
    if (label != null) {
      if (isCash) return const _Problem('counterparty_label', 'not allowed for source');
      final p = _text(label, 'counterparty_label', kBackupMaxLabelLength);
      if (p != null) return p;
    }
    if (phone != null &&
        (source != 'SEND_MONEY' || phone is! String || !kBackupPhonePattern.hasMatch(phone))) {
      return const _Problem('counterparty_phone', 'format');
    }
    if (account != null) {
      if (source != 'PAYBILL') return const _Problem('paybill_account_number', 'not allowed for source');
      final p = _text(account, 'paybill_account_number', kBackupMaxPaybillAccountLength);
      if (p != null) return p;
    }
    if (source == 'SEND_MONEY' && (label == null) != (phone == null)) {
      return const _Problem('counterparty_phone', 'paired with label');
    }
    if (source == 'PAYBILL' && (label == null) != (account == null)) {
      return const _Problem('paybill_account_number', 'paired with label');
    }
    final raw = row['raw_parse_source'];
    if (raw is! String || !kBackupRawParseSources.contains(raw)) {
      return const _Problem('raw_parse_source', 'unknown value');
    }
    if (isCash && raw != 'MANUAL') return const _Problem('raw_parse_source', 'not allowed for source');
    if (!_isEpoch(row['transaction_occurred_at'])) {
      return const _Problem('transaction_occurred_at', 'range');
    }
    if (!_isEpoch(row['created_at'])) return const _Problem('created_at', 'range');
    final ref = _classRef(row['classification']);
    if (ref != null) return ref;
    final group = _groupById[row['classification']];
    if (isCash) {
      if (!_enabled.contains(group)) return const _Problem('classification', 'group is switched off');
    } else if (group != source) {
      return const _Problem('classification', 'group does not match');
    }
    return null;
  }

  _Problem? _mapProblem(Map<String, Object?> row) {
    final source = row['source_type'];
    if (source is! String || !kBackupMapSourceTypes.contains(source)) {
      return const _Problem('source_type', 'unknown value');
    }
    final key = row['counterparty_key'];
    final p = _text(key, 'counterparty_key', kBackupMaxCounterpartyKeyLength);
    if (p != null) return p;
    if (source == 'PAYBILL' && !(key! as String).contains('#')) {
      return const _Problem('counterparty_key', 'format');
    }
    if (!_isInt(row['auto_apply'], 0, 1)) return const _Problem('auto_apply', 'range');
    if (!_isEpoch(row['updated_at'])) return const _Problem('updated_at', 'range');
    final ref = _classRef(row['classification']);
    if (ref != null) return ref;
    if (_groupById[row['classification']] != source) {
      return const _Problem('classification', 'group does not match');
    }
    return null;
  }

  _Problem? _classRef(Object? id) {
    if (id is! int) return const _Problem('classification', 'type');
    if (_groupById.containsKey(id)) return null;
    return _Problem(
      'classification',
      _droppedClassIds.contains(id) ? 'its classification was skipped' : 'dangling reference',
    );
  }
}
