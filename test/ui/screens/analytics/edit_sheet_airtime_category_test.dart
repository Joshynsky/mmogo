// Row 17: an AIRTIME row shows its category as a read-only line (no picker, never the other kind);
// other types keep the picker. Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/ui/screens/analytics/edit_sheet.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_analytics_db.dart';

AnalyticsTransactionRow _row(String type, String category) => AnalyticsTransactionRow(
  id: 9,
  displayCode: 'SAMPLEED01',
  sourceType: type,
  amountCents: 10000,
  counterpartyLabel: type == 'AIRTIME' ? 'Sample Network' : 'MARY WANJIKU',
  counterpartyPhone: null,
  paybillAccountNumber: null,
  classificationId: 14,
  classificationName: category,
  occurredAt: DateTime(2026, 11, 1, 15, 20),
  transactionCostCents: 0,
  fromMessage: type == 'AIRTIME',
);

Object? _result;

Future<void> _open(WidgetTester t, AnalyticsTransactionRow row, {double scale = 1.0}) async {
  t.view.physicalSize = const Size(400, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _result = null;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                _result = await showModalBottomSheet<Object>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => AnalyticsEditSheet(
                    db: FakeAnalyticsDb(const []),
                    tx: row,
                    palette: AppPalette.light,
                    lockMessageFields: true,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final name in ['For myself', 'For another number']) {
    testWidgets('edit_sheet_airtime_category_read_only ($name)', (t) async {
      await _open(t, _row('AIRTIME', name));
      expect(find.byKey(const Key('editClassificationReadOnly')), findsOneWidget);
      expect(find.text(name), findsOneWidget);
      expect(find.byKey(const Key('editChooseClassificationButton')), findsNothing);
      expect(find.byKey(const Key('editClassificationChosen')), findsNothing);
      // The other kind is never offered anywhere in the sheet.
      expect(find.text(name == 'For myself' ? 'For another number' : 'For myself'), findsNothing);
      // Saving keeps the category id as it was.
      await t.ensureVisible(find.byKey(const Key('editSaveButton')));
      await t.tap(find.byKey(const Key('editSaveButton')));
      await t.pumpAndSettle();
      expect((_result as AnalyticsEditResult).classificationId, 14);
    });
  }

  testWidgets('edit_sheet_airtime_category_read_only at large text scale does not overflow', (t) async {
    await _open(t, _row('AIRTIME', 'For another number'), scale: 2.0);
    expect(find.byKey(const Key('editClassificationReadOnly')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('edit_sheet_non_airtime_category_picker_unchanged', (t) async {
    await _open(t, _row('SEND_MONEY', 'Family/Friends'));
    expect(find.byKey(const Key('editChooseClassificationButton')), findsOneWidget);
    expect(find.byKey(const Key('editClassificationChosen')), findsOneWidget);
    expect(find.byKey(const Key('editClassificationReadOnly')), findsNothing);
  });
}
