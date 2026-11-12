// 0.2.0 S9: the edit sheet for a row read from an M-Pesa message. Amount, date and time, phone / account,
// and transaction cost are read-only (padlock + one caption); name and category stay editable. The Fuliza
// "How it was paid" block is read-only with its own padlock note. A hand-typed row, a row with the lock
// switched off (the standard build) and a Cash row are unchanged.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/ui/screens/analytics/edit_lock_parts.dart';
import 'package:mmogo/ui/screens/analytics/edit_sheet.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_analytics_db.dart';

AnalyticsTransactionRow _row({
  String type = 'SEND_MONEY',
  bool fromMessage = true,
  String code = 'QDMFL00002',
  int ksh = 400,
}) => AnalyticsTransactionRow(
  id: 7,
  displayCode: code,
  sourceType: type,
  amountCents: ksh * 100,
  counterpartyLabel: type == 'CASH' ? null : 'MARY WANJIKU',
  counterpartyPhone: type == 'SEND_MONEY' ? '0722114455' : null,
  paybillAccountNumber: type == 'PAYBILL' ? '5566' : null,
  classificationId: 1,
  classificationName: 'Family/Friends',
  occurredAt: DateTime(2026, 11, 1, 15, 20),
  transactionCostCents: type == 'CASH' ? null : 700,
  fromMessage: fromMessage,
);

Object? _lastResult;

Future<void> _open(
  WidgetTester t,
  AnalyticsTransactionRow row, {
  bool lock = true,
  FulizaPaidInfo? paid,
  double scale = 1.0,
}) async {
  t.view.physicalSize = const Size(400, 3000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  _lastResult = null;
  await t.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async {
                _lastResult = await showModalBottomSheet<Object>(
                  context: ctx,
                  isScrollControlled: true,
                  builder: (_) => AnalyticsEditSheet(
                    db: FakeAnalyticsDb(const []),
                    tx: row,
                    palette: AppPalette.light,
                    lockMessageFields: lock,
                    fulizaPaid: paid,
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
  setUp(() => SharedPreferences.setMockInitialValues({'capture_identity_preference': true}));

  testWidgets('message row, lock ON: amount, time, phone and cost are read-only; name stays editable', (t) async {
    await _open(t, _row());
    expect(find.byKey(const Key('editAmountLocked')), findsOneWidget);
    expect(find.byKey(const Key('editDateTimeText')), findsOneWidget);
    expect(find.byKey(const Key('editPhoneLocked')), findsOneWidget);
    expect(find.byKey(const Key('editCostLocked')), findsOneWidget);
    expect(find.byKey(const Key('editAmountField')), findsNothing);
    expect(find.byKey(const Key('editPhoneField')), findsNothing);
    expect(find.byKey(const Key('editCostField')), findsNothing);
    expect(find.byKey(const Key('editDateTimeChangeLink')), findsNothing);
    expect(find.byKey(const Key('editLabelField')), findsOneWidget); // name editable
    expect(find.byKey(const Key('editChooseClassificationButton')), findsOneWidget); // category editable
    expect(find.byKey(const Key('editLockedCaption')), findsOneWidget);
    expect(find.text("From the M‑Pesa message, so it can't be changed"), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);
    expect(find.text('400.00'), findsOneWidget);
    expect(find.text('7.00'), findsOneWidget);
    expect(find.text('0722114455'), findsOneWidget);
  });

  testWidgets('locked phone keeps its Copy button while Record receiver details is on', (t) async {
    await _open(t, _row());
    expect(find.byKey(const Key('copy-phone number')), findsOneWidget);
  });

  testWidgets('Paybill row: the account is read-only', (t) async {
    await _open(t, _row(type: 'PAYBILL', code: 'QDMFL00004'));
    expect(find.byKey(const Key('editAccountLocked')), findsOneWidget);
    expect(find.byKey(const Key('editAccountField')), findsNothing);
  });

  testWidgets('save writes the message figures back unchanged', (t) async {
    await _open(t, _row());
    await t.enterText(find.byKey(const Key('editLabelField')), 'MARY W');
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('editSaveButton')));
    await t.tap(find.byKey(const Key('editSaveButton')));
    await t.pumpAndSettle();
    final r = _lastResult as AnalyticsEditResult;
    expect(r.amountCents, 40000);
    expect(r.transactionCostCents, 700);
    expect(r.counterpartyLabel, 'MARY W');
    expect(r.counterpartyPhone, '0722114455');
    expect(r.transactionOccurredAt, DateTime(2026, 11, 1, 15, 20).millisecondsSinceEpoch);
  });

  testWidgets('lock switched off (standard build): every field is editable as in 0.1.3', (t) async {
    await _open(t, _row(), lock: false);
    expect(find.byKey(const Key('editAmountField')), findsOneWidget);
    expect(find.byKey(const Key('editPhoneField')), findsOneWidget);
    expect(find.byKey(const Key('editCostField')), findsOneWidget);
    expect(find.byKey(const Key('editDateTimeChangeLink')), findsOneWidget);
    expect(find.byKey(const Key('editLockedCaption')), findsNothing);
  });

  testWidgets('a hand-typed row (not from a message) stays editable even with the lock ON', (t) async {
    await _open(t, _row(fromMessage: false));
    expect(find.byKey(const Key('editAmountField')), findsOneWidget);
    expect(find.byKey(const Key('editLockedCaption')), findsNothing);
  });

  testWidgets('a Cash row is never locked', (t) async {
    await _open(t, _row(type: 'CASH', code: 'CASH-20261101-1520'));
    expect(find.byKey(const Key('editAmountField')), findsOneWidget);
    expect(find.byKey(const Key('editLockedCaption')), findsNothing);
  });

  testWidgets('Fuliza: part paid block with the padlock note; tapping it asks the caller to open the page', (t) async {
    await _open(t, _row(ksh: 900), paid: const FulizaPaidInfo(drawCents: 60000));
    expect(find.byKey(const Key('editFulizaBlock')), findsOneWidget);
    expect(find.text('How it was paid'), findsOneWidget);
    expect(find.text('From your M‑Pesa'), findsOneWidget);
    expect(find.text('Ksh 300'), findsOneWidget);
    expect(find.text('From Fuliza'), findsOneWidget);
    expect(find.text('Ksh 600'), findsOneWidget);
    expect(find.text('Fuliza tags come from the messages and cannot be edited.'), findsOneWidget);
    await t.tap(find.byKey(const Key('editFulizaBlock')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('editFulizaBlock')), findsNothing);
    expect(_lastResult, isA<AnalyticsOpenFuliza>());
  });

  testWidgets('Fuliza: a whole borrowing says Paid with Fuliza (borrowed)', (t) async {
    await _open(t, _row(), paid: const FulizaPaidInfo(drawCents: 40000));
    expect(find.text('Paid with Fuliza'), findsOneWidget);
    expect(find.text('Ksh 400 (borrowed)'), findsOneWidget);
    expect(find.text('From your M‑Pesa'), findsNothing);
  });

  testWidgets('no Fuliza block when no borrowing paid for the row', (t) async {
    await _open(t, _row());
    expect(find.byKey(const Key('editFulizaBlock')), findsNothing);
  });

  testWidgets('large text 1.3 on a narrow phone: the locked sheet does not overflow', (t) async {
    t.view.physicalSize = const Size(360, 3000);
    await _open(t, _row(ksh: 900), paid: const FulizaPaidInfo(drawCents: 60000), scale: 1.3);
    expect(t.takeException(), isNull);
  });
}
