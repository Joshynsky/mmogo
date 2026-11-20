// Auto-record S2b: the live-database history reader (read-only FFI route) on a real temp sqlite file.
@Tags(['autoread'])
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/ffi_history_reader.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A factory whose open never finishes (the app holds the database busy).
class _HangingFactory implements DatabaseFactory {
  int opens = 0;
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    opens++;
    return Completer<Database>().future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FailingFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) => throw StateError('no plugin');
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;
  var t = 0;

  Future<void> ins(Database db, String type, int cat,
      {String? label, String? phone, String? account, int? deleted}) async {
    t++;
    await db.insert('transactions', {
      'source_type': type,
      'counterparty_label': label,
      'counterparty_phone': phone,
      'paybill_account_number': account,
      'classification_id': cat,
      'transaction_occurred_at': t,
      'deleted_at': deleted,
    });
  }

  setUp(() async {
    t = 0;
    dir = await Directory.systemTemp.createTemp('hist_ffi_');
    path = '${dir.path}${Platform.pathSeparator}mmogo.db';
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, source_type TEXT NOT NULL, '
        'counterparty_label TEXT, counterparty_phone TEXT, paybill_account_number TEXT, '
        'classification_id INTEGER NOT NULL, transaction_occurred_at INTEGER NOT NULL, deleted_at INTEGER)');
    // Oldest first (occurred_at rises with each insert).
    await ins(db, 'SEND_MONEY', 1, label: 'JANE', phone: '0712345678'); // 6th newest: ignored
    await ins(db, 'SEND_MONEY', 2, label: 'JANE', phone: '+254712345678');
    await ins(db, 'SEND_MONEY', 2, label: 'JANE', phone: '254712345678');
    await ins(db, 'SEND_MONEY', 3, label: 'JANE', phone: '0712345678');
    await ins(db, 'SEND_MONEY', 9, label: 'JANE', phone: '0712345678', deleted: 5); // undone: ignored
    await ins(db, 'SEND_MONEY', 3, label: 'JANE', phone: '0712 345 678');
    await ins(db, 'SEND_MONEY', 2, label: 'JANE', phone: '0712345678');
    await ins(db, 'SEND_MONEY', 7, label: 'OTHER', phone: '0799999999');
    await ins(db, 'PAYBILL', 5, label: 'kplc prepaid', account: '123');
    await ins(db, 'PAYBILL', 6, label: 'KPLC PREPAID', account: '999');
    await ins(db, 'BUY_GOODS', 8, label: 'Mama  Mboga');
    await ins(db, 'CASH', 1);
    await db.close();
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  FfiHistoryReader reader({DatabaseFactory? factory, Duration? cap}) =>
      FfiHistoryReader(dbPath: () async => path, factory: factory ?? databaseFactoryFfi, cap: cap ?? kFfiHistoryCap);

  test('Send Money: one person across phone formats; last 5 live records; most used first', () async {
    // newest first among JANE live rows: 2, 3, 3, 2, 2, (1 is the 6th) -> counts 2:3, 3:2
    expect(await reader().topTwo(ReceiverType.sendMoney, '0712345678'), [2, 3]);
  });

  test('Paybill keys by business and account; Buy Goods by shop; unknown person is empty', () async {
    expect(await reader().topTwo(ReceiverType.payBill, 'KPLC PREPAID#123'), [5]);
    expect(await reader().topTwo(ReceiverType.payBill, 'KPLC PREPAID#999'), [6]);
    expect(await reader().topTwo(ReceiverType.buyGoods, 'MAMA MBOGA'), [8]);
    expect(await reader().topTwo(ReceiverType.sendMoney, '0700000000'), isEmpty);
  });

  test('the database file is not changed by a read (bytes identical)', () async {
    final before = await File(path).readAsBytes();
    await reader().topTwo(ReceiverType.sendMoney, '0712345678');
    expect(await File(path).readAsBytes(), before);
  });

  test('missing file, failing factory and bad key all answer null (never throw)', () async {
    expect(await FfiHistoryReader(dbPath: () async => '${dir.path}/none.db', factory: databaseFactoryFfi)
        .topTwo(ReceiverType.sendMoney, '1'), isNull);
    expect(await FfiHistoryReader(dbPath: () async => null).topTwo(ReceiverType.sendMoney, '1'), isNull);
    expect(await reader(factory: _FailingFactory()).topTwo(ReceiverType.sendMoney, '0712345678'), isNull);
    expect(await reader().topTwo(ReceiverType.sendMoney, ''), isNull);
  });

  test('a hung open answers null at the 1.5 s cap (not later than about 2 s)', () async {
    final f = _HangingFactory();
    final sw = Stopwatch()..start();
    final r = await reader(factory: f).topTwo(ReceiverType.sendMoney, '0712345678');
    sw.stop();
    expect(r, isNull);
    expect(f.opens, 1);
    expect(sw.elapsedMilliseconds, inInclusiveRange(1400, 2200));
  });

  test('summary rows from the same file agree with the reader (one shared key rule)', () async {
    final db = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(readOnly: true));
    final rows = await readHistoryRows(db);
    await db.close();
    final s = summariseHistory(rows);
    expect(s['SM.0712345678'], [2, 3]);
    expect(s['PB.KPLC PREPAID#123'], [5]);
    expect(s.keys.any((k) => k.startsWith('CASH')), isFalse);
  });
}
