// Widget tests for lib/ui/screens/recently_deleted_screen.dart.
//
// Per this project's disclosed environment finding (first hit at T7, see
// manage_classifications_screen_test.dart's header comment): a real
// sqflite_common_ffi `Database` hangs indefinitely inside a `testWidgets`
// test in this environment. This file drives the screen's real
// countdown/restore/empty-state/coming-soon-row UI logic against a
// minimal, explicit fake in-memory `Database` (`_FakeDb` below) — not a
// real one.
//
// The real `RecentlyDeletedDao.deletedTransactions` query and
// `TransactionDao.restore`/`purgeExpiredSoftDeletes` (real column writes,
// real hard-delete SQL) are separately, authoritatively proven against a
// genuine in-memory sqlite3 database in
// `test/data/recently_deleted_dao_test.dart` and
// `test/data/transaction_dao_test.dart` — this screen calls those DAOs
// directly and unconditionally.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/ui/screens/recently_deleted_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeDb implements Database {
  _FakeDb({required this.transactions});

  final List<Map<String, Object?>> transactions;

  final classifications = <Map<String, Object?>>[
    {'id': 101, 'name': 'Family/Friends'},
    {'id': 102, 'name': 'Rent'},
  ];

  String _classificationName(int id) =>
      classifications.firstWhere((c) => c['id'] == id)['name'] as String;

  int purgeCallCount = 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('WHERE t.deleted_at IS NOT NULL')) {
      // RecentlyDeletedDao.deletedTransactions
      final rows = transactions.where((t) => t['deleted_at'] != null).toList()
        ..sort((a, b) => (b['deleted_at'] as int).compareTo(a['deleted_at'] as int));
      return rows
          .map(
            (t) => {
              'id': t['id'],
              'display_code': t['display_code'],
              'source_type': t['source_type'],
              'amount_cents': t['amount_cents'],
              'counterparty_label': t['counterparty_label'],
              'classification_name': _classificationName(t['classification_id'] as int),
              'deleted_at': t['deleted_at'],
            },
          )
          .toList();
    }
    throw UnsupportedError('_FakeDb.rawQuery: unexpected sql "$sql"');
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'transactions') {
      final id = whereArgs![0] as int;
      final tx = transactions.firstWhere((t) => t['id'] == id);
      tx.addAll(values);
      return 1;
    }
    throw UnsupportedError('_FakeDb.update: unexpected table "$table"');
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    if (table == 'transactions') {
      purgeCallCount++;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cutoff = now - 3600000;
      final before = transactions.length;
      transactions.removeWhere((t) => t['deleted_at'] != null && (t['deleted_at'] as int) < cutoff);
      return before - transactions.length;
    }
    throw UnsupportedError('_FakeDb.delete: unexpected table "$table"');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _deletedTx({
  required int id,
  required int deletedAt,
  String sourceType = 'SEND_MONEY',
  String? counterpartyLabel = 'JOHN KAMAU',
  int classificationId = 101,
  int amountCents = 150000,
}) => {
      'id': id,
      'display_code': 'THA7K2P9QX$id',
      'source_type': sourceType,
      'amount_cents': amountCents,
      'counterparty_label': counterpartyLabel,
      'classification_id': classificationId,
      'deleted_at': deletedAt,
    };

