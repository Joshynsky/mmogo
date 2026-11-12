// 0.2.0 S7: Copy buttons for phone and account in the edit sheet, only while
// "Record receiver details" (capture_identity_preference) is on.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/analytics_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_analytics_db.dart';

Future<void> _open(WidgetTester tester, String rowName) async {
  tester.view.physicalSize = const Size(400, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: AnalyticsScreen(db: FakeAnalyticsDb(analyticsSampleRows()), clock: () => analyticsTestNow)),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(rowName));
  await tester.pumpAndSettle();
}

void main() {
  late List<String> clip;

  setUp(() {
    clip = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') clip.add((call.arguments as Map)['text'] as String);
        return null;
      },
    );
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));

  String phoneText(WidgetTester t) => t.widget<TextField>(find.byKey(const Key('editPhoneField'))).controller!.text;

  testWidgets('switch ON: Copy beside the phone puts the number on the clipboard and says Copied', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_identity_preference': true});
    await _open(tester, 'JOHN KAMAU');
    final phone = phoneText(tester);
    expect(phone, isNotEmpty);
    expect(find.byKey(const Key('copy-phone number')), findsOneWidget);
    await tester.tap(find.byKey(const Key('copy-phone number')));
    await tester.pump();
    expect(clip, [phone]);
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('switch ON: Copy beside the account number (Paybill)', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_identity_preference': true});
    await _open(tester, 'DSTV KENYA');
    final acct = tester.widget<TextField>(find.byKey(const Key('editAccountField'))).controller!.text;
    expect(acct, isNotEmpty);
    await tester.tap(find.byKey(const Key('copy-account number')));
    await tester.pump();
    expect(clip, [acct]);
  });

  testWidgets('switch OFF: no Copy button anywhere in the sheet', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_identity_preference': false});
    await _open(tester, 'JOHN KAMAU');
    expect(find.text('Copy'), findsNothing);
    expect(find.byKey(const Key('copy-phone number')), findsNothing);
    expect(clip, isEmpty);
  });

  testWidgets('an emptied field hides its Copy button; what is copied is what the field shows', (tester) async {
    SharedPreferences.setMockInitialValues({'capture_identity_preference': true});
    await _open(tester, 'JOHN KAMAU');
    await tester.enterText(find.byKey(const Key('editPhoneField')), '0711111111');
    await tester.pump();
    await tester.tap(find.byKey(const Key('copy-phone number')));
    await tester.pump();
    expect(clip, ['0711111111']);
    await tester.enterText(find.byKey(const Key('editPhoneField')), '');
    await tester.pump();
    expect(find.byKey(const Key('copy-phone number')), findsNothing);
  });
}
