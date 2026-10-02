// B10: the restore validator (Stage 1). Pure Dart, no database; adversarial
// files, table-driven field checks, and an export-then-validate round trip.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_codec.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_validator.dart';

import '../../support/backup_test_data.dart';

/// Runs [fn] and expects a [RestoreRejected] with [reason]; optionally also
/// the table and field it names. Returns the exception for further checks.
RestoreRejected _rejected(
  void Function() fn,
  RestoreRejectReason reason, {
  String? table,
  String? field,
}) {
  try {
    fn();
  } on RestoreRejected catch (e) {
    expect(e.reason, reason, reason: e.toString());
    if (table != null) expect(e.table, table, reason: e.toString());
    if (field != null) expect(e.field, field, reason: e.toString());
    return e;
  }
  fail('expected RestoreRejected($reason) but the file was accepted');
}

RestoreRejected _rejectJson(
  Map<String, Object?> json,
  RestoreRejectReason reason, {
  String? table,
  String? field,
}) =>
    _rejected(() => BackupValidator.validate(bytesOf(json)), reason,
        table: table, field: field);

void main() {
  group('accept', () {
    test('accept_valid_realistic_file', () {
      final j = validBackupJson();
      final v = BackupValidator.validate(bytesOf(j));
      expect(v.formatVersion, 1);
      expect(v.schemaVersion, 2);
      expect(v.createdAt, tBase);
      expect(v.classifications, rowsOf(j, 'classifications'));
      expect(v.transactions, rowsOf(j, 'transactions'));
      expect(v.counterpartyMap, rowsOf(j, 'counterparty_map'));
      expect(v.prefs, {'palette_id': 'leaf', 'user_display_name': 'Amina'});
    });

    test('two CASH rows sharing a code but not created_at are fine', () {
      // (the fixture has exactly that)
      final v = BackupValidator.validate(bytesOf(validBackupJson()));
      final cash = v.transactions.where((t) => t['source_type'] == 'CASH');
      expect(cash.length, 2);
      expect(cash.map((t) => t['display_code']).toSet().length, 1);
    });

    test('an empty backup (no rows at all) is valid', () {
      final j = validBackupJson()
        ..['classifications'] = []
        ..['transactions'] = []
        ..['counterparty_map'] = []
        ..['prefs'] = {};
      fixCounts(j);
      final v = BackupValidator.validate(bytesOf(j));
      expect(v.transactions, isEmpty);
    });

    test('an inactive duplicate (group,name) is fine, two active are not', () {
      final j = validBackupJson();
      rowsOf(j, 'classifications').add({
        'id': 6, 'group': 'SEND_MONEY', 'name': 'School fees', 'active': 0,
        'seed_key': null, 'created_at': tBase,
      });
      fixCounts(j);
      expect(() => BackupValidator.validate(bytesOf(j)), returnsNormally);
    });

    test('names with spaces inside, emoji and zero-width joiner are text', () {
      final j = validBackupJson();
      rowsOf(j, 'classifications')[3]['name'] = 'Mum\u2019s \u{1F468}\u200D\u{1F469} fund';
      expect(() => BackupValidator.validate(bytesOf(j)), returnsNormally);
    });

    test('boundary values are accepted', () {
      final j = validBackupJson();
      final tx = rowsOf(j, 'transactions')[0];
      tx['amount_cents'] = kBackupMaxAmountCents;
      tx['transaction_cost_cents'] = kBackupMaxCostCents;
      tx['counterparty_label'] = 'L' * kBackupMaxLabelLength;
      tx['transaction_occurred_at'] = kBackupMinEpochMs;
      tx['created_at'] = kBackupMaxEpochMs - 1;
      rowsOf(j, 'classifications')[3]['name'] = 'N' * kBackupMaxClassificationNameLength;
      expect(() => BackupValidator.validate(bytesOf(j)), returnsNormally);
    });
  });

  group('envelope', () {
    test('reject_foreign_app_marker', () {
      for (final bad in <Object?>['other', 'MMOGO', 'mmogo ', '', 1, null, true]) {
        final j = validBackupJson()..['app'] = bad;
        _rejectJson(j, RestoreRejectReason.notMmogo, field: 'app');
      }
      final noApp = validBackupJson()..remove('app');
      _rejectJson(noApp, RestoreRejectReason.notMmogo);
      // A completely foreign JSON document.
      _rejected(() => BackupValidator.validate(bytesOf({'transactions': [], 'bank': 'x'})),
          RestoreRejectReason.notMmogo);
    });

    test('reject_newer_schema_version', () {
      for (final v in [3, 4, 99, 2147483647]) {
        _rejectJson(validBackupJson()..['schema_version'] = v,
            RestoreRejectReason.newer, field: 'schema_version');
      }
      for (final v in [2, 3, 50]) {
        // format_version above 1 is newer too
        _rejectJson(validBackupJson()..['format_version'] = v,
            RestoreRejectReason.newer, field: 'format_version');
      }
      // A newer file may carry keys this build has never seen: still "newer".
      final future = validBackupJson()
        ..['format_version'] = 2
        ..['shiny_new_section'] = [1, 2, 3];
      _rejectJson(future, RestoreRejectReason.newer);
    });

    test('reject_wrong_version_types_and_values (not "newer")', () {
      for (final v in <Object?>[0, -1, '1', 1.5, 1.0, null, true, [1]]) {
        _rejectJson(validBackupJson()..['format_version'] = v,
            RestoreRejectReason.corrupt, field: 'format_version');
      }
      for (final v in <Object?>[0, 1, -2, '2', 2.0, 2.5, null, false]) {
        _rejectJson(validBackupJson()..['schema_version'] = v,
            RestoreRejectReason.corrupt, field: 'schema_version');
      }
    });

    test('top-level keys must be exactly the documented set', () {
      for (final k in kBackupTopLevelKeys.where((k) => k != 'app')) {
        final missing = validBackupJson()..remove(k);
        _rejectJson(missing, RestoreRejectReason.corrupt);
      }
      _rejectJson(validBackupJson()..['auto_backup_folder_uri'] = 'content://evil',
          RestoreRejectReason.corrupt, field: '(keys)');
    });

    test('end marker missing or wrong means a truncated or altered file', () {
      for (final v in <Object?>['', 'mmogo-v2', null, 1]) {
        _rejectJson(validBackupJson()..['end'] = v, RestoreRejectReason.corrupt, field: 'end');
      }
    });

    test('created_at must be an epoch in range', () {
      for (final v in <Object?>[0, kBackupMinEpochMs - 1, kBackupMaxEpochMs, '1', 1.5, null]) {
        _rejectJson(validBackupJson()..['created_at'] = v,
            RestoreRejectReason.corrupt, field: 'created_at');
      }
    });

    test('reject_counts_mismatch_truncated', () {
      final j = validBackupJson();
      (j['counts']! as Map)['transactions'] = 6;
      _rejectJson(j, RestoreRejectReason.corrupt, field: 'counts');
      final j2 = validBackupJson();
      rowsOf(j2, 'transactions').removeLast(); // truncated array, counts say 5
      _rejectJson(j2, RestoreRejectReason.corrupt, field: 'counts');
      for (final bad in <Object?>[null, 'x', [], {'classifications': 5}]) {
        _rejectJson(validBackupJson()..['counts'] = bad, RestoreRejectReason.corrupt, field: 'counts');
      }
      final j3 = validBackupJson();
      (j3['counts']! as Map)['transactions'] = 5.0;
      _rejectJson(j3, RestoreRejectReason.corrupt, field: 'counts');
    });

    test('arrays must be arrays', () {
      for (final k in ['classifications', 'transactions', 'counterparty_map']) {
        _rejectJson(validBackupJson()..[k] = {'a': 1}, RestoreRejectReason.corrupt, field: k);
        _rejectJson(validBackupJson()..[k] = 'x', RestoreRejectReason.corrupt, field: k);
      }
    });
  });

  group('raw bytes', () {
    test('reject_corrupt_json (empty, truncated, garbage, bad utf8, array root)', () {
      for (final bytes in <Uint8List>[
        Uint8List(0),
        Uint8List.fromList(utf8.encode('{"app":"mmogo"')), // truncated
        Uint8List.fromList(utf8.encode('not json at all')),
        Uint8List.fromList([0x7B, 0xFF, 0xFE, 0x7D]), // invalid UTF-8
        Uint8List.fromList(utf8.encode('[]')),
        Uint8List.fromList(utf8.encode('"mmogo"')),
        Uint8List.fromList(utf8.encode('null')),
        Uint8List.fromList(utf8.encode('${jsonEncode(validBackupJson())} trailing')),
        Uint8List.fromList(utf8.encode('{"app":"mmogo",}')),
      ]) {
        _rejected(() => BackupValidator.validate(bytes), RestoreRejectReason.corrupt);
      }
      // A UTF-8 byte-order mark is skipped by the UTF-8 decoder: a good file
      // saved with one is still read, and a BOM'd foreign file is "not mmogo".
      final bom = [0xEF, 0xBB, 0xBF];
      expect(
        () => BackupValidator.validate(
            Uint8List.fromList([...bom, ...bytesOf(validBackupJson())])),
        returnsNormally,
      );
      _rejected(
          () => BackupValidator.validate(Uint8List.fromList([...bom, ...utf8.encode('{}')])),
          RestoreRejectReason.notMmogo);
      // Truncating a good file anywhere is corrupt, never accepted.
      final good = bytesOf(validBackupJson());
      for (final cut in [1, good.length ~/ 2, good.length - 1]) {
        _rejected(() => BackupValidator.validate(Uint8List.sublistView(good, 0, cut)),
            RestoreRejectReason.corrupt);
      }
    });

    test('reject_deeply_nested_json', () {
      // 1,000,000 nested arrays: refused cleanly, no crash, no stack overflow.
      final deep = Uint8List.fromList(List.filled(1000000, 0x5B));
      final sw = Stopwatch()..start();
      _rejected(() => BackupValidator.validate(deep), RestoreRejectReason.corrupt, field: 'depth');
      expect(sw.elapsedMilliseconds, lessThan(2000));
      // Balanced, deep objects too.
      final nested = '${'{"a":' * 200000}1${'}' * 200000}';
      _rejected(() => BackupValidator.validate(Uint8List.fromList(utf8.encode(nested))),
          RestoreRejectReason.corrupt, field: 'depth');
      // One level over the limit is refused; brackets inside strings do not count.
      final nine = '${'[' * (kBackupMaxJsonDepth + 1)}${']' * (kBackupMaxJsonDepth + 1)}';
      _rejected(() => BackupValidator.validate(Uint8List.fromList(utf8.encode(nine))),
          RestoreRejectReason.corrupt, field: 'depth');
      final j = validBackupJson();
      rowsOf(j, 'classifications')[3]['name'] = '[[[[[[[[[[[[[[[[[[[[ \\" ]]]]]]]]]]]]]]]]]]]]';
      expect(() => BackupValidator.validate(bytesOf(j)), returnsNormally);
    });

    test('depth scan is informational: what does jsonDecode do alone at 100k?', () {
      // Amendment 4: the validator pre-scans depth either way, so it never
      // relies on this. Recorded for the report.
      final deep = '${'[' * 100000}${']' * 100000}';
      String outcome;
      try {
        jsonDecode(deep);
        outcome = 'jsonDecode survives 100,000-deep nesting on its own';
      } catch (e) {
        outcome = 'jsonDecode fails on 100,000-deep nesting: ${e.runtimeType}';
      }
      // ignore: avoid_print
      print(outcome);
      expect(outcome, isNotEmpty);
    });

    test('reject_over_20mb_stream_aborts', () async {
      // A stream far longer than the cap is cut off at the cap, not read to
      // the end.
      var pulled = 0;
      Stream<List<int>> endless() async* {
        while (true) {
          pulled++;
          yield Uint8List(65536);
        }
      }

      await expectLater(
        BackupValidator.readCapped(endless()),
        throwsA(isA<RestoreRejected>()
            .having((e) => e.reason, 'reason', RestoreRejectReason.tooLarge)),
      );
      final maxChunks = kBackupMaxBytes ~/ 65536 + 1;
      expect(pulled, lessThanOrEqualTo(maxChunks + 1), reason: 'stopped at the cap');
      expect(pulled, greaterThan(maxChunks - 2));

      // A lying size (reports 1 KB) is covered by the running count.
      pulled = 0;
      await expectLater(
        BackupValidator.readCapped(endless(), declaredSize: 1024),
        throwsA(isA<RestoreRejected>()),
      );
      expect(pulled, lessThanOrEqualTo(maxChunks + 1));

      // An honest oversize report is refused before reading anything.
      pulled = 0;
      await expectLater(
        BackupValidator.readCapped(endless(), declaredSize: kBackupMaxBytes + 1),
        throwsA(isA<RestoreRejected>()),
      );
      expect(pulled, 0);

      // Exactly the cap is allowed through the reader.
      final ok = await BackupValidator.readCapped(Stream.fromIterable([
        Uint8List(kBackupMaxBytes ~/ 2),
        Uint8List(kBackupMaxBytes ~/ 2),
      ]));
      expect(ok.length, kBackupMaxBytes);
      // Small file reads whole.
      final small = await BackupValidator.readCapped(Stream.fromIterable([
        [1, 2],
        [3],
      ]));
      expect(small, [1, 2, 3]);
    });

    test('over 20 MB bytes are refused before any parsing; exactly 20 MB is not "too large"', () {
      _rejected(() => BackupValidator.validate(Uint8List(kBackupMaxBytes + 1)),
          RestoreRejectReason.tooLarge);
      _rejected(() => BackupValidator.validate(Uint8List(kBackupMaxBytes)),
          RestoreRejectReason.corrupt);
    });

    test('reject_over_row_caps', () {
      List<Object?> empties(int n) => List<Object?>.generate(n, (_) => <String, Object?>{});
      Map<String, Object?> withCount(String table, int n) {
        final j = validBackupJson();
        j[table] = empties(n);
        fixCounts(j);
        return j;
      }

      _rejectJson(withCount('transactions', kBackupMaxTransactions + 1),
          RestoreRejectReason.tooMany, table: 'transactions');
      _rejectJson(withCount('classifications', kBackupMaxClassifications + 1),
          RestoreRejectReason.tooMany, table: 'classifications');
      _rejectJson(withCount('counterparty_map', kBackupMaxMapRows + 1),
          RestoreRejectReason.tooMany, table: 'counterparty_map');
      // Exactly at the cap is NOT too many (these empty rows then fail as rows).
      _rejectJson(withCount('transactions', kBackupMaxTransactions),
          RestoreRejectReason.invalidRow);
      // A liar whose counts say "small" over a huge array is still tooMany.
      final liar = validBackupJson()..['transactions'] = empties(kBackupMaxTransactions + 1);
      _rejectJson(liar, RestoreRejectReason.tooMany, table: 'transactions');
      // prefs key cap
      final prefs = validBackupJson()
        ..['prefs'] = {for (var i = 0; i <= kBackupMaxPrefsKeys; i++) 'k$i': 1};
      _rejectJson(prefs, RestoreRejectReason.invalidRow, table: 'prefs');
    });

    test('accept_20mb_realistic_and_reject_extreme_history', () {
      Uint8List build(int n, {required int labelLen, required int accountLen}) {
        final rows = <Map<String, Object?>>[];
        for (var i = 0; i < n; i++) {
          final isPay = i % 3 == 0;
          rows.add({
            'id': i + 1,
            'display_code': 'Z${i.toString().padLeft(9, '0')}',
            'source_type': isPay ? 'PAYBILL' : 'SEND_MONEY',
            'amount_cents': 1000 + i,
            'transaction_cost_cents': 500,
            'counterparty_label': ('R$i ').padRight(labelLen, 'N'),
            'counterparty_phone': isPay ? null : '0712${(100000 + i)}',
            'paybill_account_number': isPay ? 'A' * accountLen : null,
            'classification': isPay ? 2 : 1,
            'raw_parse_source': 'SMS_PARSE',
            'transaction_occurred_at': tBase + i,
            'created_at': tBase + i,
          });
        }
        final j = validBackupJson();
        return BackupCodec.encode(
          createdAtMs: tBase,
          classifications: rowsOf(j, 'classifications'),
          transactions: rows,
          counterpartyMap: const [],
        );
      }

      // Realistic heavy use: 50,000 entries (the row cap) with ordinary names.
      final realistic = build(50000, labelLen: 40, accountLen: 10);
      expect(realistic.length, lessThan(kBackupMaxBytes));
      final sw = Stopwatch()..start();
      final v = BackupValidator.validate(realistic);
      sw.stop();
      expect(v.transactions.length, 50000);
      // ignore: avoid_print
      print('50,000 realistic rows: ${realistic.length} bytes, validated in ${sw.elapsedMilliseconds} ms');

      // Extreme history: 50,000 entries at the field-length limits is over 20 MB.
      final extreme = build(50000, labelLen: kBackupMaxLabelLength, accountLen: kBackupMaxPaybillAccountLength);
      expect(extreme.length, greaterThan(kBackupMaxBytes));
      _rejected(() => BackupValidator.validate(extreme), RestoreRejectReason.tooLarge);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('reject_bad_type_range_length_enum_date', () {
    // Each case is one named mutation of an otherwise valid file.
    const longName = 'x';
    final cases = <String, Map<String, List<Object?>>>{
      'classifications': {
        'id': [0, -1, 2147483648, 1.5, '1', null, true, [1]],
        'group': ['OTHER', 'send_money', '', 1, null],
        'name': ['', ' ', ' a', 'a ', longName * 101, 'a\nb', 'a\u202Eb', 'a\u200Fb', 'a\u0000b', 'a\u0085b', 'a\u007Fb', 'a\tb', 5, null],
        'active': [2, -1, 1.0, '1', true, null],
        'seed_key': ['SEND_MONEY:nope', 'PAYBILL:rent_payment', '', 5, ' SEND_MONEY:rent'],
        'created_at': [0, kBackupMinEpochMs - 1, kBackupMaxEpochMs, '1', 1.5, null],
      },
      'transactions': {
        'id': [0, -3, '1', 1.5, null],
        'display_code': ['ab12cd34ef', 'AB12CD34E', 'AB12CD34EFG', 'AB12CD34E!', 'AB12CD34E ', 'CASH-20260921-1030', '', 5, null],
        'source_type': ['X', 'cash', '', 1, null],
        'amount_cents': [0, -5, kBackupMaxAmountCents + 1, 1.5, '100', null, true],
        'transaction_cost_cents': [-1, kBackupMaxCostCents + 1, null, 1.5, '5'],
        'counterparty_label': ['', ' ', ' a', 'a ', 'x' * 201, 'a\nb', 'a\u200Eb', 'a\u2066b', 5],
        'counterparty_phone': ['abc', '123456', '1' * 21, '0712-345678', '0712345678\n', '', 5, true],
        'classification': ['1', 1.5, null, true, [1]],
        'raw_parse_source': ['OTHER', 'sms_parse', '', 1, null],
        'transaction_occurred_at': [0, kBackupMinEpochMs - 1, kBackupMaxEpochMs, '1', 1.5, null],
        'created_at': [0, kBackupMinEpochMs - 1, kBackupMaxEpochMs, '1', 1.5, null],
      },
      'counterparty_map': {
        'source_type': ['CASH', 'X', '', 1, null],
        'counterparty_key': ['', ' ', ' a', 'x' * 311, 'a\nb', 'a\u202Eb', 5, null],
        'classification': ['1', 1.5, null, true],
        'auto_apply': [2, -1, '1', true, null, 0.0],
        'updated_at': [0, kBackupMinEpochMs - 1, kBackupMaxEpochMs, '1', 1.5, null],
      },
    };

    for (final table in cases.keys) {
      for (final field in cases[table]!.keys) {
        final values = cases[table]![field]!;
        for (var i = 0; i < values.length; i++) {
          final value = values[i];
          test('$table.$field bad case #$i (${value.runtimeType})', () {
            final j = validBackupJson();
            rowsOf(j, table)[0][field] = value;
            final e = _rejected(() => BackupValidator.validate(bytesOf(j)),
                RestoreRejectReason.invalidRow, table: table, field: field);
            // The rejection names the place, never the value.
            if (value is String && value.trim().length > 3) {
              expect(e.toString().contains(value), isFalse);
            }
          });
        }
      }
    }

    test('PAYBILL fields: account length and blank, key without #', () {
      for (final bad in <Object?>['', ' x', 'x ', 'a' * 101, 7]) {
        final j = validBackupJson();
        rowsOf(j, 'transactions')[1]['paybill_account_number'] = bad;
        _rejectJson(j, RestoreRejectReason.invalidRow, table: 'transactions', field: 'paybill_account_number');
      }
      final j = validBackupJson();
      rowsOf(j, 'counterparty_map')[1]['counterparty_key'] = 'KPLC12345';
      _rejectJson(j, RestoreRejectReason.invalidRow, table: 'counterparty_map', field: 'counterparty_key');
    });

    test('every row key is required and no extra key is allowed', () {
      final tables = {
        'classifications': kBackupClassificationKeys,
        'transactions': kBackupTransactionKeys,
        'counterparty_map': kBackupMapKeys,
      };
      for (final entry in tables.entries) {
        for (final k in entry.value) {
          final missing = validBackupJson();
          rowsOf(missing, entry.key)[0].remove(k);
          _rejectJson(missing, RestoreRejectReason.invalidRow, table: entry.key, field: '(keys)');
        }
        for (final extra in ['deleted_at', 'extra', 'id2', '']) {
          final j = validBackupJson();
          rowsOf(j, entry.key)[0][extra] = 1;
          _rejectJson(j, RestoreRejectReason.invalidRow, table: entry.key, field: '(keys)');
        }
        for (final notARow in <Object?>[null, 5, 'row', [1], []]) {
          final j = validBackupJson();
          (j[entry.key]! as List)[0] = notARow;
          _rejectJson(j, RestoreRejectReason.invalidRow, table: entry.key);
        }
      }
    });

    test('CHECK mirrors: cost, label, phone, account by source type', () {
      Map<String, Object?> edit(int row, Map<String, Object?> changes) {
        final j = validBackupJson();
        rowsOf(j, 'transactions')[row].addAll(changes);
        return j;
      }

      // CASH: cost must be null, no label/phone/account, must be MANUAL.
      for (final changes in <Map<String, Object?>>[
        {'transaction_cost_cents': 0},
        {'counterparty_label': 'X'},
        {'counterparty_phone': '0712345678'},
        {'paybill_account_number': 'A'},
        {'raw_parse_source': 'SMS_PARSE'},
      ]) {
        _rejectJson(edit(3, changes), RestoreRejectReason.invalidRow, table: 'transactions');
      }
      // SEND_MONEY: label and phone both set or both null; no account.
      _rejectJson(edit(0, {'counterparty_phone': null}), RestoreRejectReason.invalidRow, field: 'counterparty_phone');
      _rejectJson(edit(0, {'counterparty_label': null}), RestoreRejectReason.invalidRow, field: 'counterparty_phone');
      _rejectJson(edit(0, {'paybill_account_number': 'A'}), RestoreRejectReason.invalidRow, field: 'paybill_account_number');
      expect(() => BackupValidator.validate(bytesOf(edit(0, {'counterparty_label': null, 'counterparty_phone': null}))), returnsNormally);
      // PAYBILL: label and account both set or both null; no phone.
      _rejectJson(edit(1, {'paybill_account_number': null}), RestoreRejectReason.invalidRow, field: 'paybill_account_number');
      _rejectJson(edit(1, {'counterparty_label': null}), RestoreRejectReason.invalidRow, field: 'paybill_account_number');
      _rejectJson(edit(1, {'counterparty_phone': '0712345678'}), RestoreRejectReason.invalidRow, field: 'counterparty_phone');
      // BUY_GOODS: label optional, never phone/account.
      expect(() => BackupValidator.validate(bytesOf(edit(2, {'counterparty_label': 'SHOP'}))), returnsNormally);
      _rejectJson(edit(2, {'counterparty_phone': '0712345678'}), RestoreRejectReason.invalidRow);
      _rejectJson(edit(2, {'paybill_account_number': 'A'}), RestoreRejectReason.invalidRow);
      // Non-CASH cost is required.
      _rejectJson(edit(0, {'transaction_cost_cents': null}), RestoreRejectReason.invalidRow, field: 'transaction_cost_cents');
    });
  });

  group('cross-row rules', () {
    test('reject_dangling_classification_ref', () {
      final tx = validBackupJson();
      rowsOf(tx, 'transactions')[0]['classification'] = 99;
      _rejectJson(tx, RestoreRejectReason.danglingRef, table: 'transactions', field: 'classification');
      final map = validBackupJson();
      rowsOf(map, 'counterparty_map')[0]['classification'] = 99;
      _rejectJson(map, RestoreRejectReason.danglingRef, table: 'counterparty_map', field: 'classification');
      // Referencing a row that is later in the array is fine (ids are handles).
      // Referencing an id that is only in ANOTHER table's range is not.
      final txRef = validBackupJson();
      rowsOf(txRef, 'transactions')[0]['classification'] = 1000;
      _rejectJson(txRef, RestoreRejectReason.danglingRef);
    });

    test('a classification in the wrong group is rejected (trigger rule pre-check)', () {
      final tx = validBackupJson();
      rowsOf(tx, 'transactions')[0]['classification'] = 2; // PAYBILL class on SEND_MONEY row
      _rejectJson(tx, RestoreRejectReason.invalidRow, table: 'transactions', field: 'classification');
      final map = validBackupJson();
      rowsOf(map, 'counterparty_map')[0]['classification'] = 3; // BUY_GOODS on SEND_MONEY key
      _rejectJson(map, RestoreRejectReason.invalidRow, table: 'counterparty_map', field: 'classification');
    });

    test('reject_cash_row_on_disabled_group', () {
      final j = validBackupJson();
      rowsOf(j, 'classifications').add({
        'id': 6, 'group': 'POCHI_LA_BIASHARA', 'name': 'Stock', 'active': 1,
        'seed_key': null, 'created_at': tBase,
      });
      rowsOf(j, 'transactions')[3]['classification'] = 6; // the CASH row
      fixCounts(j);
      _rejectJson(j, RestoreRejectReason.invalidRow, table: 'transactions', field: 'classification');
      // The same file is fine when this phone has that group enabled.
      expect(
        () => BackupValidator.validate(bytesOf(j),
            enabledGroupCodes: {...BackupValidator.defaultEnabledGroups, 'POCHI_LA_BIASHARA'}),
        returnsNormally,
      );
      // A non-CASH row on a Pochi class is a group mismatch either way.
      final k = validBackupJson();
      rowsOf(k, 'classifications').add({
        'id': 6, 'group': 'POCHI_LA_BIASHARA', 'name': 'Stock', 'active': 1,
        'seed_key': null, 'created_at': tBase,
      });
      rowsOf(k, 'transactions')[0]['classification'] = 6;
      fixCounts(k);
      _rejectJson(k, RestoreRejectReason.invalidRow);
      // A CASH row on any ENABLED group is fine (fixture: row 3 on SEND_MONEY).
      final cashOnPaybill = validBackupJson();
      rowsOf(cashOnPaybill, 'transactions')[3]['classification'] = 2;
      expect(() => BackupValidator.validate(bytesOf(cashOnPaybill)), returnsNormally);
    });

    test('reject_duplicate_codes_in_file', () {
      // two M-Pesa rows with the same code
      final a = validBackupJson();
      rowsOf(a, 'transactions')[1]['display_code'] = 'AB12CD34EF';
      _rejectJson(a, RestoreRejectReason.invalidRow, table: 'transactions', field: 'display_code');
      // two CASH rows with the same code AND created_at
      final b = validBackupJson();
      rowsOf(b, 'transactions')[4]['created_at'] = rowsOf(b, 'transactions')[3]['created_at'];
      _rejectJson(b, RestoreRejectReason.invalidRow, table: 'transactions', field: 'display_code');
      // duplicate transaction ids
      final c = validBackupJson();
      rowsOf(c, 'transactions')[1]['id'] = 1;
      _rejectJson(c, RestoreRejectReason.invalidRow, table: 'transactions', field: 'id');
      // duplicate classification ids
      final d = validBackupJson();
      rowsOf(d, 'classifications')[1]['id'] = 1;
      _rejectJson(d, RestoreRejectReason.invalidRow, table: 'classifications', field: 'id');
      // a seed key twice
      final e = validBackupJson();
      rowsOf(e, 'classifications')[3]['seed_key'] = 'SEND_MONEY:family_friends';
      _rejectJson(e, RestoreRejectReason.invalidRow, table: 'classifications', field: 'seed_key');
      // two ACTIVE classes with the same (group, name)
      final f = validBackupJson();
      rowsOf(f, 'classifications').add({
        'id': 6, 'group': 'SEND_MONEY', 'name': 'School fees', 'active': 1,
        'seed_key': null, 'created_at': tBase,
      });
      fixCounts(f);
      _rejectJson(f, RestoreRejectReason.invalidRow, table: 'classifications', field: 'name');
      // duplicate map key
      final g = validBackupJson();
      rowsOf(g, 'counterparty_map').add(Map<String, Object?>.of(rowsOf(g, 'counterparty_map')[0]));
      fixCounts(g);
      _rejectJson(g, RestoreRejectReason.invalidRow, table: 'counterparty_map', field: 'counterparty_key');
      // same name in different groups is fine
      final h = validBackupJson();
      rowsOf(h, 'classifications').add({
        'id': 6, 'group': 'BUY_GOODS', 'name': 'School fees', 'active': 1,
        'seed_key': null, 'created_at': tBase,
      });
      fixCounts(h);
      expect(() => BackupValidator.validate(bytesOf(h)), returnsNormally);
    });
  });

  group('prefs', () {
    test('unknown and forbidden keys are dropped, never applied, never an error', () {
      final j = validBackupJson()
        ..['prefs'] = {
          'palette_id': 'indigo',
          'auto_backup_folder_uri': 'content://evil',
          'update_check_enabled': false,
          'whatsnew_seen_version': '99.0.0',
          'onboarding_complete': true,
          'auto_backup_enabled': true,
          'anything': {'nested': [1]},
        };
      final v = BackupValidator.validate(bytesOf(j));
      expect(v.prefs, {'palette_id': 'indigo'});
    });

    test('a present allowlisted key with a bad type or range rejects the file', () {
      for (final p in <Map<String, Object?>>[
        {'palette_id': 'red'},
        {'palette_id': 1},
        {'auto_recognize_classifications': 'true'},
        {'capture_identity_preference': 1},
        {'auto_backup_every_n': 10.0},
        {'auto_backup_every_n': 0},
        {'auto_backup_every_n': 101},
        {'auto_backup_keep_k': 1},
        {'auto_backup_keep_k': 21},
        {'user_display_name': 'x' * 31},
        {'user_display_name': ''},
        {'user_display_name': 'a\nb'},
        {'user_display_name': 'bidi\u202Eevil'},
      ]) {
        _rejectJson(validBackupJson()..['prefs'] = p, RestoreRejectReason.invalidRow,
            table: 'prefs', field: p.keys.first);
      }
    });

    test('prefs must be an object', () {
      for (final bad in <Object?>[null, [], 'x', 5]) {
        _rejectJson(validBackupJson()..['prefs'] = bad, RestoreRejectReason.corrupt, field: 'prefs');
      }
    });

    test('all six allowlisted settings pass through', () {
      final p = {
        'user_display_name': 'Amina',
        'palette_id': 'leaf',
        'auto_recognize_classifications': false,
        'capture_identity_preference': true,
        'auto_backup_every_n': 20,
        'auto_backup_keep_k': 7,
      };
      expect(BackupValidator.validate(bytesOf(validBackupJson()..['prefs'] = p)).prefs, p);
    });
  });

  group('hostile content', () {
    test('no_code_path_opens_or_evaluates_file_content', () {
      // A file full of things that look like instructions.
      final hostile = <String>[
        'file:///etc/passwd',
        'https://evil.example/pwn?id=1',
        'content://com.android.externalstorage.documents/tree/primary%3A',
        r'C:\Windows\System32\cmd.exe /c calc',
        '../../../../data/data/app.mmogo/databases/mmogo.db',
        '/proc/self/environ',
        r'$(rm -rf /)',
        '`reboot`',
        "'); DROP TABLE transactions;--",
        'javascript:alert(1)',
        'intent://scan/#Intent;scheme=zxing;end',
        r'{{7*7}} ${1 + 1}',
      ];
      final j = validBackupJson();
      final classes = rowsOf(j, 'classifications');
      // Spread the hostile strings across every text field.
      final tx = rowsOf(j, 'transactions');
      tx[0]['counterparty_label'] = hostile[1];
      tx[1]['counterparty_label'] = hostile[2];
      tx[1]['paybill_account_number'] = hostile[3];
      rowsOf(j, 'counterparty_map')[1]['counterparty_key'] = '${hostile[4]}#${hostile[5]}';
      classes[3]['name'] = hostile[0];
      classes[4]['name'] = hostile[6];
      j['prefs'] = {'user_display_name': hostile[7], 'palette_id': 'leaf'};
      // Ids that look like pointers: huge file-local ids are only handles.
      rowsOf(j, 'transactions')[2]['id'] = 9007199254740991;

      // Recording fakes: any file or network access during validation is a
      // failure.
      final touched = <String>[];
      late ValidatedBackup v;
      IOOverrides.runZoned(
        () {
          HttpOverrides.runZoned(
            () => v = BackupValidator.validate(bytesOf(j)),
            createHttpClient: (c) {
              touched.add('HttpClient');
              throw StateError('network');
            },
          );
        },
        createFile: (p) {
          touched.add('File($p)');
          throw StateError('file');
        },
        createDirectory: (p) {
          touched.add('Directory($p)');
          throw StateError('dir');
        },
        createLink: (p) {
          touched.add('Link($p)');
          throw StateError('link');
        },
        socketConnect: (host, port, {sourceAddress, sourcePort = 0, timeout}) {
          touched.add('socket');
          throw StateError('socket');
        },
      );
      expect(touched, isEmpty);
      // The text is carried through verbatim as plain data.
      expect(v.classifications[3]['name'], hostile[0]);
      expect(v.transactions[0]['counterparty_label'], hostile[1]);
      expect(v.prefs['user_display_name'], hostile[7]);
    });

    test('static scan: the validator has no way to open, fetch or evaluate anything', () {
      final src = File('lib/data/backup/backup_validator.dart').readAsStringSync();
      final code = _stripComments(src);
      for (final banned in [
        'dart:io',
        'dart:mirrors',
        'dart:ffi',
        'File(',
        'Directory(',
        'Uri',
        'HttpClient',
        'Process',
        'Socket',
        'eval',
        'launch',
        'sqflite',
        'Database',
        'rawQuery',
        'execute(',
        'SharedPreferences',
        'package:flutter',
      ]) {
        expect(code.contains(banned), isFalse, reason: 'backup_validator.dart mentions $banned');
      }
      final imports = RegExp(r"^import '([^']+)';", multiLine: true)
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(imports, [
        'dart:convert',
        'dart:typed_data',
        'backup_limits.dart',
        'backup_setting_keys.dart',
      ]);
      // The two helper files it pulls in are import-free of IO too.
      for (final f in ['backup_limits.dart', 'backup_setting_keys.dart']) {
        final s = _stripComments(File('lib/data/backup/$f').readAsStringSync());
        expect(s.contains('dart:io'), isFalse);
        expect(s.contains('Uri'), isFalse);
        expect(s.contains('Process'), isFalse);
      }
    });

    test('table and column name lists are const', () {
      final src = File('lib/data/backup/backup_limits.dart').readAsStringSync();
      for (final name in [
        'kBackupTopLevelKeys',
        'kBackupCountsKeys',
        'kBackupClassificationKeys',
        'kBackupTransactionKeys',
        'kBackupMapKeys',
        'kBackupGroupCodes',
        'kBackupSourceTypes',
        'kBackupMapSourceTypes',
        'kBackupRawParseSources',
        'kBackupSeedKeys',
      ]) {
        expect(RegExp('^const List<String> $name = \\[', multiLine: true).hasMatch(src), isTrue,
            reason: '$name must be a const List<String>');
      }
      // The validator never builds a table or column name from the file.
      final v = _stripComments(File('lib/data/backup/backup_validator.dart').readAsStringSync());
      expect(RegExp(r'SELECT|INSERT|UPDATE|DELETE\s+FROM|CREATE\s+TABLE').hasMatch(v), isFalse);
    });

    test('SQL-looking text is accepted as inert text', () {
      final j = validBackupJson();
      rowsOf(j, 'classifications')[3]['name'] = "'); DROP TABLE transactions;--";
      rowsOf(j, 'transactions')[0]['counterparty_label'] = '" OR 1=1';
      final v = BackupValidator.validate(bytesOf(j));
      expect(v.classifications[3]['name'], "'); DROP TABLE transactions;--");
    });

    test('a hostile file of control and bidi characters is refused field by field', () {
      for (final bad in [
        '\u0000', '\u0007', '\u001B[31m', '\u0080', '\u009F', '\u061C', '\u200E', '\u200F',
        '\u202A', '\u202B', '\u202C', '\u202D', '\u202E', '\u2066', '\u2067', '\u2068', '\u2069',
      ]) {
        final j = validBackupJson();
        rowsOf(j, 'transactions')[0]['counterparty_label'] = 'a${bad}b';
        _rejectJson(j, RestoreRejectReason.invalidRow, table: 'transactions', field: 'counterparty_label');
      }
    });
  });

  group('isolate', () {
    test('runs in Isolate.run: a valid file returns plain data', () async {
      final bytes = bytesOf(validBackupJson());
      final v = await Isolate.run(() => BackupValidator.validate(bytes));
      expect(v.transactions.length, 5);
      expect(v.prefs['palette_id'], 'leaf');
    });

    test('runs in Isolate.run: a rejection crosses back with its reason', () async {
      final bytes = bytesOf(validBackupJson()..['schema_version'] = 3);
      await expectLater(
        Isolate.run(() => BackupValidator.validate(bytes)),
        throwsA(isA<RestoreRejected>()
            .having((e) => e.reason, 'reason', RestoreRejectReason.newer)),
      );
      final deep = Uint8List.fromList(List.filled(1000000, 0x5B));
      await expectLater(
        Isolate.run(() => BackupValidator.validate(deep)),
        throwsA(isA<RestoreRejected>()),
      );
    });
  });

  group('round trip (export then validate)', () {
    test('a file the codec writes always validates, and equals its source', () {
      final j = validBackupJson();
      final bytes = BackupCodec.encode(
        createdAtMs: tBase,
        classifications: rowsOf(j, 'classifications'),
        transactions: rowsOf(j, 'transactions'),
        counterpartyMap: rowsOf(j, 'counterparty_map'),
        prefs: {'palette_id': 'ocean', 'auto_backup_keep_k': 5},
      );
      final v = BackupValidator.validate(bytes);
      expect(v.classifications, rowsOf(j, 'classifications'));
      expect(v.transactions, rowsOf(j, 'transactions'));
      expect(v.counterpartyMap, rowsOf(j, 'counterparty_map'));
      expect(v.prefs, {'palette_id': 'ocean', 'auto_backup_keep_k': 5});
      // and encoding the validated rows again gives the same bytes
      final again = BackupCodec.encode(
        createdAtMs: v.createdAt,
        classifications: v.classifications,
        transactions: v.transactions,
        counterpartyMap: v.counterpartyMap,
        prefs: v.prefs,
      );
      expect(again, bytes);
    });
  });
}

/// Source with `//` comments removed (line-based; no string in the validator
/// contains `//`).
String _stripComments(String src) => src
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i < 0 ? l : l.substring(0, i);
    })
    .join('\n');
