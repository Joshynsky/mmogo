// QA fix F6: the Analytics edit sheet rejects a bad cost, saves blank
// identity fields as NULL (not ''), and shows a plain message if the update
// fails instead of throwing unhandled.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<FakeAnalyticsDb> _pumpEdit(WidgetTester tester, String rowName) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final db = FakeAnalyticsDb(analyticsSampleRows());
  await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => analyticsTestNow)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(rowName));
  await tester.pumpAndSettle();
  return db;
}

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('editSaveButton'))).onPressed != null;

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a cost above the cap is rejected: Save is off and a message shows (was: silently saved as 0)', (tester) async {
    final db = await _pumpEdit(tester, 'JOHN KAMAU');
    await tester.enterText(find.byKey(const Key('editCostField')), '20000000');
    await tester.pump();
    expect(_saveEnabled(tester), isFalse);
    expect(find.text('Enter a cost from 0 to 10,000,000.00'), findsOneWidget);
    expect(db.byId(1)['transaction_cost_cents'], 2200);
  });

  testWidgets('a negative cost cannot be typed, so it can never be stored', (tester) async {
    final db = await _pumpEdit(tester, 'JOHN KAMAU');
    await tester.enterText(find.byKey(const Key('editCostField')), '-5');
    await tester.pump();
    expect(tester.widget<TextField>(find.byKey(const Key('editCostField'))).controller!.text, '22.00');
    await tester.tap(find.byKey(const Key('editSaveButton')));
    await tester.pumpAndSettle();
    expect(db.byId(1)['transaction_cost_cents'], 2200);
  });

  testWidgets('blank name and phone are saved as NULL, not an empty string', (tester) async {
    final db = await _pumpEdit(tester, 'JOHN KAMAU');
    await tester.enterText(find.byKey(const Key('editLabelField')), '  ');
    await tester.enterText(find.byKey(const Key('editPhoneField')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('editSaveButton')));
    await tester.pumpAndSettle();
    expect(db.byId(1)['counterparty_label'], isNull);
    expect(db.byId(1)['counterparty_phone'], isNull);
    await _drain(tester);
  });

  testWidgets('a blank Paybill account is saved as NULL', (tester) async {
    final db = await _pumpEdit(tester, 'DSTV KENYA');
    await tester.enterText(find.byKey(const Key('editLabelField')), '');
    await tester.enterText(find.byKey(const Key('editAccountField')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('editSaveButton')));
    await tester.pumpAndSettle();
    expect(db.byId(3)['counterparty_label'], isNull);
    expect(db.byId(3)['paybill_account_number'], isNull);
    await _drain(tester);
  });

  testWidgets('a failed update shows a plain message, no raw exception, and leaves the row alone', (tester) async {
    final db = await _pumpEdit(tester, 'JOHN KAMAU');
    db.updateError = FakeDatabaseException('CHECK constraint failed: transactions');
    await tester.enterText(find.byKey(const Key('editAmountField')), '2000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('editSaveButton')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Could not save the changes'), findsOneWidget);
    expect(find.textContaining('SqfliteFfiException'), findsNothing);
    expect(db.byId(1)['amount_cents'], 150000);
    await _drain(tester);
  });
}
