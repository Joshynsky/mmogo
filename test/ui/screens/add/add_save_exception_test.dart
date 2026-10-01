// B4: a non-database exception while saving (here a StateError from the DAO
// insert) is caught: the review sheet shows the plain "Could not save"
// message, the screen stays up and usable, nothing is saved and no "Saved"
// snackbar appears. (The existing error surface is the review sheet's inline
// message; see the B4 report.)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('add_save_exception_shows_snackbar_test: a throwing insert shows the error, no crash, nothing saved',
      (tester) async {
    final db = _ThrowingInsertDb();
    await pumpAdd(tester, db);
    await tester.enterText(find.byKey(const Key('addAmountField')), '500');
    await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
    await tester.tap(find.byKey(const Key('addCategoryChip_101')));
    await settle(tester);

    await reviewAndConfirm(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save this transaction'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);
    expect(find.byKey(const Key('addReviewSheet')), findsOneWidget); // not stuck: the sheet is usable again
    expect(db.insertedTransactions, isEmpty);
    expect(db.upsertCalls, isEmpty);
    // Confirm is enabled again (not stuck on "saving").
    expect(tester.widget<FilledButton>(find.byKey(const Key('addReviewConfirmButton'))).onPressed, isNotNull);
  });
}
