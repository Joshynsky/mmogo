// B3: length limits on the Add form. A 101-character category name is cut at
// 100 and a 201-character receiver name / label at 200. The counter stays
// hidden (the onboarding name field's style). Values already longer than the
// limit load untouched (only typing is limited).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new category name: 101 characters are cut at 100, no counter shown', (tester) async {
    await pumpAdd(tester, FakeAddDb());
    await tester.tap(find.byKey(const Key('addCategoryNewButton')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('addCategoryNewField')), 'a' * 101);
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byKey(const Key('addCategoryNewField')));
    expect(field.controller!.text.length, 100);
    expect(find.text('100/100'), findsNothing);
  });

  testWidgets('receiver name and label: 201 characters are cut at 200', (tester) async {
    await pumpAdd(tester, FakeAddDb(), captureReceiver: true);

    await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'b' * 201);
    await tester.enterText(find.byKey(const Key('addReceiverSubField')), 'c' * 201);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('addReceiverNameField'))).controller!.text.length, 200);
    expect(tester.widget<TextField>(find.byKey(const Key('addReceiverSubField'))).controller!.text.length, 200);
    expect(find.text('200/200'), findsNothing);
  });
}
