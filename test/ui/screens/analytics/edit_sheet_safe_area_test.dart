// A full-height edit sheet must keep its header (title, Delete) below the status bar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/ui/screens/analytics/edit_sheet.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_analytics_db.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'capture_identity_preference': true}));

  testWidgets('withdrawal edit sheet: Delete and title sit below a 40px status bar', (t) async {
    // Short screen so the sheet fills it to the top.
    t.view.physicalSize = const Size(400, 500);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final row = AnalyticsTransactionRow(
      id: 7,
      displayCode: 'QDMFL00002',
      sourceType: 'AGENT_WITHDRAWAL',
      amountCents: 500000,
      counterpartyLabel: 'JOHN KAMAU',
      counterpartyPhone: null,
      paybillAccountNumber: null,
      classificationId: 1,
      classificationName: 'Withdrawal',
      occurredAt: DateTime(2026, 11, 1, 15, 20),
      transactionCostCents: 2900,
      fromMessage: true,
    );
    await t.pumpWidget(
      MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(padding: const EdgeInsets.only(top: 40), viewPadding: const EdgeInsets.only(top: 40)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showModalBottomSheet<Object>(
                context: ctx,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (_) => AnalyticsEditSheet(db: FakeAnalyticsDb(const []), tx: row, palette: AppPalette.light),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.getTopLeft(find.byKey(const Key('editDeleteButton'))).dy, greaterThanOrEqualTo(40));
    expect(t.getTopLeft(find.byKey(const Key('editTitle'))).dy, greaterThanOrEqualTo(40));
  });
}
