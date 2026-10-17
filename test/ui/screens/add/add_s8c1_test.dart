// 0.1.2 S8c-1: the Add flow for the six M-Pesa types (AD1, WD8a, WD9, AI2).
// Pills and locking, a parsed message per type, Withdrawal (fee mandatory,
// agent number digits only, saves agent_number and the agent name as label),
// Airtime (no Fee field, fee 0 or the parsed fee, locked category), the signed
// copy strings, TOOLONG reachable, "+ New" only where the mock has it, the
// thousands separators. Invented data only. The database CHECKs are proved on a
// real in-memory sqlite in test/data/add_draft_insert_test.dart (a real
// Database hangs inside testWidgets here, see fake_add_db.dart).
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';
import 'package:mmogo/ui/screens/add/type_pills.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

const _withdrawalSms =
    'ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh2,000.00 from 1234567 - SAMPLE AGENT NAME  '
    'New M-PESA balance is Ksh4,100.00. Transaction cost, Ksh29.00. Amount you can transact within the day is 498,000.00.';
const _airtimeSms =
    'PT8N4W7Q2K confirmed.You bought Ksh200.00 of airtime on 31/10/25 at 2:01 PM.New M-PESA balance is Ksh77,777.77. '
    'Transaction cost, Ksh3.00.';
const _airtimeNoFeeLineSms =
    'HJ8K9L0M1N Confirmed. You bought Ksh100.00 of airtime on 12/10/26 at 7:45 AM. New M-PESA balance is Ksh650.00.';
const _buyGoodsSms =
    'ASD1F2G3H4 Confirmed. Ksh350.00 paid to SAMPLE SHOP. on 8/10/26 at 1:05 PM. New M-PESA balance is Ksh900.00. '
    'Transaction cost, Ksh0.00.';
const _nameOnlySms =
    'TXA3B4C5D6 Confirmed. Ksh100.00 sent to Jane  Sample on 8/10/26 at 5:25 PM. New M-PESA balance is Ksh3,950.00. '
    'Transaction cost, Ksh0.00.';
const _longBase =
    'QWE1R2T3Y4 Confirmed. Ksh500.00 sent to JANE DOE 0712345678 on 8/10/26 at 9:15 AM. New M-PESA balance is Ksh1,000.00. '
    'Transaction cost, Ksh7.00.';

String _padTo(int length) => '$_longBase ${'x' * (length - _longBase.length - 1)}';

String _text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

Future<void> _tapPill(WidgetTester tester, String type) async {
  // The test font (Ahem) is wider than the app's real font, so the row can
  // scroll sideways here: bring the pill into view first (the app's fallback).
  await tester.ensureVisible(find.byKey(Key('addTypePill_$type')));
  await tester.pump();
  await tester.tap(find.byKey(Key('addTypePill_$type')));
  await settle(tester);
}

/// Amount + code typed by hand (the category of W/A is pre-selected).
Future<void> _amountAndCode(WidgetTester tester, {String amount = '2000', String code = 'ABCD123456'}) async {
  await tester.enterText(find.byKey(const Key('addAmountField')), amount);
  await tester.enterText(find.byKey(const Key('addCodeField')), code);
  await settle(tester);
}

Future<void> _openPasteSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('addPasteButton')));
  await settle(tester);
}

Future<void> _submitPaste(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('addPasteTextField')), text);
  await tester.tap(find.byKey(const Key('addPasteSubmitButton')));
  await settle(tester);
}

