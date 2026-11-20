/// AUTOREAD HISTORY reader over the live database file, READ ONLY, through sqflite_common_ffi (dart:ffi and
/// the bundled sqlite3 library). It needs no Flutter plugin, so it works in the headless Parse engine, where
/// the sqflite plugin is not registered (spike 18-11-2026: about 0.7 s; 2 of 4 runs timed out at 1.5 s while
/// the app held the database open, hence the hard cap and the preferences fallback).
///
/// Reads the newest rows of the person's type and compares the key in Dart. Any failure or timeout answers
/// null (unavailable); it never throws and never writes. No text is logged or put in an error.
library;

import 'dart:async';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../rules/rule_model.dart';
import 'history_reader.dart';
import 'history_summary_codec.dart';
import 'history_summary_writer.dart' show kHistoryRowsSql;

/// The hard cap on one lookup (open, query, close).
const Duration kFfiHistoryCap = Duration(milliseconds: 1500);

/// Newest rows scanned per lookup (a person older than that reads as no history).
const int kFfiScanLimit = 1000;

/// `/data/data/<package>/databases/mmogo.db` for the running process, from /proc/self/cmdline; null when the
/// package cannot be read (not Android).
Future<String?> defaultMmogoDbPath() async {
  try {
    final first = (await File('/proc/self/cmdline').readAsString()).split('\u0000').first.trim();
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$').hasMatch(first)) return null;
    return '/data/data/$first/databases/mmogo.db';
  } catch (_) {
    return null;
  }
}

const Map<ReceiverType, String> _dbType = {
  ReceiverType.sendMoney: 'SEND_MONEY',
  ReceiverType.payBill: 'PAYBILL',
  ReceiverType.buyGoods: 'BUY_GOODS',
  ReceiverType.pochi: 'POCHI_LA_BIASHARA',
};

class FfiHistoryReader implements HistoryReader {
  FfiHistoryReader({
    Future<String?> Function()? dbPath,
    DatabaseFactory? factory,
    this.cap = kFfiHistoryCap,
    this.scanLimit = kFfiScanLimit,
  })  : _dbPath = dbPath ?? defaultMmogoDbPath,
        _factory = factory;

  final Future<String?> Function() _dbPath;
  final DatabaseFactory? _factory;
  final Duration cap;
  final int scanLimit;

  // The history query narrowed to one type: the IN list becomes `= ?`.
  static final String _sql = kHistoryRowsSql.replaceFirst(
    "source_type IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA')",
    'source_type = ?',
  );

  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) async {
    if (key.isEmpty || key.length > kHistMaxKeyLength) return null;
    var timedOut = false;
    Future<List<int>?> work() async {
      Database? db;
      try {
        final path = await _dbPath();
        if (path == null || !File(path).existsSync()) return null;
        db = await (_factory ?? databaseFactoryFfi)
            .openDatabase(path, options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
        if (timedOut) return null;
        final rows = await db.rawQuery(_sql, [_dbType[type], scanLimit]);
        final wanted = historyPersonId(type, key);
        final cats = <int>[];
        for (final r in rows) {
          final cat = r['classification_id'];
          if (cat is! int) continue;
          final id = historyPersonIdOfRow(
            sourceType: r['source_type'] as String,
            label: r['counterparty_label'] as String?,
            phone: r['counterparty_phone'] as String?,
            account: r['paybill_account_number'] as String?,
          );
          if (id != wanted) continue;
          cats.add(cat);
          if (cats.length >= kHistLastRecords) break;
        }
        return topTwoCategories(cats);
      } catch (_) {
        return null;
      } finally {
        // A late finish after the cap still closes its own handle.
        try {
          await db?.close();
        } catch (_) {}
      }
    }

    try {
      return await work().timeout(cap);
    } catch (_) {
      timedOut = true;
      return null;
    }
  }
}
