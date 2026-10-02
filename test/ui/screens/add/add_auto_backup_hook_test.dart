// B20: AddScreen._save tells AutoBackupService once per NEWLY saved entry,
// only after TransactionDao.insert succeeded, and a backup problem can never
// block or fail the save.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

class _Spy extends AutoBackupService {
  int calls = 0;
  Object? error;

  @override
  Future<void> onEntrySaved() async {
    calls++;
    final e = error;
    if (e != null) throw e;
  }
}

class _ThrowingInsertDb extends FakeAddDb {
  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    if (table == 'transactions') throw StateError('boom');
    return super.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }
}

Future<void> _fill(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('addAmountField')), '500');
  await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
  await tester.tap(find.byKey(const Key('addCategoryChip_101')));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AutoBackupService original;
  late _Spy spy;
  setUp(() {
    original = AutoBackupService.instance;
    spy = _Spy();
    AutoBackupService.instance = spy;
  });
  tearDown(() => AutoBackupService.instance = original);

  testWidgets('counter_incremented_from_add_save: one call per saved entry, after the insert', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _fill(tester);
    expect(spy.calls, 0, reason: 'nothing is counted before the entry is saved');
    await reviewAndConfirm(tester);
    expect(db.insertedTransactions, hasLength(1));
    expect(spy.calls, 1);
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a failed insert is not counted', (tester) async {
    final db = _ThrowingInsertDb();
    await pumpAdd(tester, db);
    await _fill(tester);
    await reviewAndConfirm(tester);
    expect(find.textContaining('Could not save this transaction'), findsOneWidget);
    expect(spy.calls, 0);
  });

  testWidgets('failure_isolation: an auto-backup error never blocks or fails the save', (tester) async {
    spy.error = StateError('backup exploded');
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _fill(tester);
    await reviewAndConfirm(tester);
    expect(tester.takeException(), isNull);
    expect(db.insertedTransactions, hasLength(1));
    expect(find.text('Saved'), findsOneWidget);
    expect(find.textContaining('Could not save'), findsNothing);
  });

  testWidgets('with auto-backup off (the default) saving works and counts nothing', (tester) async {
    AutoBackupService.instance = original; // the real service, switched off by default
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _fill(tester);
    await reviewAndConfirm(tester);
    expect(tester.takeException(), isNull);
    expect(db.insertedTransactions, hasLength(1));
    expect(find.text('Saved'), findsOneWidget);
  });
}
