// Shared harness for the T27 Add-screen widget tests in test/ui/screens/add/.
// Pushes the real AddScreen over a root page (Add pops itself on save) with a
// FakeAddDb (test/support/fake_add_db.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/data/prefs/app_prefs.dart';
import 'package:mpesa_tracker/ui/screens/add/add_screen.dart';
import 'package:mpesa_tracker/ui/shell/app_messenger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_add_db.dart';

/// [captureReceiver] mirrors the remembered "Also record the receiver..." box.
/// Its real default is ON, so tests that are not about receiver capture start
/// with it OFF. The first-run hint is marked seen.
Future<void> pumpAdd(WidgetTester tester, FakeAddDb db, {bool captureReceiver = false}) async {
  SharedPreferences.setMockInitialValues({
    'hint_seen_$addHintId': true,
    if (!captureReceiver) AppPrefs.keyCaptureIdentityPreference: false,
  });
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    scaffoldMessengerKey: appMessengerKey,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddScreen(db: db))),
            child: const Text('root'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('root'));
  await tester.pumpAndSettle();
}

Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

/// Paste [sms] through the paste sheet and submit it.
Future<void> pasteSms(WidgetTester tester, String sms) async {
  await tester.tap(find.byKey(const Key('addPasteButton')));
  await settle(tester);
  await tester.enterText(find.byKey(const Key('addPasteTextField')), sms);
  await tester.tap(find.byKey(const Key('addPasteSubmitButton')));
  await settle(tester);
}

/// Review & save, then Confirm & save.
Future<void> reviewAndConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('addReviewButton')));
  await settle(tester);
  await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
  await settle(tester);
}

bool reviewEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed != null;

const sendMoneySms = 'THA7K2P9QX Confirmed. Ksh1500.00 sent to JOHN KAMAU 0798630424 on 25/9/26 at '
    '11:25 AM. New M-PESA balance is Ksh3210.00. Transaction cost, Ksh22.00.';

const marySms = 'TXY1234567 Confirmed. Ksh500.00 sent to MARY WANJIRU 0722334455 on 17/9/26 at '
    '11:25 AM. New M-PESA balance is Ksh3210.00. Transaction cost, Ksh22.00.';

const paybillSms = 'TGB1234567 Confirmed. Ksh2,000.00 sent to KPLC PREPAID for account 12345678 on '
    '17/9/26 at 10:00 AM. New M-PESA balance is Ksh3,000.00. Transaction cost, Ksh0.00.';
