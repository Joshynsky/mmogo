// 0.2.0 S12 slice C (Judge C4): Delete data and Fuliza. Invented data; real SQLite file in a temp dir.
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/sqlite_fuliza_repository.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/data_op_env.dart';

Future<void> _plantFuliza(Database db, {int n = 2}) async {
  for (var i = 0; i < n; i++) {
    await db.insert('fuliza_events', {
      'kind': 'draw',
      'code': 'QDMFX0000$i',
      'occurred_at': 1760000000000 + i,
      'amount_cents': 50000,
      'fee_cents': 500,
      'printed_total_cents': 50500,
    });
  }
  await (await SharedPreferences.getInstance()).setInt(SqliteFulizaRepository.limitPrefsKey, 5000000);
}

void main() {
  late DataOpEnv env;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
  });
  tearDown(() => env.dispose());

  test('peek counts Fuliza records and nothingLeftAtLevel2 is false while they remain', () async {
    final db = await env.open();
    await _plantFuliza(db, n: 3);
    final peek = await env.service().peek();
    expect(peek.fulizaRecords, 3);
    expect(peek.nothingLeftAtLevel2, isFalse);
    expect(peek.nothingLeftToDeleteAtLevel1, isFalse);
  });

  test('a database with only Fuliza records is not "nothing to delete"', () async {
    final db = await env.open();
    await db.delete('counterparty_classification_map');
    await db.delete('transactions');
    await _plantFuliza(db, n: 1);
    final peek = await env.service().peek();
    expect(peek.liveTransactions + peek.softDeletedTransactions + peek.learnedReceivers, 0);
    expect(peek.fulizaRecords, 1);
    expect(peek.nothingLeftToDeleteAtLevel1, isFalse);
  });

  test('level 1 clears fuliza_events and the limit and reports the count', () async {
    final db = await env.open();
    await _plantFuliza(db, n: 2);
    final r = await env.service().deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.done);
    expect(r.fulizaRecordsDeleted, 2);
    expect(await env.count('SELECT COUNT(*) FROM fuliza_events'), 0);
    expect(await env.prefsMap(), isNot(contains(SqliteFulizaRepository.limitPrefsKey)));
  });

  test('level 1: the left-behind check includes Fuliza; a row "left" rolls the whole delete back', () async {
    final db = await env.open();
    await _plantFuliza(db, n: 2);
    final txBefore = await env.count('SELECT COUNT(*) FROM transactions');
    final r = await env
        .service(countRows: (d, table) async => table == 'fuliza_events' ? 1 : 0)
        .deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.nothingWasDeleted);
    expect(await env.count('SELECT COUNT(*) FROM fuliza_events'), 2);
    expect(await env.count('SELECT COUNT(*) FROM transactions'), txBefore);
    expect(await env.prefsMap(), contains(SqliteFulizaRepository.limitPrefsKey));
  });

  test('level 2: after a reset no fuliza_events table and no limit key remain', () async {
    final db = await env.open();
    await _plantFuliza(db, n: 2);
    final r = await env.service().resetApp();
    expect(r.outcome, DeleteDataOutcome.done);
    expect(r.fulizaRecordsDeleted, 2);
    expect(await File(env.dbPath).exists(), isFalse, reason: 'the file is removed, not rows');
    expect(await env.prefsMap(), isEmpty);
    expect(await env.prefsMap(), isNot(contains(SqliteFulizaRepository.limitPrefsKey)));
  });

  test('the confirmation counts name Fuliza records', () {
    expect(
      deleteCountsText(live: 2, recentlyDeleted: 0, learnedReceivers: 0, rememberedRecipients: 0, fulizaRecords: 3),
      '2 transactions, 3 Fuliza records',
    );
    expect(
      deleteCountsText(live: 0, recentlyDeleted: 0, learnedReceivers: 0, rememberedRecipients: 0, fulizaRecords: 1),
      '1 Fuliza record',
    );
  });
}
