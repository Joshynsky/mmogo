// Regression tests restored after the T27 rewrite: "Always use" auto-apply
// (old E1/E2), the remembered receiver preference (old D3) and the paired
// name/phone rule.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

FakeAddDb _dbWithJohn() => FakeAddDb()
  ..counterpartyMap.add({
    'source_type': 'SEND_MONEY',
    'counterparty_key': '0798630424',
    'classification_id': 101,
    'auto_apply': 0,
    'updated_at': 0,
  });

/// Type John (known), wait for the suggestion, tick "Always use".
Future<void> _tickForJohn(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
  await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
  await settle(tester);
  await tester.tap(find.byKey(const Key('addAlwaysUseCheckbox')));
  await settle(tester);
}

Future<void> _fillAmountAndCode(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('addAmountField')), '500');
  await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('"Always use" (old E1/E2)', () {
    testWidgets('tick for A, retype the phone to B, save -> setAutoApply never runs', (tester) async {
      final db = _dbWithJohn();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tickForJohn(tester);
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0722334455');
      await settle(tester);
      await _fillAmountAndCode(tester);
      expect(reviewEnabled(tester), isTrue);
      await reviewAndConfirm(tester);

      expect(db.insertedTransactions, hasLength(1));
      expect(db.autoApplyCalls, isEmpty);
    });

    testWidgets('tick for A, then paste an SMS for a different person, save -> no setAutoApply', (tester) async {
      final db = _dbWithJohn();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tickForJohn(tester);
      await pasteSms(tester, marySms);
      expect(tester.widget<TextField>(find.byKey(const Key('addReceiverNameField'))).controller!.text, 'MARY WANJIRU');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      await reviewAndConfirm(tester);

      expect(db.insertedTransactions, hasLength(1));
      expect(db.autoApplyCalls, isEmpty);
    });

    testWidgets('tick then untick, then save -> no setAutoApply', (tester) async {
      final db = _dbWithJohn();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tickForJohn(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isTrue);
      await tester.tap(find.byKey(const Key('addAlwaysUseCheckbox')));
      await settle(tester);
      expect(tester.widget<Checkbox>(find.byType(Checkbox).last).value, isFalse);
      await _fillAmountAndCode(tester);
      await reviewAndConfirm(tester);

      expect(db.insertedTransactions, hasLength(1));
      expect(db.autoApplyCalls, isEmpty);
    });

    testWidgets('tick then Back from the review sheet -> nothing is written', (tester) async {
      final db = _dbWithJohn();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tickForJohn(tester);
      await _fillAmountAndCode(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewBackButton')));
      await settle(tester);

      expect(db.insertedTransactions, isEmpty);
      expect(db.upsertCalls, isEmpty);
      expect(db.autoApplyCalls, isEmpty);
    });
  });

  group('receiver preference (old D3)', () {
    testWidgets('unticked "Also record the receiver" is remembered across a remount', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true); // default: ticked
      expect(find.byKey(const Key('addReceiverNameField')), findsOneWidget);

      await tester.tap(find.byKey(const Key('addCaptureCheckbox')));
      await settle(tester);
      expect(find.byKey(const Key('addReceiverNameField')), findsNothing);

      await tester.tap(find.byKey(const Key('addCloseButton')));
      await settle(tester);
      await tester.tap(find.text('root'));
      await settle(tester);

      expect(find.byKey(const Key('addCaptureCheckbox')), findsOneWidget);
      expect(find.byKey(const Key('addReceiverNameField')), findsNothing);
    });
  });

  group('paired name/phone rule', () {
    testWidgets('with the receiver box on, only one of name/phone keeps Review & save disabled', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _fillAmountAndCode(tester);
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      expect(reviewEnabled(tester), isFalse); // neither filled

      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await settle(tester);
      expect(reviewEnabled(tester), isFalse); // name only

      await tester.enterText(find.byKey(const Key('addReceiverNameField')), '');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await settle(tester);
      expect(reviewEnabled(tester), isFalse); // phone only

      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await settle(tester);
      expect(reviewEnabled(tester), isTrue); // both
    });
  });
}