bool _hasReviewRow(WidgetTester tester, String label) {
  final sheet = find.byKey(const Key('addReviewSheet'));
  return find.descendant(of: sheet, matching: find.text(label)).evaluate().isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AD1 six type pills', () {
    testWidgets('all six pills are there in the mock order; the selected one shows its NAME, the rest the code',
        (tester) async {
      await pumpAdd(tester, FakeAddDb());
      final types = [for (final o in TypePills.options) o.$1];
      expect(types, ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME']);
      for (final t in types) {
        expect(find.byKey(Key('addTypePill_$t')), findsOneWidget, reason: t);
      }
      // Send Money is selected: its name shows; the others show only the code.
      final pills = find.byKey(const Key('addTypePills'));
      expect(find.descendant(of: pills, matching: find.text('Send Money')), findsOneWidget);
      for (final code in ['PB', 'BG', 'P', 'W', 'A']) {
        expect(find.descendant(of: pills, matching: find.text(code)), findsOneWidget, reason: code);
      }
      expect(find.descendant(of: pills, matching: find.text('SM')), findsNothing, reason: 'name only (deviation C)');
      // Tapping Withdrawal opens its name and closes Send Money's.
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      expect(find.descendant(of: pills, matching: find.text('Withdrawal')), findsOneWidget);
      expect(find.descendant(of: pills, matching: find.text('Send Money')), findsNothing);
      expect(find.descendant(of: pills, matching: find.text('SM')), findsOneWidget);
    });

    testWidgets('each pill is a 44 dp tap target with the FULL name as semantic label and tooltip', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAdd(tester, FakeAddDb());
      for (final o in TypePills.options) {
        final size = tester.getSize(find.byKey(Key('addTypePill_${o.$1}')));
        expect(size.height, greaterThanOrEqualTo(44), reason: o.$2);
        expect(size.width, greaterThanOrEqualTo(44), reason: o.$2);
        expect(find.bySemanticsLabel(o.$2), findsOneWidget, reason: o.$2);
        expect(find.byTooltip(o.$2), findsOneWidget, reason: o.$2);
      }
      handle.dispose();
    });

    testWidgets('after a parse the six pills stay, the parsed one is open and the others ignore taps; the divider goes',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      expect(find.text('or enter it yourself'), findsOneWidget);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _withdrawalSms);

      for (final o in TypePills.options) {
        expect(find.byKey(Key('addTypePill_${o.$1}')), findsOneWidget, reason: o.$2);
      }
      expect(find.text('or enter it yourself'), findsNothing);
      final pills = find.byKey(const Key('addTypePills'));
      expect(find.descendant(of: pills, matching: find.text('Withdrawal')), findsOneWidget);
      // Locked: a tap on Airtime changes nothing; the Fee field is still there.
      await _tapPill(tester, 'AIRTIME');
      expect(find.descendant(of: pills, matching: find.text('Withdrawal')), findsOneWidget);
      expect(find.byKey(const Key('addFeeField')), findsOneWidget);
      expect(find.byKey(const Key('addNoFeeLine')), findsNothing);
      // Screen readers hear the others as disabled.
      final airtime = tester.getSemantics(find.bySemanticsLabel('Airtime'));
      expect(airtime.flagsCollection.isEnabled, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('TypePills: a locked row ignores taps, an open row reports them', (tester) async {
      final taps = <String>[];
      Future<void> pump(bool locked) => tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: TypePills(type: 'PAYBILL', locked: locked, onChanged: taps.add),
            ),
          ));
      await pump(true);
      await tester.tap(find.byKey(const Key('addTypePill_BUY_GOODS')));
      await tester.pump();
      expect(taps, isEmpty);
      await pump(false);
      await tester.tap(find.byKey(const Key('addTypePill_BUY_GOODS')));
      await tester.pump();
      expect(taps, ['BUY_GOODS']);
    });

    testWidgets('Start over clears the fields, unlocks the pills and puts the type back on Send Money', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _withdrawalSms);
      expect(_text(tester, 'addAmountField'), '2,000.00');

      await tester.tap(find.byKey(const Key('addStartOverButton')));
      await settle(tester);
      final pills = find.byKey(const Key('addTypePills'));
      expect(find.descendant(of: pills, matching: find.text('Send Money')), findsOneWidget);
      expect(find.descendant(of: pills, matching: find.text('Withdrawal')), findsNothing);
      expect(_text(tester, 'addAmountField'), isEmpty);
      expect(_text(tester, 'addCodeField'), isEmpty);
      expect(find.text('or enter it yourself'), findsOneWidget);
      // Unlocked: Airtime can be chosen again.
      await _tapPill(tester, 'AIRTIME');
      expect(find.descendant(of: pills, matching: find.text('Airtime')), findsOneWidget);
    });

    testWidgets('the Cash | M-Pesa switch stays and shows no pills on Cash', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      expect(find.byKey(const Key('addSrcSeg_MPESA')), findsOneWidget);
      await tester.tap(find.byKey(const Key('addSrcSeg_CASH')));
      await settle(tester);
      expect(find.byKey(const Key('addTypePills')), findsNothing);
    });
  });

  group('a parsed message per type fills the right fields and shows in the review', () {
    testWidgets('Send Money', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, sendMoneySms);
      expect(_text(tester, 'addCodeField'), 'THA7K2P9QX');
      expect(_text(tester, 'addFeeField'), '22.00');
      expect(_text(tester, 'addReceiverNameField'), 'JOHN KAMAU');
      expect(_text(tester, 'addReceiverSubField'), '0798630424');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(find.text('Send Money'), findsWidgets);
      expect(_hasReviewRow(tester, 'To'), isTrue);
      expect(_hasReviewRow(tester, 'Fee'), isTrue);
      expect(find.text('JOHN KAMAU · 0798630424'), findsOneWidget);
    });

    testWidgets('Paybill', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, paybillSms);
      expect(_text(tester, 'addReceiverNameField'), 'KPLC PREPAID');
      expect(_text(tester, 'addReceiverSubField'), '12345678');
      await tester.tap(find.byKey(const Key('addCategoryChip_105')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Business'), isTrue);
    });

    testWidgets('Buy Goods', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _buyGoodsSms);
      expect(_text(tester, 'addReceiverNameField'), 'SAMPLE SHOP');
      await tester.tap(find.byKey(const Key('addCategoryChip_109')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Shop'), isTrue);
      expect(find.text('SAMPLE SHOP'), findsWidgets);
    });

    testWidgets('Withdrawal: amount, fee, agent name and number fill in; the category is the locked built-in; review shows the agent',
        (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _withdrawalSms);
      expect(_text(tester, 'addAmountField'), '2,000.00');
      expect(_text(tester, 'addCodeField'), 'ABC1D2E3F4');
      expect(_text(tester, 'addFeeField'), '29.00');
      expect(_text(tester, 'addReceiverNameField'), 'SAMPLE AGENT NAME');
      expect(_text(tester, 'addReceiverSubField'), '1234567');
      expect(find.byKey(const Key('addFixedCategory')), findsOneWidget);
      expect(find.text('Category: Withdrawal'), findsOneWidget);
      expect(reviewEnabled(tester), isTrue, reason: 'the parsed fee satisfies the mandatory-fee rule');

      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Agent'), isTrue);
      expect(find.text('SAMPLE AGENT NAME · 1234567'), findsOneWidget);
      expect(_hasReviewRow(tester, 'Fee'), isTrue);
      expect(find.text('Withdrawal'), findsWidgets);
    });

    testWidgets('Airtime: amount fills, the parsed fee is kept silently, there is no Fee field, no receiver, no chips',
        (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _airtimeSms);
      expect(_text(tester, 'addAmountField'), '200.00');
      expect(_text(tester, 'addCodeField'), 'PT8N4W7Q2K');
      expect(find.byKey(const Key('addFeeField')), findsNothing);
      expect(find.text('No fee for airtime.'), findsOneWidget);
      expect(find.byKey(const Key('addCaptureCheckbox')), findsNothing);
      expect(find.byKey(const Key('addCategoryChip_101')), findsNothing);
      expect(find.text('Category: Airtime'), findsOneWidget);
      expect(reviewEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Fee'), isFalse, reason: 'no Fee row for Airtime');
      expect(_hasReviewRow(tester, 'To'), isFalse);
      expect(_hasReviewRow(tester, 'Receiver'), isFalse);
      expect(_hasReviewRow(tester, 'Category'), isTrue);
    });
  });

  group('WD8a Withdrawal', () {
    testWidgets('a parsed Withdrawal saves agent_number, the agent name as label and the parsed fee', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _withdrawalSms);
      await reviewAndConfirm(tester);
      final row = db.insertedTransactions.single;
      expect(row['source_type'], 'AGENT_WITHDRAWAL');
      expect(row['agent_number'], '1234567');
      expect(row['counterparty_label'], 'SAMPLE AGENT NAME');
      expect(row['counterparty_phone'], isNull);
      expect(row['paybill_account_number'], isNull);
      expect(row['transaction_cost_cents'], 2900);
      expect(row['amount_cents'], 200000);
      expect(row['classification_id'], 120, reason: 'the built-in Withdrawal category (seed_key)');
      expect(row['raw_parse_source'], 'SMS_PARSE');
      expect(db.upsertCalls, isEmpty, reason: 'Withdrawal never learns a receiver');
    });

    testWidgets('hand entry: agent name and number are optional and do NOT gate Review; they are saved', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await _amountAndCode(tester);
      await tester.enterText(find.byKey(const Key('addFeeField')), '29');
      await settle(tester);
      expect(reviewEnabled(tester), isTrue, reason: 'neither agent field is required');
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'Demo Agent');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '765432');
      await settle(tester);
      await reviewAndConfirm(tester);
      final row = db.insertedTransactions.single;
      expect(row['agent_number'], '765432');
      expect(row['counterparty_label'], 'Demo Agent');
      expect(row['transaction_cost_cents'], 2900);
    });

    testWidgets('the Fee is mandatory: empty gives the hint and (once touched) the inline error; a typed 0 is allowed',
        (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await _amountAndCode(tester);
      expect(reviewEnabled(tester), isFalse);
      expect(tester.widget<Text>(find.byKey(const Key('addReviewHint'))).data, 'Still needed: fee.');
      // Not touched yet: no inline error.
      expect(find.byKey(const Key('addFeeError')), findsNothing);

      // Touched (typed, then cleared): the signed text shows.
      await tester.enterText(find.byKey(const Key('addFeeField')), '5');
      await tester.enterText(find.byKey(const Key('addFeeField')), '');
      await settle(tester);
      expect(find.byKey(const Key('addFeeError')), findsOneWidget);
      expect(find.text('Enter the fee. It can be 0 if you were not charged.'), findsOneWidget);
      expect(reviewEnabled(tester), isFalse);

      // A typed 0 is a fee.
      await tester.enterText(find.byKey(const Key('addFeeField')), '0');
      await settle(tester);
      expect(find.byKey(const Key('addFeeError')), findsNothing);
      expect(reviewEnabled(tester), isTrue);
      await reviewAndConfirm(tester);
      expect(db.insertedTransactions.single['transaction_cost_cents'], 0);
    });

    testWidgets('leaving the empty Fee field (blur) shows the error without typing', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await tester.tap(find.byKey(const Key('addFeeField')));
      await tester.pump();
      expect(find.byKey(const Key('addFeeError')), findsNothing, reason: 'focused, not yet left');
      await tester.tap(find.byKey(const Key('addCodeField'))); // focus moves away
      await settle(tester);
      expect(find.text('Enter the fee. It can be 0 if you were not charged.'), findsOneWidget);
    });

    testWidgets('a bad Fee value shows the cost message; the other types treat an empty Fee as 0', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await tester.enterText(find.byKey(const Key('addFeeField')), '20000000');
      await settle(tester);
      expect(find.text('Enter a cost from 0 to 10,000,000.00'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('addReviewHint'))).data, endsWith('fee.'));

      // Send Money: an empty fee is fine and shows no fee error.
      await _tapPill(tester, 'SEND_MONEY');
      await tester.enterText(find.byKey(const Key('addFeeField')), '');
      await settle(tester);
      expect(find.byKey(const Key('addFeeError')), findsNothing);
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await _amountAndCode(tester);
      expect(reviewEnabled(tester), isTrue);
    });

    testWidgets('the agent number takes digits only and at most 20 of them, on a numeric keyboard', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '12ab 34-5');
      await settle(tester);
      expect(_text(tester, 'addReceiverSubField'), '12345');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '1234567890123456789012345');
      await settle(tester);
      expect(_text(tester, 'addReceiverSubField'), hasLength(20));
      final field = tester.widget<TextField>(find.byKey(const Key('addReceiverSubField')));
      expect(field.keyboardType, TextInputType.number);
      // Labels follow the signed copy.
      expect(find.text('Also record the agent’s name & number'), findsOneWidget);
      expect(find.text('Agent name'), findsOneWidget);
      expect(find.text('Agent number'), findsOneWidget);
    });

    testWidgets('tick OFF: nothing about the agent is saved even when parsed; the review says Receiver: Not recorded (private)',
        (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db); // tick off
      await _openPasteSheet(tester);
      await _submitPaste(tester, _withdrawalSms);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Receiver'), isTrue);
      expect(find.text('Not recorded (private)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await settle(tester);
      final row = db.insertedTransactions.single;
      expect(row['agent_number'], isNull);
      expect(row['counterparty_label'], isNull);
    });

    testWidgets('tick ON with both agent fields empty: the review says Agent: Not recorded, and it saves with nulls',
        (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await _amountAndCode(tester);
      await tester.enterText(find.byKey(const Key('addFeeField')), '29');
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(_hasReviewRow(tester, 'Agent'), isTrue);
      expect(find.text('Not recorded'), findsOneWidget);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await settle(tester);
      final row = db.insertedTransactions.single;
      expect(row['agent_number'], isNull);
      expect(row['counterparty_label'], isNull);
    });

    testWidgets('agent_number is cleared when the type changes, and Withdrawal never gets a memory chip', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '765432');
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'Demo Agent');
      await settle(tester);
      await _tapPill(tester, 'SEND_MONEY');
      expect(_text(tester, 'addReceiverSubField'), isEmpty);
      expect(_text(tester, 'addReceiverNameField'), isEmpty);
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      expect(_text(tester, 'addReceiverSubField'), isEmpty);
      expect(find.byKey(const Key('addAlwaysUseCheckbox')), findsNothing);
    });
  });

  group('AI2 Airtime', () {
    testWidgets('hand entry: no Fee field, "No fee for airtime.", no receiver, locked category, saves fee 0 and no label',
        (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await tester.enterText(find.byKey(const Key('addFeeField')), '7'); // typed under Send Money first
      await _tapPill(tester, 'AIRTIME');
      expect(find.byKey(const Key('addFeeField')), findsNothing);
      expect(find.text('No fee for airtime.'), findsOneWidget);
      expect(find.byKey(const Key('addCaptureCheckbox')), findsNothing);
      expect(find.byKey(const Key('addReceiverNameField')), findsNothing);
      expect(find.text('Category: Airtime'), findsOneWidget);
      await _amountAndCode(tester, amount: '50');
      expect(reviewEnabled(tester), isTrue);
      await reviewAndConfirm(tester);
      final row = db.insertedTransactions.single;
      expect(row['source_type'], 'AIRTIME');
      expect(row['transaction_cost_cents'], 0, reason: 'a fee typed for another type is not carried to Airtime');
      expect(row['counterparty_label'], isNull);
      expect(row['agent_number'], isNull);
      expect(row['classification_id'], 121);
    });

    testWidgets('a parsed Airtime fee is kept and saved; no fee line saves 0', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _airtimeSms);
      await reviewAndConfirm(tester);
      expect(db.insertedTransactions.single['transaction_cost_cents'], 300);
      expect(db.insertedTransactions.single['source_type'], 'AIRTIME');
    });

    testWidgets('an Airtime message with no fee line saves fee 0', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await _openPasteSheet(tester);
      await _submitPaste(tester, _airtimeNoFeeLineSms);
      await reviewAndConfirm(tester);
      expect(db.insertedTransactions.single['transaction_cost_cents'], 0);
    });
  });

  group('category control per type', () {
    testWidgets('"+ New" is on Send Money, Paybill, Buy Goods, Pochi and Cash; absent on Withdrawal and Airtime',
        (tester) async {
      await pumpAdd(tester, FakeAddDb());
      for (final t in ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA']) {
        await _tapPill(tester, t);
        expect(find.byKey(const Key('addCategoryNewButton')), findsOneWidget, reason: t);
      }
      await tester.tap(find.byKey(const Key('addSrcSeg_CASH')));
      await settle(tester);
      expect(find.byKey(const Key('addCategoryNewButton')), findsOneWidget, reason: 'Cash');
      await tester.tap(find.byKey(const Key('addSrcSeg_MPESA')));
      await settle(tester);
      for (final t in ['AGENT_WITHDRAWAL', 'AIRTIME']) {
        await _tapPill(tester, t);
        expect(find.byKey(const Key('addCategoryNewButton')), findsNothing, reason: t);
        expect(find.byKey(const Key('addCategoryNewField')), findsNothing, reason: t);
        expect(find.textContaining('Category:'), findsOneWidget, reason: t);
      }
    });

    testWidgets('Withdrawal and Airtime show no category chips and no heading; the category is pre-selected by seed_key',
        (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _tapPill(tester, 'AGENT_WITHDRAWAL');
      expect(find.text('Category'), findsNothing);
      expect(find.byKey(const Key('addCategoryChip_120')), findsNothing);
      expect(find.byKey(const Key('addFixedCategory')), findsOneWidget);
      await _amountAndCode(tester);
      await tester.enterText(find.byKey(const Key('addFeeField')), '29');
      await settle(tester);
      expect(reviewEnabled(tester), isTrue, reason: 'category already chosen');
    });

    testWidgets('Pochi: hand entry saves a POCHI row with the name as label, from its own chips', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true);
      await _tapPill(tester, 'POCHI_LA_BIASHARA');
      expect(find.text('Also record the receiver’s name'), findsOneWidget);
      expect(find.byKey(const Key('addReceiverSubField')), findsNothing, reason: 'Pochi has a name only');
      await _amountAndCode(tester, amount: '300');
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'Jane Sample');
      await tester.tap(find.byKey(const Key('addCategoryChip_110')));
      await settle(tester);
      await reviewAndConfirm(tester);
      final row = db.insertedTransactions.single;
      expect(row['source_type'], 'POCHI_LA_BIASHARA');
      expect(row['counterparty_label'], 'Jane Sample');
      expect(row['counterparty_phone'], isNull);
      expect(row['agent_number'], isNull);
      expect(db.upsertCalls, isEmpty, reason: 'Pochi learns no usual category');
    });

    testWidgets('a category made in Add on a Cash entry goes to the Send Money group', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await tester.tap(find.byKey(const Key('addSrcSeg_CASH')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addCategoryNewButton')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('addCategoryNewField')), 'Church');
      await tester.tap(find.byKey(const Key('addCategoryNewAddButton')));
      await settle(tester);
      final made = db.classifications.where((c) => c['name'] == 'Church' && c['id'] != 110).single;
      expect(made['group_id'], 1);
    });
  });

  group('WD9 copy and paste limits', () {
    test('the signed strings are exactly the mock text', () {
      expect(
        SmsParser.kSmsNoMatchReason,
        'Couldn’t recognize this message. It doesn’t match a Send Money, Paybill, Buy Goods, Pochi, Withdrawal or '
        'Airtime confirmation. Check the pasted text, or choose the type and enter it yourself.',
      );
      expect(kSmsTooLongReason, 'This is too long to be an M-Pesa message (over 2,000 characters).');
      expect(kSmsMaxChars, 2000);
    });

    testWidgets('no match, an empty box and an impossible date all show the NOMATCH box and keep the sheet open',
        (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _openPasteSheet(tester);
      for (final bad in [
        'not an sms at all',
        '',
        'QWE1R2T3Y4 Confirmed. Ksh500.00 sent to JANE DOE 0712345678 on 31/2/26 at 9:15 AM. New M-PESA balance is '
            'Ksh1,000.00. Transaction cost, Ksh7.00.',
      ]) {
        await _submitPaste(tester, bad);
        expect(find.text(SmsParser.kSmsNoMatchReason), findsOneWidget, reason: bad);
        expect(find.byKey(const Key('addPasteError')), findsOneWidget);
        expect(find.byKey(const Key('addPasteTextField')), findsOneWidget, reason: 'the sheet stays open');
        expect(_text(tester, 'addAmountField'), isEmpty);
      }
    });

    testWidgets('2,001 characters: Parse shows the TOOLONG box, keeps the sheet open, fills nothing; the box clears on edit',
        (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _openPasteSheet(tester);
      final long = _padTo(2001);
      expect(long.length, 2001);
      await _submitPaste(tester, long);
      // No maxLength: the whole paste is in the box (otherwise Parse would never see it).
      expect(tester.widget<TextField>(find.byKey(const Key('addPasteTextField'))).controller!.text.length, 2001);
      expect(tester.widget<TextField>(find.byKey(const Key('addPasteTextField'))).maxLength, isNull);
      expect(find.text(kSmsTooLongReason), findsOneWidget);
      expect(find.byKey(const Key('addPasteTextField')), findsOneWidget);
      expect(find.byKey(const Key('addFilledStrip')), findsNothing);

      await tester.enterText(find.byKey(const Key('addPasteTextField')), 'x');
      await settle(tester);
      expect(find.text(kSmsTooLongReason), findsNothing, reason: 'the box clears when the text changes');
    });

    testWidgets('exactly 2,000 characters still parses and fills the form', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true);
      await _openPasteSheet(tester);
      final text = _padTo(2000);
      expect(text.length, 2000);
      await _submitPaste(tester, text);
      expect(find.byKey(const Key('addFilledStrip')), findsOneWidget);
      expect(_text(tester, 'addCodeField'), 'QWE1R2T3Y4');
    });

    testWidgets('ParseNeedsType (a name-only message) closes the paste sheet and opens the S8c-2 ask; no NOMATCH box', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _openPasteSheet(tester);
      await _submitPaste(tester, _nameOnlySms);
      expect(find.text(SmsParser.kSmsNoMatchReason), findsNothing);
      expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
      expect(find.byKey(const Key('addFilledStrip')), findsOneWidget);
      expect(_text(tester, 'addAmountField'), '100.00');
    });
  });

  group('amount shows thousands separators as you type (signed 08-10)', () {
    testWidgets('typing 2000 reads 2,000 and still counts as 2000.00', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await tester.enterText(find.byKey(const Key('addAmountField')), '2000');
      await settle(tester);
      expect(_text(tester, 'addAmountField'), '2,000');
      await tester.enterText(find.byKey(const Key('addAmountField')), '1234567.5');
      await settle(tester);
      expect(_text(tester, 'addAmountField'), '1,234,567.5');
      await tester.enterText(find.byKey(const Key('addAmountField')), '1500');
      await tester.enterText(find.byKey(const Key('addCodeField')), 'ABCD123456');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await settle(tester);
      expect(db.insertedTransactions.single['amount_cents'], 150000);
    });
  });

  group('STAYS (evidence given)', () {
    testWidgets('Android Back closes the review sheet first, then leaves the page', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await _amountAndCode(tester, amount: '500');
      await tester.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(find.byKey(const Key('addReviewSheet')), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const Key('addReviewSheet')), findsNothing);
      expect(find.byKey(const Key('addAmountField')), findsOneWidget, reason: 'still on Add');

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byKey(const Key('addAmountField')), findsNothing, reason: 'now back on the root page');
    });
  });
}
