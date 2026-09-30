// Regression tests restored after the T27 rewrite (old D1/D5 code checks,
// empty-fee rule, Back-writes-nothing, E4). See add_screen_test.dart for the
// main flows.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

/// The counterparty upsert throws AFTER the transaction insert (old E4).
class _FailingUpsertDb extends FakeAddDb {
  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    if (sql.contains('INSERT INTO counterparty_classification_map')) {
      throw StateError('boom');
    }
    return super.rawInsert(sql, arguments);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Code field (old D1)', () {
    testWidgets('typed lowercase is forced to uppercase', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await tester.enterText(find.byKey(const Key('addCodeField')), 'tha7k2p9qx');
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('addCodeField'))).controller!.text, 'THA7K2P9QX');
    });

    testWidgets('9 characters shows the shape error and blocks Review; 10 clears it', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD12345');
      await settle(tester);
      expect(find.byKey(const Key('addCodeShapeError')), findsOneWidget);
      expect(reviewEnabled(tester), isFalse);

      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
      await settle(tester);
      expect(find.byKey(const Key('addCodeShapeError')), findsNothing);
      expect(reviewEnabled(tester), isTrue);
    });
  });

  group('save details', () {
    testWidgets('an empty Fee does not block Review and saves as 0', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('addFeeField'))).controller!.text, isEmpty);
      expect(reviewEnabled(tester), isTrue);

      await reviewAndConfirm(tester);
      expect(db.insertedTransactions.single['transaction_cost_cents'], 0);
    });

    testWidgets('Back from the review sheet writes nothing and keeps the form', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);

      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(find.byKey(const Key('addReviewSheet')), findsOneWidget);
      await tester.tap(find.byKey(const Key('addReviewBackButton')));
      await settle(tester);

      expect(find.byKey(const Key('addReviewSheet')), findsNothing);
      expect(find.byKey(const Key('addAmountField')), findsOneWidget); // still on Add
      expect(db.insertedTransactions, isEmpty);
      expect(db.upsertCalls, isEmpty);
      expect(db.autoApplyCalls, isEmpty);
    });

    testWidgets('a counterparty-memory failure after the insert still saves cleanly (old E4)', (tester) async {
      final db = _FailingUpsertDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      await reviewAndConfirm(tester);

      expect(tester.takeException(), isNull);
      expect(db.insertedTransactions, hasLength(1));
      expect(find.text('root'), findsOneWidget); // Add popped
      expect(find.text('Saved'), findsOneWidget);
    });
  });
}