Widget _harness(Database db) => MaterialApp(home: RecentlyDeletedScreen(db: db));

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('empty state shows "Nothing here right now." and the coming-soon row', (tester) async {
    final db = _FakeDb(transactions: []);
    await tester.pumpWidget(_harness(db));
    await _settle(tester);

    expect(find.text('Nothing here right now.'), findsOneWidget);
    expect(find.text('View & restore from the companion web page'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  testWidgets(
    'renders soft-deleted rows most-recently-deleted first, each with a live countdown and Restore',
    (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final db = _FakeDb(
        transactions: [
          _deletedTx(id: 1, deletedAt: now - 10 * 60000, counterpartyLabel: 'OLDER DELETE'), // 10 min ago
          _deletedTx(id: 2, deletedAt: now - 60000, counterpartyLabel: 'NEWER DELETE'), // 1 min ago
        ],
      );
      await tester.pumpWidget(_harness(db));
      await _settle(tester);

      expect(find.text('Nothing here right now.'), findsNothing);
      expect(find.text('OLDER DELETE'), findsOneWidget);
      expect(find.text('NEWER DELETE'), findsOneWidget);

      // most-recently-deleted first: row 2 (1 min ago) before row 1 (10 min ago).
      final row2Top = tester.getTopLeft(find.byKey(const Key('deletedRow_2'))).dy;
      final row1Top = tester.getTopLeft(find.byKey(const Key('deletedRow_1'))).dy;
      expect(row2Top, lessThan(row1Top));

      // Countdown text roughly matches "Nm SSs left" for each (~50min / ~59min remaining).
      expect(find.textContaining('m ', findRichText: false), findsWidgets);
      expect(find.byKey(const Key('deletedRowCountdown_1')), findsOneWidget);
      expect(find.byKey(const Key('deletedRowCountdown_2')), findsOneWidget);
    },
  );

  testWidgets('tapping Restore clears deleted_at, shows the toast, and removes the row', (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final db = _FakeDb(transactions: [_deletedTx(id: 1, deletedAt: now - 60000)]);
    await tester.pumpWidget(_harness(db));
    await _settle(tester);

    expect(find.text('JOHN KAMAU'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deletedRowRestoreButton_1')));
    await tester.pumpAndSettle();

    expect(find.text('Transaction restored'), findsOneWidget);
    expect(find.text('JOHN KAMAU'), findsNothing);
    expect(find.text('Nothing here right now.'), findsOneWidget);
    final row = db.transactions.firstWhere((t) => t['id'] == 1);
    expect(row['deleted_at'], isNull);
  });

  testWidgets(
    'purgeExpiredSoftDeletes runs on this page\'s own load (not just at app launch)',
    (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final db = _FakeDb(transactions: [_deletedTx(id: 1, deletedAt: now - 3700000)]); // 1h1m40s ago
      await tester.pumpWidget(_harness(db));
      await _settle(tester);

      expect(db.purgeCallCount, greaterThanOrEqualTo(1));
      expect(db.transactions, isEmpty); // hard-purged already
      expect(find.text('Nothing here right now.'), findsOneWidget);
    },
  );

  testWidgets(
    'a live tick that observes a row cross the 1-hour boundary re-runs the purge+reload path '
    'without waiting for a relaunch',
    (tester) async {
      // A raw `DateTime.now()` isn't affected by flutter_test's fake-async
      // `pump(duration)` (that only fast-forwards Timer/Future scheduling,
      // not what `DateTime.now()` itself returns) — asserting the tick
      // path deterministically therefore needs this screen's own `now`
      // test seam (see recently_deleted_screen.dart's doc comment on it),
      // not real wall-clock elapsed time.
      final fixedNow = DateTime.now();
      var injectedNow = fixedNow;
      // Real-clock-wise this is only 1 second old (nowhere near real
      // expiry), so the fake DB's own real-time purge check at bootstrap
      // does NOT remove it — only the widget's injected clock will
      // observe this row crossing the boundary.
      final db = _FakeDb(
        transactions: [_deletedTx(id: 1, deletedAt: fixedNow.millisecondsSinceEpoch - 1000)],
      );
      await tester.pumpWidget(
        MaterialApp(home: RecentlyDeletedScreen(db: db, now: () => injectedNow)),
      );
      await _settle(tester);

      expect(find.text('JOHN KAMAU'), findsOneWidget);
      expect(db.purgeCallCount, 1); // bootstrap's own initial load

      // Advance the INJECTED clock (not real time) past this row's own
      // 1-hour boundary, then let a real Timer.periodic tick actually
      // fire (flutter_test's fake-async pump(duration) DOES advance
      // Timer scheduling).
      injectedNow = fixedNow.add(const Duration(hours: 1, seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(db.purgeCallCount, greaterThanOrEqualTo(2)); // the tick re-ran purge+reload
    },
  );
}
