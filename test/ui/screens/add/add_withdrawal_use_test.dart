// 0.2.1: Add, type W: "What was this money for?" under Category: Withdrawal. Fake Add database (no real
// categories), so only the block, its default and its sentence are checked here; the entry is written by
// LinkedCashDao (covered in test/data/linked_cash_dao_test.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

void main() {
  testWidgets('the block shows only for Withdrawal; Cash only is the default and the sentence says so', (tester) async {
    await pumpAdd(tester, FakeAddDb());
    expect(find.byKey(const Key('addWithdrawalUse')), findsNothing, reason: 'Send Money');
    await tester.tap(find.byKey(const Key('addTypePill_AGENT_WITHDRAWAL')));
    await settle(tester);
    expect(find.byKey(const Key('addFixedCategory')), findsOneWidget);
    expect(find.byKey(const Key('addWithdrawalUse')), findsOneWidget);
    expect(find.text('What was this money for?'), findsOneWidget);
    expect(find.byKey(const Key('wdChipCashOnly')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('wdSentence'))).data, contains('Nothing else is added'));
    // The block sits under the fixed category line.
    expect(
      tester.getTopLeft(find.byKey(const Key('addWithdrawalUse'))).dy,
      greaterThan(tester.getTopLeft(find.byKey(const Key('addFixedCategory'))).dy),
    );
    await tester.tap(find.byKey(const Key('addTypePill_AIRTIME')));
    await settle(tester);
    expect(find.byKey(const Key('addWithdrawalUse')), findsNothing, reason: 'Airtime');
  });
}
