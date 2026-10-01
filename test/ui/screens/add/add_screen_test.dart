// Widget tests for the T27 Add rework (lib/ui/screens/add/*.dart), driven
// through the real AddScreen against test/support/fake_add_db.dart's
// FakeAddDb (see that file's own header for why a real sqflite_common_ffi
// Database isn't used here). Covers the behaviors that had to
// survive the Add rework: save, the duplicate-code check,
// auto_apply ("Always use"), and opt-in/opt-out identity capture — plus the
// paste-parse flow and the M-Pesa/Cash switch that are new to this layout.
//
// AddScreen now pops itself on a successful save ("return to the shell with
// a 'Saved' confirmation") rather than resetting and staying, so every test
// pushes it over a root page instead of using it as MaterialApp's `home`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/ui/screens/add/add_screen.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_add_db.dart';

/// [captureReceiver] mirrors the remembered "Also record the receiver…" box.
/// Its real default is ON, and while it is on Review & save also waits for
/// BOTH halves of the name/phone pair (the T6 paired-optionality CHECK), so
/// tests that aren't about receiver capture start with it OFF.
Future<void> _pumpAdd(WidgetTester tester, FakeAddDb db, {bool captureReceiver = false}) async {
  SharedPreferences.setMockInitialValues({
    'tour_seen_$addTourId': true, // the first-run tour scrim would cover the Type pills
    if (!captureReceiver) AppPrefs.keyCaptureIdentityPreference: false,
  });
  // Phone width, tall enough that the whole form (down to the category chips)
  // is on screen — the default 800x600 surface leaves the chips off-screen.
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

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

const _sendMoneySms = 'THA7K2P9QX Confirmed. Ksh1500.00 sent to JOHN KAMAU 0798630424 on 25/9/26 at '
    '11:25 AM. New M-PESA balance is Ksh3210.00. Transaction cost, Ksh22.00.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('gating + save (M-Pesa)', () {
    testWidgets('Review & save is disabled until amount, code and category are set, with a matching hint',
        (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db);

      expect(tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed, isNull);
      expect(find.text('Add an amount, the 10-character code and a category.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await _settle(tester);
      expect(find.text('Add a category.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed, isNotNull);
    });

    group('the hint names what "Also record the receiver…" still needs', () {
      const untick = 'or untick “Also record the receiver’s name & phone”';

      Future<void> fillBasics(WidgetTester tester) async {
        await tester.enterText(find.byKey(const Key('addAmountField')), '500');
        await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
        await tester.tap(find.byKey(const Key('addCategoryChip_101')));
        await _settle(tester);
      }

      bool reviewEnabled(WidgetTester tester) =>
          tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed != null;

      String hint(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('addReviewHint'))).data!;

      testWidgets('Send Money, nothing entered: name and phone', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await fillBasics(tester);
        expect(reviewEnabled(tester), isFalse);
        expect(hint(tester), 'Add the receiver’s name and phone, $untick.');
      });

      testWidgets('Send Money, name but no phone: just the phone (the case that used to be blank)', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await fillBasics(tester);
        await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'alice wambui');
        await _settle(tester);
        expect(reviewEnabled(tester), isFalse);
        expect(hint(tester), 'Add the receiver’s phone, $untick.');
      });

      testWidgets('Send Money, phone but no name: just the name', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await fillBasics(tester);
        await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0711000001');
        await _settle(tester);
        expect(hint(tester), 'Add the receiver’s name, $untick.');
      });

      testWidgets('both filled: enabled, no hint', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await fillBasics(tester);
        await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'alice wambui');
        await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0711000001');
        await _settle(tester);
        expect(reviewEnabled(tester), isTrue);
        expect(find.byKey(const Key('addReviewHint')), findsNothing);
      });

      testWidgets('joins with the other missing items', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await tester.enterText(find.byKey(const Key('addAmountField')), '500');
        await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'alice wambui');
        await _settle(tester);
        expect(
          hint(tester),
          'Add the 10-character code, a category and the receiver’s phone, $untick.',
        );
      });

      testWidgets('Paybill asks for the business and account instead', (tester) async {
        await _pumpAdd(tester, FakeAddDb(), captureReceiver: true);
        await tester.tap(find.byKey(const Key('addTypePill_PAYBILL')));
        await _settle(tester);
        await tester.enterText(find.byKey(const Key('addAmountField')), '500');
        await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
        await tester.tap(find.byKey(const Key('addCategoryChip_105'))); // Paybill's own category
        await _settle(tester);
        expect(hint(tester), 'Add the business name and account number, $untick.');
      });

      testWidgets('box unticked: no receiver words in the hint', (tester) async {
        await _pumpAdd(tester, FakeAddDb());
        await tester.enterText(find.byKey(const Key('addAmountField')), '500');
        await _settle(tester);
        expect(hint(tester), 'Add the 10-character code and a category.');
      });
    });

    testWidgets('a duplicate M-Pesa code shows inline and blocks Review & save', (tester) async {
      final db = FakeAddDb()
        ..transactions.add({'id': 1, 'display_code': 'ABCD123456', 'source_type': 'SEND_MONEY', 'deleted_at': null});
      await _pumpAdd(tester, db);

      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);

      expect(find.byKey(const Key('addCodeDuplicateError')), findsOneWidget);
      expect(find.text('That code is already recorded.'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed, isNull);
    });

    testWidgets('save writes the real transaction row, pops Add, and shows "Saved"', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db);

      await tester.enterText(find.byKey(const Key('addAmountField')), '1500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'thd7k2p9qx');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('addReviewButton')));
      await _settle(tester);
      expect(find.byKey(const Key('addReviewSheet')), findsOneWidget);
      expect(find.text('Ksh 1,500.00'), findsWidgets);

      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await _settle(tester);

      expect(find.text('root'), findsOneWidget); // Add popped away
      expect(find.text('Saved'), findsOneWidget); // via appMessengerKey

      expect(db.insertedTransactions, hasLength(1));
      final row = db.insertedTransactions.single;
      expect(row['display_code'], 'THD7K2P9QX');
      expect(row['source_type'], 'SEND_MONEY');
      expect(row['amount_cents'], 150000);
      expect(row['classification_id'], 101);
      expect(row['raw_parse_source'], 'MANUAL');
      // Receiver capture is off here (see _pumpAdd) -> NULL.
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
      expect(db.upsertCalls, isEmpty); // empty counterparty key -> no write
    });
  });

  group('receiver capture (T15/T6-D3)', () {
    testWidgets('opted in: the typed name/phone are saved and the counterparty is remembered', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db, captureReceiver: true);

      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('addReviewButton')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await _settle(tester);

      final row = db.insertedTransactions.single;
      expect(row['counterparty_label'], 'John Kamau');
      expect(row['counterparty_phone'], '0798630424');
      expect(db.upsertCalls.single, {'source_type': 'SEND_MONEY', 'counterparty_key': '0798630424', 'classification_id': 101});
    });

    testWidgets('opted out: fields hidden, nothing is saved even if typed before unticking', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db, captureReceiver: true);

      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await tester.tap(find.byKey(const Key('addCaptureCheckbox')));
      await _settle(tester);
      expect(find.byKey(const Key('addReceiverNameField')), findsNothing);

      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await _settle(tester);
      expect(find.text('Not recorded (private)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await _settle(tester);

      final row = db.insertedTransactions.single;
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
      expect(db.upsertCalls, isEmpty);
    });
  });

  group('category suggestion + "Always use" (T12/T18)', () {
    testWidgets('a known counterparty is suggested, pre-selected and marked "usual"; ticking Always use calls setAutoApply',
        (tester) async {
      final db = FakeAddDb()
        ..counterpartyMap.add({
          'source_type': 'SEND_MONEY',
          'counterparty_key': '0798630424',
          'classification_id': 101,
          'auto_apply': 0,
          'updated_at': 0,
        });
      await _pumpAdd(tester, db, captureReceiver: true);

      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'John Kamau');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0798630424');
      await _settle(tester);

      expect(find.textContaining('usual'), findsOneWidget);
      // Pre-selected: Review & save only still needs the amount + code.
      await tester.enterText(find.byKey(const Key('addAmountField')), '500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await _settle(tester);
      expect(tester.widget<FilledButton>(find.byKey(const Key('addReviewButton'))).onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('addAlwaysUseCheckbox')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await _settle(tester);
      expect(find.textContaining('always for them'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await _settle(tester);

      expect(db.autoApplyCalls.single, {'source_type': 'SEND_MONEY', 'counterparty_key': '0798630424'});
    });

    testWidgets('"+ New" creates a classification through the real DAO and selects it', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db);

      await tester.tap(find.byKey(const Key('addCategoryNewButton')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('addCategoryNewField')), 'Barber');
      await tester.tap(find.byKey(const Key('addCategoryNewAddButton')));
      await _settle(tester);

      expect(db.classifications.any((c) => c['name'] == 'Barber' && c['group_id'] == 1), isTrue);
      final newId = db.classifications.firstWhere((c) => c['name'] == 'Barber')['id'];
      expect(find.byKey(Key('addCategoryChip_$newId')), findsOneWidget);
    });

    testWidgets('switching the Type pill clears the chosen category', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db);
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addTypePill_PAYBILL')));
      await _settle(tester);
      expect(find.byKey(const Key('addCategoryChip_101')), findsNothing); // Send Money's own group list
      expect(find.textContaining('a category'), findsWidgets);
    });
  });

  group('large phone font', () {
    testWidgets('row labels stay on one line and the value fields stay usable (Paybill, 1.6x)', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db, captureReceiver: true);
      tester.platformDispatcher.textScaleFactorTestValue = 1.6;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.tap(find.byKey(const Key('addTypePill_PAYBILL')));
      await _settle(tester);

      // A one-line label is about as tall as "Fee"'s.
      final oneLine = tester.getSize(find.text('Fee')).height;
      for (final label in ['Business', 'Account', 'Code', 'When']) {
        expect(tester.getSize(find.text(label)).height, lessThan(oneLine * 1.5), reason: '"$label" broke onto two lines');
      }
      // The typed-into fields still have room.
      expect(tester.getSize(find.byKey(const Key('addReceiverNameField'))).width, greaterThan(100));
      expect(tester.getSize(find.byKey(const Key('addReceiverSubField'))).width, greaterThan(100));
    });
  });

  group('paste-first parse', () {
    testWidgets('a successful parse fills the form and hides the paste card + Type pills; Start over reverts', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db, captureReceiver: true);

      await tester.tap(find.byKey(const Key('addPasteButton')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('addPasteTextField')), _sendMoneySms);
      await tester.tap(find.byKey(const Key('addPasteSubmitButton')));
      await _settle(tester);

      expect(find.byKey(const Key('addFilledStrip')), findsOneWidget);
      expect(find.byKey(const Key('addPasteButton')), findsNothing);
      expect(find.byKey(const Key('addTypePill_SEND_MONEY')), findsNothing);
      expect(tester.widget<TextField>(find.byKey(const Key('addCodeField'))).controller!.text, 'THA7K2P9QX');
      expect(tester.widget<TextField>(find.byKey(const Key('addAmountField'))).controller!.text, '1500.00');
      expect(tester.widget<TextField>(find.byKey(const Key('addReceiverNameField'))).controller!.text, 'JOHN KAMAU');

      await tester.tap(find.byKey(const Key('addStartOverButton')));
      await _settle(tester);
      expect(find.byKey(const Key('addPasteButton')), findsOneWidget);
      expect(find.byKey(const Key('addTypePill_SEND_MONEY')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('addCodeField'))).controller!.text, isEmpty);
    });

    testWidgets('an unparseable paste shows an inline error, not a dialog', (tester) async {
      final db = FakeAddDb();
      await _pumpAdd(tester, db);

      await tester.tap(find.byKey(const Key('addPasteButton')));
      await _settle(tester);
      await tester.enterText(find.byKey(const Key('addPasteTextField')), 'not an sms at all');
      await tester.tap(find.byKey(const Key('addPasteSubmitButton')));
      await _settle(tester);

      expect(find.byKey(const Key('addPasteError')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byKey(const Key('addPasteTextField')), findsOneWidget); // sheet stayed open

      // Editing the text clears the stale error.
      await tester.enterText(find.byKey(const Key('addPasteTextField')), _sendMoneySms);
      await _settle(tester);
      expect(find.byKey(const Key('addPasteError')), findsNothing);
    });
  });

  group('Cash', () {
    testWidgets('shows only amount, When and category chips, and saves a CASH row', (tester) async {
      final db = FakeAddDb();
      // Capture ON (the real default): Cash must not wait for a receiver pair.
      await _pumpAdd(tester, db, captureReceiver: true);

      await tester.tap(find.byKey(const Key('addSrcSeg_CASH')));
      await _settle(tester);

      expect(find.byKey(const Key('addCodeField')), findsNothing);
      expect(find.byKey(const Key('addFeeField')), findsNothing);
      expect(find.byKey(const Key('addCaptureCheckbox')), findsNothing);
      expect(find.byKey(const Key('addCashWhenText')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('addAmountField')), '250');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await _settle(tester);

      final row = db.insertedTransactions.single;
      expect(row['source_type'], 'CASH');
      expect(row['transaction_cost_cents'], isNull);
      expect(row['counterparty_label'], isNull);
      expect(row['raw_parse_source'], 'MANUAL');
      expect((row['display_code'] as String).startsWith('CASH-'), isTrue);
    });
  });
}
