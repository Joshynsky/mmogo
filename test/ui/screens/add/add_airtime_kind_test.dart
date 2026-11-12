// WBS row 17: the parser decides the Airtime kind; manual Add is For myself.
// Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/add/add_draft.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

const _ownSms =
    'QZU1P6R3TG confirmed.You bought Ksh30.00 of airtime on 12/11/26 at 3:41 PM.New  balance is Ksh70.00. '
    'Transaction cost, Ksh0.00.';
const _otherSms =
    'QZU1P6R3TH confirmed.You bought Ksh30.00 of airtime for 0712345678 on 12/11/26 at 3:41 PM.New  balance is Ksh70.00. '
    'Transaction cost, Ksh0.00.';

Future<void> _paste(WidgetTester tester, String text) async {
  await tester.tap(find.byKey(const Key('addPasteButton')));
  await settle(tester);
  await tester.enterText(find.byKey(const Key('addPasteTextField')), text);
  await tester.tap(find.byKey(const Key('addPasteSubmitButton')));
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fixedSeedKey: myself by default, other when asked', () {
    expect(AddDraft.fixedSeedKey('AIRTIME'), 'AIRTIME:airtime');
    expect(AddDraft.fixedSeedKey('AIRTIME', airtimeOther: true), 'AIRTIME:for_another_number');
    expect(AddDraft.fixedSeedKey('AGENT_WITHDRAWAL', airtimeOther: true), 'AGENT_WITHDRAWAL:cash_withdrawal');
    expect(AddDraft.fixedSeedKey('SEND_MONEY'), isNull);
  });

  testWidgets('parse own airtime -> For myself, saved with that category', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _paste(tester, _ownSms);
    expect(find.text('Category: Airtime'), findsOneWidget); // fake row 121 stands for For myself
    await reviewAndConfirm(tester);
    expect(db.insertedTransactions.single['classification_id'], 121);
  });

  testWidgets('parse for-number airtime -> For another number, saved with that category', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _paste(tester, _otherSms);
    expect(find.text('Category: For another number'), findsOneWidget);
    expect(find.byKey(const Key('addCategoryNewButton')), findsNothing);
    await reviewAndConfirm(tester);
    final row = db.insertedTransactions.single;
    expect(row['classification_id'], 122);
    expect(row['source_type'], 'AIRTIME');
  });

  testWidgets('manual airtime -> For myself', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await tester.ensureVisible(find.byKey(const Key('addTypePill_AIRTIME')));
    await tester.tap(find.byKey(const Key('addTypePill_AIRTIME')));
    await settle(tester);
    expect(find.text('Category: Airtime'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('addAmountField')), '50');
    await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
    await settle(tester);
    await reviewAndConfirm(tester);
    expect(db.insertedTransactions.single['classification_id'], 121);
  });

  testWidgets('Start over after a for-number parse resets to For myself', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db);
    await _paste(tester, _otherSms);
    expect(find.text('Category: For another number'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('addStartOverButton')));
    await tester.tap(find.byKey(const Key('addStartOverButton')));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('addTypePill_AIRTIME')));
    await tester.tap(find.byKey(const Key('addTypePill_AIRTIME')));
    await settle(tester);
    expect(find.text('Category: Airtime'), findsOneWidget);
    expect(find.text('Category: For another number'), findsNothing);
  });
}
