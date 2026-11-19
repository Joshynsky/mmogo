// 0.2.1: the "Spent on" row in Add's "Check before saving" (type W only). Made-up values only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/add/review_sheet.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

Widget _sheet(String? spentOn) => MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: ReviewSheet(
          isCash: false,
          typeLabel: 'Withdrawal',
          amountCents: 80000,
          counterpartyRowLabel: 'Agent',
          counterpartyRowValue: 'Test Agent',
          whenText: 'today',
          code: 'ABC1234567',
          feeCents: 2800,
          categoryName: 'Withdrawal',
          spentOnText: spentOn,
          alwaysForThem: false,
          onConfirm: () async => null,
        ),
      ),
    );

void main() {
  testWidgets('a category shows what it adds; Cash only says only the fee is counted; none for other types', (t) async {
    await t.pumpWidget(_sheet('Rent (adds Cash — Rent, Ksh 800.00)'));
    expect(find.text('Spent on'), findsOneWidget);
    expect(find.text('Rent (adds Cash — Rent, Ksh 800.00)'), findsOneWidget);
    await t.pumpWidget(_sheet('Cash only (only the fee is counted)'));
    expect(find.text('Cash only (only the fee is counted)'), findsOneWidget);
    await t.pumpWidget(_sheet(null));
    expect(find.text('Spent on'), findsNothing);
  });
}
