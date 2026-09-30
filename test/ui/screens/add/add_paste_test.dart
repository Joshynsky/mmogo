// Regression tests restored after the T27 rewrite: what a pasted M-Pesa SMS
// does (provenance, duplicate flag, Paybill fields).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pasted entry saves with raw_parse_source SMS_PARSE', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db, captureReceiver: true);
    await pasteSms(tester, sendMoneySms);
    await tester.tap(find.byKey(const Key('addCategoryChip_101')));
    await settle(tester);
    await reviewAndConfirm(tester);

    final row = db.insertedTransactions.single;
    expect(row['raw_parse_source'], 'SMS_PARSE');
    expect(row['display_code'], 'THA7K2P9QX');
  });

  testWidgets('a parsed code that already exists is flagged and blocks Review', (tester) async {
    final db = FakeAddDb()
      ..transactions.add({'id': 1, 'display_code': 'THA7K2P9QX', 'source_type': 'SEND_MONEY', 'deleted_at': null});
    await pumpAdd(tester, db, captureReceiver: true);
    await pasteSms(tester, sendMoneySms);
    await tester.tap(find.byKey(const Key('addCategoryChip_101')));
    await settle(tester);

    expect(find.byKey(const Key('addCodeDuplicateError')), findsOneWidget);
    expect(reviewEnabled(tester), isFalse);
  });

  testWidgets('a Paybill parse fills Business and Account', (tester) async {
    final db = FakeAddDb();
    await pumpAdd(tester, db, captureReceiver: true);
    await pasteSms(tester, paybillSms);

    expect(tester.widget<TextField>(find.byKey(const Key('addReceiverNameField'))).controller!.text, 'KPLC PREPAID');
    expect(tester.widget<TextField>(find.byKey(const Key('addReceiverSubField'))).controller!.text, '12345678');
    expect(tester.widget<TextField>(find.byKey(const Key('addCodeField'))).controller!.text, 'TGB1234567');
  });
}
