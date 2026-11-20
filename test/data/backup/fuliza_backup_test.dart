// 0.2.0 S12 slice B: `fuliza_events` in backup and restore (schema 4), Judge
// C2 and C3. Invented data only. Real in-memory database with the real schema.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_codec.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

RestoreService _svc(Database db, {FakeSafetyCopyStore? safety}) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: safety ?? FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
    );

Future<void> _addEvent(DatabaseExecutor db, String kind, String code,
        {int at = f0, int amount = 50000, int fee = 0, int? printed}) =>
    db.insert('fuliza_events', {
      'kind': kind,
      'code': code,
      'occurred_at': at,
      'amount_cents': amount,
      'fee_cents': fee,
      'printed_total_cents': printed,
    });

Future<List<String>> _events(DatabaseExecutor db) async => [
      for (final r in await db.rawQuery(
          'SELECT kind, code, occurred_at, amount_cents, fee_cents, printed_total_cents '
          'FROM fuliza_events ORDER BY id'))
        r.values.join('|'),
    ];

Map<String, Object?> _v4({
  List<Map<String, Object?>> fuliza = const [],
  Map<String, Object?> prefs = const {},
}) =>
    fileJson(classes: seedRowsV3(), fuliza: fuliza, prefs: prefs, schemaVersion: 4);

Map<String, Object?> _v3({Map<String, Object?> prefs = const {}}) =>
    fileJson(classes: seedRowsV3(), prefs: prefs, schemaVersion: 3);

void _refused(Map<String, Object?> json, RestoreRejectReason reason, {String? field, String? table}) {
  try {
    BackupValidator.validate(fileBytes(json));
  } on RestoreRejected catch (e) {
    expect(e.reason, reason);
    if (field != null) expect(e.field, field);
    if (table != null) expect(e.table, table);
    return;
  }
  fail('expected a refusal ($reason)');
}

