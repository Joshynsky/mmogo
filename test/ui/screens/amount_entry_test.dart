// QA fix F5: amount entry on the Add screen and the Analytics edit sheet takes
// only a valid shape (digits, one '.', two decimals) and shows a plain message
// instead of saving 0 cents or throwing on pasted Infinity / NaN / exponents.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mymog/data/prefs/app_prefs.dart';
import 'package:mymog/ui/screens/add/add_screen.dart';
import 'package:mymog/ui/screens/analytics_screen.dart';
import 'package:mymog/ui/shell/app_messenger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_add_db.dart';
import '../../support/fake_analytics_db.dart';

Future<void> _pumpAdd(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'tour_seen_$addTourId': true,
    AppPrefs.keyCaptureIdentityPreference: false,
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
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddScreen(db: FakeAddDb()))),
            child: const Text('root'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('root'));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Add screen amount field', () {
    testWidgets('a third decimal is refused, so 0.004 can never become 0 cents', (tester) async {
      await _pumpAdd(tester);
      await tester.enterText(find.byKey(const Key('addAmountField')), '0.00');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('addAmountField')), '0.004');
      await tester.pump();
      expect(_text(tester, 'addAmountField'), '0.00');
      // 0.00 is not an amount: a plain message, no exception.
      expect(find.text('Enter an amount from 0.01 to 10,000,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Infinity, NaN, exponents and negatives are refused without an exception', (tester) async {
      await _pumpAdd(tester);
      for (final bad in ['Infinity', 'NaN', '1e30', '1e5', '-5']) {
        await tester.enterText(find.byKey(const Key('addAmountField')), bad);
        await tester.pump();
        expect(_text(tester, 'addAmountField'), '', reason: bad);
        expect(tester.takeException(), isNull, reason: bad);
      }
    });

    testWidgets('an amount above the cap shows the message', (tester) async {
      await _pumpAdd(tester);
      await tester.enterText(find.byKey(const Key('addAmountField')), '20000000');
      await tester.pump();
      expect(find.text('Enter an amount from 0.01 to 10,000,000.00'), findsOneWidget);
    });

    testWidgets('a valid amount shows no message; the fee field takes the same shape', (tester) async {
      await _pumpAdd(tester);
      await tester.enterText(find.byKey(const Key('addAmountField')), '1500.50');
      await tester.enterText(find.byKey(const Key('addFeeField')), '22.505');
      await tester.pump();
      expect(_text(tester, 'addAmountField'), '1500.50');
      expect(_text(tester, 'addFeeField'), '', reason: 'a 3-decimal fee is refused');
      expect(find.text('Enter an amount from 0.01 to 10,000,000.00'), findsNothing);
    });
  });

  group('Analytics edit sheet amount and cost', () {
    Future<FakeAnalyticsDb> pumpEdit(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final db = FakeAnalyticsDb(analyticsSampleRows());
      await tester.pumpWidget(MaterialApp(home: AnalyticsScreen(db: db, clock: () => analyticsTestNow)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('JOHN KAMAU'));
      await tester.pumpAndSettle();
      return db;
    }

    bool saveEnabled(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('editSaveButton'))).onPressed != null;

    testWidgets('0.004 and Infinity are refused, Save stays disabled on 0.00, no exception', (tester) async {
      await pumpEdit(tester);
      await tester.enterText(find.byKey(const Key('editAmountField')), '0.00');
      await tester.pump();
      await tester.enterText(find.byKey(const Key('editAmountField')), '0.004');
      await tester.pump();
      expect(_text(tester, 'editAmountField'), '0.00');
      expect(saveEnabled(tester), isFalse);
      expect(find.text('Enter an amount from 0.01 to 10,000,000.00'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('editAmountField')), 'Infinity');
      await tester.pump();
      expect(_text(tester, 'editAmountField'), '0.00');
      await tester.enterText(find.byKey(const Key('editCostField')), '1e5');
      await tester.pump();
      expect(_text(tester, 'editCostField'), isNot('1e5'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a valid amount still saves to integer cents', (tester) async {
      final db = await pumpEdit(tester);
      await tester.enterText(find.byKey(const Key('editAmountField')), '2000.55');
      await tester.pump();
      await tester.tap(find.byKey(const Key('editSaveButton')));
      await tester.pumpAndSettle();
      expect(db.byId(1)['amount_cents'], 200055);
    });
  });
}
