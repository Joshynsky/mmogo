// B3b: length limits on the Analytics edit sheet. Label, phone and account
// fields cut typing at 200 (counter hidden, like the Add screen); a saved
// value that is already longer loads in full and is not truncated silently.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_analytics_db.dart';

Future<void> _pumpEdit(WidgetTester tester, List<Map<String, Object?>> rows, String rowName) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AnalyticsScreen(db: FakeAnalyticsDb(rows), clock: () => analyticsTestNow)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(rowName));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('label and phone: 201 characters are cut at 200, no counter shown (Send Money)', (tester) async {
    await _pumpEdit(tester, analyticsSampleRows(), 'JOHN KAMAU');
    await tester.enterText(find.byKey(const Key('editLabelField')), 'a' * 201);
    await tester.enterText(find.byKey(const Key('editPhoneField')), '7' * 201);
    await tester.pump();
    expect(_text(tester, 'editLabelField').length, 200);
    expect(_text(tester, 'editPhoneField').length, 200);
    expect(find.textContaining('/200'), findsNothing);
  });

  testWidgets('account number: 201 characters are cut at 200 (Paybill)', (tester) async {
    await _pumpEdit(tester, analyticsSampleRows(), 'DSTV KENYA');
    await tester.enterText(find.byKey(const Key('editAccountField')), '9' * 201);
    await tester.pump();
    expect(_text(tester, 'editAccountField').length, 200);
    expect(find.textContaining('/200'), findsNothing);
  });

  testWidgets('a saved value longer than 200 loads in full and is not truncated', (tester) async {
    final longLabel = 'L' * 230;
    final rows = [fakeTx(id: 1, at: DateTime(2026, 9, 24, 9), label: longLabel, phone: '0' * 210)];
    await _pumpEdit(tester, rows, 'L' * 230);
    expect(_text(tester, 'editLabelField'), longLabel);
    expect(_text(tester, 'editPhoneField'), '0' * 210);
  });
}