List<String> _writes(List<Stmt> log, int mark) =>
    [for (final s in log.sublist(mark)) if (s.isWrite) s.sql];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('constants', () {
    test('kind strings equal the FulizaEventKind enum names; key lists are pinned', () {
      expect(kBackupFulizaKinds, [for (final k in FulizaEventKind.values) k.name]);
      expect(kBackupFulizaKeys,
          ['kind', 'code', 'occurred_at', 'amount_cents', 'fee_cents', 'printed_total_cents']);
      expect(kBackupTopLevelKeys.where((k) => !kBackupTopLevelKeysV3.contains(k)), ['fuliza_events']);
      expect(kBackupCountsKeys.where((k) => !kBackupCountsKeysV3.contains(k)), ['fuliza_events']);
      expect(kBackupSchemaVersion, 8);
    });
  });

  group('export', () {
    test('writes the section, the count, schema_version 5 and the limit; the file validates', () async {
      SharedPreferences.setMockInitialValues({'fuliza_limit_cents': 5000000});
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111', at: f0 + 1, amount: 100000, fee: 3000, printed: 103000);
      await _addEvent(db, 'repayPartial', 'BBB2222222', at: f0 + 2, amount: 40000);
      final bytes = await backupOf(db).exportToBytes();
      final obj = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(obj['schema_version'], 8);
      expect((obj['counts']! as Map)['fuliza_events'], 2);
      expect((obj['fuliza_events']! as List), hasLength(2));
      expect((obj['fuliza_events']! as List).first, {
        'kind': 'draw',
        'code': 'AAA1111111',
        'occurred_at': f0 + 1,
        'amount_cents': 100000,
        'fee_cents': 3000,
        'printed_total_cents': 103000,
      });
      expect((obj['prefs']! as Map)['fuliza_limit_cents'], 5000000);
      final v = BackupValidator.validate(bytes);
      expect(v.fulizaEvents, hasLength(2));
      expect(v.hasFulizaSection, isTrue);
      await db.close();
    });

    test('an empty ledger exports an empty section with count 0', () async {
      final db = await openTestDb();
      final obj = jsonDecode(utf8.decode(await backupOf(db).exportToBytes())) as Map<String, Object?>;
      expect(obj['fuliza_events'], isEmpty);
      expect((obj['counts']! as Map)['fuliza_events'], 0);
      await db.close();
    });

    test('the codec copies only the six Fuliza keys', () {
      final bytes = BackupCodec.encode(
        createdAtMs: f0,
        classifications: const [],
        transactions: const [],
        counterpartyMap: const [],
        fulizaEvents: [
          {...fulizaRow('draw', 'AAA1111111'), 'id': 7, 'extra': 'x'},
        ],
      );
      final row = ((jsonDecode(utf8.decode(bytes)) as Map)['fuliza_events'] as List).single as Map;
      expect(row.keys.toList(), kBackupFulizaKeys);
    });

    test('a stored event the validator would refuse is left out and reported, never the whole export', () async {
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111');
      await _addEvent(db, 'draw', 'BAD\u0007CODE1'); // the table only checks "not empty"
      final export = await backupOf(db).export();
      expect(export.fulizaEvents, 1);
      expect(export.fulizaLive, 2);
      expect(export.skippedCount, 1);
      expect(export.skippedRows.single.kind, SkipKind.fulizaRecord);
      expect(BackupValidator.validate(export.bytes).fulizaEvents, hasLength(1));
      await db.close();
    });

    test('BackupCounts counts the events', () async {
      final db = await openTestDb();
      expect((await BackupCounts.read(db)).isEmpty, isTrue);
      await _addEvent(db, 'draw', 'AAA1111111');
      final c = await BackupCounts.read(db);
      expect(c.fulizaEvents, 1);
      expect(c.isEmpty, isFalse);
      await db.close();
    });
  });

  group('validator', () {
    test('a valid v4 file passes; an older v3 file stays readable with no events', () {
      final v4 = BackupValidator.validate(
          fileBytes(_v4(fuliza: [fulizaRow('draw', 'AAA1111111', printed: 0)])));
      expect(v4.fulizaEvents, hasLength(1));
      final v3 = BackupValidator.validate(fileBytes(_v3()));
      expect(v3.fulizaEvents, isEmpty);
      expect(v3.hasFulizaSection, isFalse);
    });

    test('a v4 file without the section is refused (keys and counts)', () {
      _refused(_v4()..remove('fuliza_events'), RestoreRejectReason.corrupt, field: '(keys)');
      final noCount = _v4();
      (noCount['counts']! as Map).remove('fuliza_events');
      _refused(noCount, RestoreRejectReason.corrupt, field: 'counts');
    });

    test('a v3 file carrying the section or the count is refused', () {
      _refused(_v3()..['fuliza_events'] = <Object?>[], RestoreRejectReason.corrupt, field: '(keys)');
      final counted = _v3();
      (counted['counts']! as Map)['fuliza_events'] = 0;
      _refused(counted, RestoreRejectReason.corrupt, field: 'counts');
    });

    test('a v4 count that differs from the array is refused', () {
      final j = _v4(fuliza: [fulizaRow('draw', 'AAA1111111')]);
      (j['counts']! as Map)['fuliza_events'] = 2;
      _refused(j, RestoreRejectReason.corrupt, field: 'counts');
      _refused(_v4()..['fuliza_events'] = 'x', RestoreRejectReason.corrupt, field: 'fuliza_events');
    });

    test('a schema above the maximum is "newer", before any key check', () {
      final j = _v4()
        ..['schema_version'] = 9
        ..['brand_new'] = 1;
      _refused(j, RestoreRejectReason.newer, field: 'schema_version');
    });

    test('row rules: kind, amount > 0, fee >= 0, printed null or >= 0, code, time, extra keys', () {
      void bad(Map<String, Object?> row, String field) => _refused(_v4(fuliza: [row]),
          RestoreRejectReason.invalidRow, table: 'fuliza_events', field: field);
      bad(fulizaRow('Draw', 'AAA1111111'), 'kind');
      bad(fulizaRow('repay_full', 'AAA1111111'), 'kind');
      bad({...fulizaRow('draw', 'AAA1111111'), 'kind': null}, 'kind');
      bad(fulizaRow('draw', 'AAA1111111', amount: 0), 'amount_cents');
      bad(fulizaRow('draw', 'AAA1111111', amount: -5), 'amount_cents');
      bad(fulizaRow('draw', 'AAA1111111', amount: kBackupMaxFulizaCents + 1), 'amount_cents');
      bad({...fulizaRow('draw', 'AAA1111111'), 'amount_cents': 1.5}, 'amount_cents');
      bad(fulizaRow('draw', 'AAA1111111', fee: -1), 'fee_cents');
      bad(fulizaRow('draw', 'AAA1111111', printed: -1), 'printed_total_cents');
      bad(fulizaRow('draw', ''), 'code');
      bad(fulizaRow('draw', ' AAA1111111'), 'code');
      bad(fulizaRow('draw', 'A' * (kBackupMaxFulizaCodeLength + 1)), 'code');
      bad(fulizaRow('draw', 'AAA${String.fromCharCode(0x202E)}111111'), 'code');
      bad({...fulizaRow('draw', 'AAA1111111'), 'code': 7}, 'code');
      bad(fulizaRow('draw', 'AAA1111111', at: kBackupMinEpochMs - 1), 'occurred_at');
      bad(fulizaRow('draw', 'AAA1111111', at: kBackupMaxEpochMs), 'occurred_at');
      bad({...fulizaRow('draw', 'AAA1111111'), 'message': 'x'}, '(keys)');
      // A zero fee and a zero printed total are fine (a full repayment leaves 0).
      BackupValidator.validate(
          fileBytes(_v4(fuliza: [fulizaRow('draw', 'AAA1111111', fee: 0, printed: 0)])));
    });

    test('a repeated (kind, code) in one file is refused; the same code with another kind is fine', () {
      _refused(_v4(fuliza: [fulizaRow('draw', 'AAA1111111'), fulizaRow('draw', 'AAA1111111')]),
          RestoreRejectReason.invalidRow, table: 'fuliza_events', field: 'code');
      BackupValidator.validate(fileBytes(
          _v4(fuliza: [fulizaRow('draw', 'AAA1111111'), fulizaRow('repayFull', 'AAA1111111')])));
    });

    test('row cap: one over the cap is tooMany', () {
      final rows = [
        for (var i = 0; i <= kBackupMaxFulizaEvents; i++)
          fulizaRow('draw', 'C${i.toString().padLeft(9, '0')}'),
      ];
      _refused(_v4(fuliza: rows), RestoreRejectReason.tooMany, table: 'fuliza_events');
    });

    test('the limit key: allowed with a range in a v4 file, rejected out of range, dropped from a v3 file', () {
      final ok = BackupValidator.validate(fileBytes(_v4(prefs: {'fuliza_limit_cents': 7000000})));
      expect(ok.prefs['fuliza_limit_cents'], 7000000);
      BackupValidator.validate(fileBytes(_v4(prefs: {'fuliza_limit_cents': 0})));
      for (final v in <Object?>[-1, 100000000001, 1.5, '5', true]) {
        _refused(_v4(prefs: {'fuliza_limit_cents': v}), RestoreRejectReason.invalidRow,
            table: 'prefs', field: 'fuliza_limit_cents');
      }
      final old = BackupValidator.validate(
          fileBytes(_v3(prefs: {'fuliza_limit_cents': 7000000, 'palette_id': 'leaf'})));
      expect(old.prefs.containsKey('fuliza_limit_cents'), isFalse);
      expect(old.prefs['palette_id'], 'leaf');
    });

    test('the describer has one line for a Fuliza record, with no value in it', () {
      final out = describeSkipped(
        [const BackupSkippedRow(table: 'fuliza_events', rowId: 4, field: 'code', rule: 'invalidRow')],
        entryFacts: const {},
      );
      expect(out.single.kind, SkipKind.fulizaRecord);
      expect(out.single.reason, SkipReason.notAllowed);
      expect(out.single.toString(), 'SkippedRowInfo(fulizaRecord, notAllowed)');
    });
  });

  group('restore', () {
    test('round trip v4 to v4: events and the limit come back exactly', () async {
      SharedPreferences.setMockInitialValues({'fuliza_limit_cents': 5000000});
      final a = await openTestDb();
      await _addEvent(a, 'draw', 'AAA1111111', at: f0 + 1, amount: 100000, fee: 3000, printed: 103000);
      await _addEvent(a, 'repayFull', 'BBB2222222', at: f0 + 2, amount: 103000);
      await _addEvent(a, 'repayPartial', 'CCC3333333', at: f0 + 3, amount: 10000);
      final expected = await _events(a);
      final bytes = await backupOf(a).exportToBytes();
      await a.close();

      SharedPreferences.setMockInitialValues({});
      final b = await openTestDb();
      final r = await _svc(b).restore(bytes, RestoreMode.replace);
      expect(r.fulizaEvents, const TableCounts(added: 3, skipped: 0));
      expect(r.fulizaLeftAlone, isFalse);
      expect(await _events(b), expected);
      expect((await SharedPreferences.getInstance()).getInt('fuliza_limit_cents'), 5000000);
      await b.close();
    });

    test('a v3 file restores (merge) with an empty ledger', () async {
      final db = await openTestDb();
      final r = await _svc(db).restore(fileBytes(_v3()), RestoreMode.merge);
      expect(r.fulizaEvents, const TableCounts());
      expect(await _events(db), isEmpty);
      await db.close();
    });

    test('C3: Replace from a v3 file does NOT erase events or the limit, and says so', () async {
      SharedPreferences.setMockInitialValues({'fuliza_limit_cents': 5000000});
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111', at: f0 + 1, amount: 100000, fee: 3000, printed: 103000);
      await _addEvent(db, 'repayFull', 'BBB2222222', at: f0 + 2, amount: 103000);
      final before = await _events(db);
      final json = _v3(prefs: {'fuliza_limit_cents': 999, 'palette_id': 'leaf'});
      final r = await _svc(db).restore(fileBytes(json), RestoreMode.replace);
      expect(r.fulizaLeftAlone, isTrue);
      expect(await _events(db), before);
      expect(r.fulizaEvents, const TableCounts());
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('fuliza_limit_cents'), 5000000, reason: 'a v3 file cannot change the limit');
      expect(prefs.getString('palette_id'), 'leaf');
      await db.close();
    });

    test('Replace from a v4 file replaces the events (a v4 file with none empties the ledger)', () async {
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'OLD1111111');
      await _svc(db).restore(
          fileBytes(_v4(fuliza: [fulizaRow('draw', 'NEW1111111', at: f0 + 9)])), RestoreMode.replace);
      expect(await _events(db), ['draw|NEW1111111|${f0 + 9}|50000|0|null']);
      final r = await _svc(db).restore(fileBytes(_v4()), RestoreMode.replace);
      expect(r.fulizaLeftAlone, isFalse);
      expect(await _events(db), isEmpty);
      await db.close();
    });

    test('merge adds new events, skips a duplicate (kind, code) and keeps the stored row', () async {
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111', at: f0 + 1, amount: 111);
      final r = await _svc(db).restore(
        fileBytes(_v4(fuliza: [
          fulizaRow('draw', 'AAA1111111', at: f0 + 50, amount: 999),
          fulizaRow('repayFull', 'AAA1111111', at: f0 + 51),
        ])),
        RestoreMode.merge,
      );
      expect(r.fulizaEvents, const TableCounts(added: 1, skipped: 1));
      expect(await _events(db), [
        'draw|AAA1111111|${f0 + 1}|111|0|null',
        'repayFull|AAA1111111|${f0 + 51}|50000|0|null',
      ]);
      // A second merge of the same row adds nothing.
      final again = await _svc(db).restore(
          fileBytes(_v4(fuliza: [fulizaRow('repayFull', 'AAA1111111')])), RestoreMode.merge);
      expect(again.fulizaEvents, const TableCounts(added: 0, skipped: 1));
      await db.close();
    });

    test('inspect (the merge preview) counts the events and writes nothing', () async {
      final log = <Stmt>[];
      final db = await openTestDb(log: log);
      await _addEvent(db, 'draw', 'AAA1111111');
      final mark = log.length;
      final p = await _svc(db).inspect(fileBytes(_v4(fuliza: [
        fulizaRow('draw', 'AAA1111111'),
        fulizaRow('draw', 'BBB2222222'),
      ])));
      expect(p.fileFulizaEvents, 2);
      expect(p.newFulizaEvents, 1);
      expect(p.phoneFulizaEvents, 1);
      expect(_writes(log, mark), isEmpty);
      await db.close();
    });

    test('bad shapes and a newer schema are refused before any write (state unchanged)', () async {
      final log = <Stmt>[];
      final db = await openTestDb(log: log);
      await _addEvent(db, 'draw', 'AAA1111111');
      final before = await _events(db);
      final mark = log.length;
      for (final json in [
        _v4()..remove('fuliza_events'),
        _v3()..['fuliza_events'] = <Object?>[],
        _v4()..['schema_version'] = 9,
        _v4(fuliza: [fulizaRow('draw', 'AAA1111111', amount: 0)]),
      ]) {
        for (final mode in RestoreMode.values) {
          await expectLater(
              _svc(db).restore(fileBytes(json), mode), throwsA(isA<RestoreRejected>()));
        }
      }
      expect(_writes(log, mark), isEmpty);
      expect(await _events(db), before);
      await db.close();
    });

    test('the Replace count check includes the table: a changed ledger rolls it back', () async {
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111');
      final file = BackupValidator.validate(fileBytes(_v4()));
      await expectLater(
        db.transaction((txn) => const RestoreWriter().replace(txn, file,
            expect: const ExpectedRows(
                transactions: 0, classifications: 17, counterpartyMap: 0, fulizaEvents: 0))),
        throwsA(isA<RestoreDataChanged>()),
      );
      expect(await _events(db), hasLength(1));
      await db.close();
    });

    test('Undo: the safety copy carries the events and undo brings them back', () async {
      SharedPreferences.setMockInitialValues({'fuliza_limit_cents': 5000000});
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111', at: f0 + 1, amount: 100000, fee: 3000, printed: 103000);
      await _addEvent(db, 'repayPartial', 'BBB2222222', at: f0 + 2, amount: 20000);
      final before = await _events(db);
      final safety = FakeSafetyCopyStore([]);
      final svc = _svc(db, safety: safety);

      // Replace from a v4 file with other events: the old ones are gone.
      await svc.restore(fileBytes(_v4(fuliza: [fulizaRow('draw', 'ZZZ9999999', at: f0 + 7)])),
          RestoreMode.replace);
      expect(await _events(db), ['draw|ZZZ9999999|${f0 + 7}|50000|0|null']);
      // The private copy is a v4 file holding the old events.
      final copy = BackupValidator.validate(safety.bytes!);
      expect(copy.fulizaEvents, hasLength(2));

      await svc.undoLastReplace();
      expect(await _events(db), before);
      await db.close();
    });

    test('Undo after a Replace from a v3 file keeps the events too', () async {
      final db = await openTestDb();
      await _addEvent(db, 'draw', 'AAA1111111');
      final before = await _events(db);
      final svc = _svc(db, safety: FakeSafetyCopyStore([]));
      await svc.restore(fileBytes(_v3()), RestoreMode.replace);
      await svc.undoLastReplace();
      expect(await _events(db), before);
      await db.close();
    });

    test('the real SafetyCopyStore refuses a copy whose Fuliza count is not the expected one', () async {
      final dir = await Directory.systemTemp.createTemp('mmogo_safety_b_');
      try {
        final store = SafetyCopyStore(baseDir: () async => dir);
        final bytes = Uint8List.fromList(
            utf8.encode(jsonEncode(_v4(fuliza: [fulizaRow('draw', 'AAA1111111')]))));
        // The file fixture holds the 17 built-ins and nothing else.
        await expectLater(
          store.write(bytes,
              expect: const ExpectedRows(
                  transactions: 0, classifications: 17, counterpartyMap: 0, fulizaEvents: 2)),
          throwsA(isA<SafetyCopyError>()),
        );
        expect(await store.exists(), isFalse);
        await store.write(bytes,
            expect: const ExpectedRows(
                transactions: 0, classifications: 17, counterpartyMap: 0, fulizaEvents: 1));
        expect(await store.exists(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });
}
