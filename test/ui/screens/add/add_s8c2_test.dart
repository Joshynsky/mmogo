// 0.1.2 S8c-2: the name-only ask (NO4), remembered answers, the remembered
// recipients chooser, the Withdrawal fee hint (AD2/WD8b) and the fee-differs
// soft note (CB11). Invented data only. A fake database stands in for sqlite
// (see fake_add_db.dart); the memory is the REAL RecipientMemory on mocked
// SharedPreferences except where a test needs to record call order.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/name_only_resolver.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

const _nameOnlySms =
    'TXA3B4C5D6 Confirmed. Ksh100.00 sent to Jane  Sample on 8/10/26 at 5:25 PM. New M-PESA balance is Ksh3,950.00. '
    'Transaction cost, Ksh0.00.';
const _withdrawalSms =
    'ABC1D2E3F4 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh2,000.00 from 1234567 - SAMPLE AGENT NAME  '
    'New M-PESA balance is Ksh4,100.00. Transaction cost, Ksh29.00. Amount you can transact within the day is 498,000.00.';
const _withdrawalOddFeeSms =
    'ABC1D2E3F5 Confirmed.on 8/10/26 at 9:15 AMWithdraw Ksh2,000.00 from 1234567 - SAMPLE AGENT NAME  '
    'New M-PESA balance is Ksh4,100.00. Transaction cost, Ksh35.00. Amount you can transact within the day is 498,000.00.';

const _janeKey = 'JANE SAMPLE';
const _pochi = 'POCHI_LA_BIASHARA';

/// Records every call and when it happened relative to the insert.
class _RecMemory extends RecipientMemory {
  _RecMemory({this.rule, this.db, this.result = RememberResult.saved, this.lookupThrows = false, this.rememberThrows = false});

  final RecipientRule? rule;
  final FakeAddDb? db;
  final RememberResult result;
  final bool lookupThrows;
  final bool rememberThrows;
  final lookups = <String>[];
  final remembered = <(String, SmsSourceType, bool)>[];
  final insertsAtRemember = <int>[];

  @override
  Future<RecipientRule?> lookup(String key) async {
    lookups.add(key);
    if (lookupThrows) throw StateError('lookup failed');
    return rule;
  }

  @override
  Future<RememberResult> remember(String key, SmsSourceType type, {required bool recordDetailsOn}) async {
    remembered.add((key, type, recordDetailsOn));
    insertsAtRemember.add(db?.insertedTransactions.length ?? -1);
    if (rememberThrows) throw StateError('write failed');
    return result;
  }

  @override
  Future<List<RecipientEntry>> list() async => const [];
}

/// A database whose insert fails.
class _FailingDb extends FakeAddDb {
  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    if (table == 'transactions') throw StateError('insert failed');
    return super.insert(table, values, nullColumnHack: nullColumnHack, conflictAlgorithm: conflictAlgorithm);
  }
}

String _text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
Finder _pills() => find.byKey(const Key('addTypePills'));
Finder _pillOpen(String name) => find.descendant(of: _pills(), matching: find.text(name));

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pump();
  await tester.tap(find.byKey(Key(key)));
  await settle(tester);
}

Future<void> _saveWithChip(WidgetTester tester, int chip) async {
  await _tap(tester, 'addCategoryChip_$chip');
  await reviewAndConfirm(tester);
}

Future<void> _dismissWithBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NO4 name-only ask', () {
    testWidgets('a name-only message with a memory miss fills the type-free fields, closes the paste sheet and opens the ask',
        (tester) async {
      final mem = _RecMemory();
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      expect(mem.lookups, [_janeKey]);
      expect(find.byKey(const Key('addPasteTextField')), findsNothing, reason: 'the ask opens AFTER the paste sheet closes');
      expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
      expect(find.text('Is Jane Sample on Pochi or Send Money?'), findsOneWidget);
      expect(find.text('This message has a name but no phone number, so we can’t tell. Choose one.'), findsOneWidget);
      // Behind the ask the form already holds the type-free fields.
      expect(find.byKey(const Key('addFilledStrip')), findsOneWidget);
      expect(_text(tester, 'addAmountField'), '100.00');
      expect(_text(tester, 'addCodeField'), 'TXA3B4C5D6');
    });

    testWidgets('choosing Pochi fills as Pochi: the name is the label, the marker says Chosen', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      expect(find.byKey(const Key('addAskSheet')), findsNothing);
      expect(_pillOpen('Pochi'), findsOneWidget);
      expect(find.text('Chosen · Pochi'), findsOneWidget);
      expect(_text(tester, 'addReceiverNameField'), 'Jane Sample');
      expect(find.byKey(const Key('addSendMoneyNameNote')), findsNothing);
      await _saveWithChip(tester, 110);
      final row = db.insertedTransactions.single;
      expect(row['source_type'], _pochi);
      expect(row['counterparty_label'], 'Jane Sample');
      expect(row['counterparty_phone'], isNull);
      expect(row['raw_parse_source'], 'SMS_PARSE');
    });

    testWidgets('choosing Send Money prefills the name, shows the note, and needs a phone or the tick off', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskSendMoney');
      expect(_pillOpen('Send Money'), findsOneWidget);
      expect(_text(tester, 'addReceiverNameField'), 'Jane Sample');
      expect(
        find.text('Send Money keeps a name only with a phone number. Add the phone below, or untick '
            '“Also record the receiver’s name & phone” and this saves as Unnamed.'),
        findsOneWidget,
      );
      await _tap(tester, 'addCategoryChip_101');
      expect(reviewEnabled(tester), isFalse, reason: 'switch on, no phone');
      // Untick the switch: the name is dropped and it saves as Unnamed.
      await _tap(tester, 'addCaptureCheckbox');
      expect(reviewEnabled(tester), isTrue);
      await reviewAndConfirm(tester);
      final row = db.insertedTransactions.single;
      expect(row['source_type'], 'SEND_MONEY');
      expect(row['counterparty_label'], isNull);
      expect(row['counterparty_phone'], isNull);
    });

    testWidgets('with a phone typed, Send Money keeps name and phone', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskSendMoney');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0712345678');
      await settle(tester);
      await _saveWithChip(tester, 101);
      final row = db.insertedTransactions.single;
      expect(row['counterparty_label'], 'Jane Sample');
      expect(row['counterparty_phone'], '0712345678');
    });

    for (final how in ['Back', 'scrim', 'Esc', 'swipe down']) {
      testWidgets('closing the ask by $how: type-free fields stay, the line and Choose stay, Review is off, nothing picked',
          (tester) async {
        final mem = _RecMemory();
        await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: mem);
        await pasteSms(tester, _nameOnlySms);
        switch (how) {
          case 'Back':
            await _dismissWithBack(tester);
          case 'scrim':
            await tester.tapAt(const Offset(180, 40));
            await settle(tester);
          case 'Esc':
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await settle(tester);
          default:
            await tester.fling(find.byKey(const Key('addAskSheet')), const Offset(0, 600), 1500);
            await settle(tester);
        }
        expect(find.byKey(const Key('addAskSheet')), findsNothing);
        // Still on Add (Back closed only the ask).
        expect(find.byKey(const Key('addFilledStrip')), findsOneWidget);
        expect(find.byKey(const Key('addAskAwait')), findsOneWidget);
        expect(find.text('Choose Pochi or Send Money.'), findsWidgets);
        expect(_text(tester, 'addAmountField'), '100.00');
        expect(_text(tester, 'addCodeField'), 'TXA3B4C5D6');
        // Receiver and Category stay hidden, Review is off, no pill is open.
        expect(find.byKey(const Key('addCaptureCheckbox')), findsNothing);
        expect(find.byKey(const Key('addCategoryChip_101')), findsNothing);
        expect(reviewEnabled(tester), isFalse);
        for (final n in ['Send Money', 'Pochi', 'Paybill', 'Buy Goods', 'Withdrawal', 'Airtime']) {
          expect(_pillOpen(n), findsNothing, reason: n);
        }
        // The pills are inert.
        await tester.ensureVisible(find.byKey(const Key('addTypePill_BUY_GOODS')));
        await tester.tap(find.byKey(const Key('addTypePill_BUY_GOODS')));
        await settle(tester);
        expect(_pillOpen('Buy Goods'), findsNothing);
        expect(mem.remembered, isEmpty);
        // Choose reopens the ask; choosing then works.
        await _tap(tester, 'addAskChooseButton');
        expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
        await _tap(tester, 'addAskPochi');
        expect(_pillOpen('Pochi'), findsOneWidget);
        expect(find.byKey(const Key('addAskAwait')), findsNothing);
      });
    }

    testWidgets('a lookup error counts as a miss: the ask opens', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: _RecMemory(lookupThrows: true));
      await pasteSms(tester, _nameOnlySms);
      expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
    });

    testWidgets('Start over clears the ask state; a new parse clears it too', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _dismissWithBack(tester);
      expect(find.byKey(const Key('addAskAwait')), findsOneWidget);
      await _tap(tester, 'addStartOverButton');
      expect(find.byKey(const Key('addAskAwait')), findsNothing);
      expect(find.byKey(const Key('addFilledStrip')), findsNothing);
      expect(_pillOpen('Send Money'), findsOneWidget);
      // Choose, then paste something else: the marker is gone.
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      expect(find.byKey(const Key('addAskMarker')), findsOneWidget);
      await _tap(tester, 'addStartOverButton');
      await pasteSms(tester, sendMoneySms);
      expect(find.byKey(const Key('addAskMarker')), findsNothing);
      expect(find.byKey(const Key('addAskAwait')), findsNothing);
    });
  });

  group('NO4 remembered answers', () {
    testWidgets('a memory hit fills without asking and is flagged Remembered, changeable', (tester) async {
      final mem = _RecMemory(rule: const RecipientRule(type: SmsSourceType.pochi, at: 5));
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      expect(find.byKey(const Key('addAskSheet')), findsNothing);
      expect(_pillOpen('Pochi'), findsOneWidget);
      expect(find.text('Remembered · Pochi'), findsOneWidget);
      expect(_text(tester, 'addReceiverNameField'), 'Jane Sample');
      // Change reopens the ask with the tick OFF: "Remember this change (off)".
      await _tap(tester, 'addAskChangeButton');
      expect(find.text('Remember this change (off)'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.descendant(of: find.byKey(const Key('addAskTick')), matching: find.byType(Checkbox))).value, isFalse);
      await _tap(tester, 'addAskSendMoney');
      expect(find.text('Chosen · Send Money'), findsOneWidget);
    });

    testWidgets('choosing the same type again closes the ask and writes nothing', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db, rule: const RecipientRule(type: SmsSourceType.pochi, at: 5));
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskChangeButton');
      await _tap(tester, 'addAskPochi');
      expect(find.byKey(const Key('addAskSheet')), findsNothing);
      expect(find.text('Remembered · Pochi'), findsOneWidget, reason: 'unchanged: still the remembered answer');
      await _saveWithChip(tester, 110);
      expect(mem.remembered, isEmpty, reason: 'an unchanged remembered answer writes nothing');
    });

    testWidgets('an override with the tick on replaces the memory after the save', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db, rule: const RecipientRule(type: SmsSourceType.pochi, at: 5));
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskChangeButton');
      await _tap(tester, 'addAskTick'); // off -> on; the sheet stays open
      expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
      expect(find.text('Remember this change (on)'), findsOneWidget);
      await _tap(tester, 'addAskSendMoney');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0712345678');
      await settle(tester);
      await _saveWithChip(tester, 101);
      expect(mem.remembered, [(_janeKey, SmsSourceType.sendMoney, true)]);
    });

    testWidgets('an override with the tick left off writes nothing', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db, rule: const RecipientRule(type: SmsSourceType.pochi, at: 5));
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskChangeButton');
      await _tap(tester, 'addAskSendMoney');
      await tester.enterText(find.byKey(const Key('addReceiverSubField')), '0712345678');
      await settle(tester);
      await _saveWithChip(tester, 101);
      expect(mem.remembered, isEmpty);
    });

    testWidgets('the tick shows only with the switch ON; first answer defaults ON with the signed label', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      expect(find.byKey(const Key('addAskTick')), findsOneWidget);
      expect(find.text('Remember this choice for Jane Sample'), findsOneWidget);
      expect(find.text('The name is kept on this phone only. It is not in backups and not shared.'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.descendant(of: find.byKey(const Key('addAskTick')), matching: find.byType(Checkbox))).value, isTrue);
    });

    testWidgets('with the switch OFF the tick control is absent', (tester) async {
      await pumpAdd(tester, FakeAddDb(), memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      expect(find.byKey(const Key('addAskSheet')), findsOneWidget);
      expect(find.byKey(const Key('addAskTick')), findsNothing);
      expect(find.textContaining('Remember this'), findsNothing);
    });

    testWidgets('the tick state survives a reopen', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskTick'); // on -> off
      await _dismissWithBack(tester);
      await _tap(tester, 'addAskChooseButton');
      expect(tester.widget<Checkbox>(find.descendant(of: find.byKey(const Key('addAskTick')), matching: find.byType(Checkbox))).value, isFalse);
    });

    testWidgets('save, THEN remember (the insert is already there when remember runs), once, with the SMS-name key', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db);
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      // The live Name field is edited after parse: the key still comes from the SMS name.
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'Somebody Else');
      await settle(tester);
      await _tap(tester, 'addCategoryChip_110');
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      expect(mem.remembered, isEmpty, reason: 'nothing before the explicit Confirm');
      await tester.tap(find.byKey(const Key('addReviewConfirmButton')));
      await settle(tester);
      expect(mem.remembered, [(_janeKey, SmsSourceType.pochi, true)]);
      expect(mem.insertsAtRemember, [1], reason: 'the transaction was inserted first');
    });

    testWidgets('cancelling the review writes nothing to memory', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db);
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _tap(tester, 'addCategoryChip_110');
      await tester.tap(find.byKey(const Key('addReviewButton')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('addReviewBackButton')));
      await settle(tester);
      expect(mem.remembered, isEmpty);
      expect(db.insertedTransactions, isEmpty);
    });

    testWidgets('a failed save writes nothing to memory', (tester) async {
      final db = _FailingDb();
      final mem = _RecMemory(db: db);
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(find.byKey(const Key('addReviewError')), findsOneWidget);
      expect(mem.remembered, isEmpty);
    });

    testWidgets('a memory write that throws never fails the save', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db, rememberThrows: true);
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(db.insertedTransactions, hasLength(1));
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('savedDroppedOldest adds a small note to "Saved", never a name; no snackbar or error text holds the name',
        (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db, result: RememberResult.savedDroppedOldest);
      await pumpAdd(tester, db, captureReceiver: true, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(find.text('Saved. The oldest remembered name was removed to make room.'), findsOneWidget);
      final snack = find.byType(SnackBar);
      expect(snack, findsOneWidget);
      expect(find.descendant(of: snack, matching: find.textContaining('Jane')), findsNothing);
      expect(find.descendant(of: snack, matching: find.textContaining('JANE')), findsNothing);
    });

    testWidgets('while undecided, no error text and no review hint carries the name', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: _RecMemory());
      await pasteSms(tester, _nameOnlySms);
      await _dismissWithBack(tester);
      expect(find.byKey(const Key('addReviewHint')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('addReviewHint'))).data, 'Choose Pochi or Send Money.');
      expect(find.textContaining('Jane'), findsNothing, reason: 'the name appears only in the ask, tick label and chooser');
    });
  });

  group('SECURITY F1 acceptance (real prefs)', () {
    Future<String?> stored() async => (await SharedPreferences.getInstance()).getString(RecipientMemory.prefsKey);

    testWidgets('switch OFF: the key is absent after a save (starting from empty prefs)', (tester) async {
      await pumpAdd(tester, FakeAddDb(), memory: RecipientMemory());
      expect(await stored(), isNull);
      await pasteSms(tester, _nameOnlySms);
      expect(find.byKey(const Key('addAskTick')), findsNothing);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(await stored(), isNull);
      expect((await SharedPreferences.getInstance()).containsKey(RecipientMemory.prefsKey), isFalse);
    });

    testWidgets('switch ON and tick ON: the key holds exactly {"t","at"} for the name', (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db, captureReceiver: true, memory: RecipientMemory());
      expect(await stored(), isNull);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      final raw = await stored();
      expect(raw, isNotNull);
      final map = jsonDecode(raw!) as Map<String, dynamic>;
      expect(map.keys, [_janeKey]);
      final entry = map[_janeKey] as Map<String, dynamic>;
      expect(entry.keys.toSet(), {'t', 'at'});
      expect(entry['t'], _pochi);
      expect(entry['at'], isA<int>());
    });

    testWidgets('switch ON, tick OFF: the key is absent', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: RecipientMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskTick');
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(await stored(), isNull);
    });

    testWidgets('the switch is read at SAVE time: ticked at choose, switched off before the save: nothing stored', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: RecipientMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi'); // tick is ON
      await _tap(tester, 'addCaptureCheckbox'); // switch OFF
      await _saveWithChip(tester, 110);
      expect(await stored(), isNull);
    });

    testWidgets('switch OFF: remember() is not even called (screen rule, recording memory)', (tester) async {
      final db = FakeAddDb();
      final mem = _RecMemory(db: db);
      await pumpAdd(tester, db, memory: mem);
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      expect(db.insertedTransactions, hasLength(1));
      expect(mem.remembered, isEmpty);
    });

    testWidgets('a stored answer round-trips: the next message of the same name needs no question', (tester) async {
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: RecipientMemory());
      await pasteSms(tester, _nameOnlySms);
      await _tap(tester, 'addAskPochi');
      await _saveWithChip(tester, 110);
      // A fresh memory object over the same prefs finds it.
      expect((await RecipientMemory().lookup(_janeKey))?.type, SmsSourceType.pochi);
    });
  });

  group('NO4 remembered recipients chooser', () {
    Future<RecipientMemory> seeded(WidgetTester tester, {int extra = 0}) async {
      var t = 100;
      final mem = RecipientMemory(nowMs: () => t++);
      await pumpAdd(tester, FakeAddDb(), captureReceiver: true, memory: mem);
      await mem.remember('JACKLINE DEMO', SmsSourceType.pochi, recordDetailsOn: true);
      await mem.remember('TOM SAMPLE', SmsSourceType.sendMoney, recordDetailsOn: true);
      for (var i = 0; i < extra; i++) {
        await mem.remember('JAMES NUMBER $i', SmsSourceType.sendMoney, recordDetailsOn: true);
      }
      return mem;
    }

    testWidgets('typing in the Send Money Name field lists matches (name and type only); a tap fills the name and switches the pill',
        (tester) async {
      await seeded(tester);
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'ja');
      await settle(tester);
      expect(find.byKey(const Key('addChooserItem_0')), findsOneWidget);
      expect(find.byKey(const Key('addChooserItem_1')), findsNothing, reason: 'TOM SAMPLE does not contain "ja"');
      expect(find.descendant(of: find.byKey(const Key('addChooserItem_0')), matching: find.text('JACKLINE DEMO')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('addChooserItem_0')), matching: find.text('Pochi')), findsOneWidget);
      await _tap(tester, 'addChooserItem_0');
      expect(_text(tester, 'addReceiverNameField'), 'JACKLINE DEMO');
      expect(_pillOpen('Pochi'), findsOneWidget);
      expect(find.text('Type changed to Pochi, because JACKLINE DEMO is remembered as Pochi.'), findsOneWidget);
      // Typing again clears the plain line.
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'JACKLINE DEMO x');
      await settle(tester);
      expect(find.byKey(const Key('addChooserNote')), findsNothing);
    });

    testWidgets('a chooser tap never writes to memory', (tester) async {
      final mem = await seeded(tester);
      final before = (await mem.list()).map((e) => (e.key, e.rule.at)).toList();
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'tom');
      await settle(tester);
      await _tap(tester, 'addChooserItem_0');
      final after = (await mem.list()).map((e) => (e.key, e.rule.at)).toList();
      expect(after, before);
    });

    testWidgets('an exact name + same type match is hidden; at most 4 entries show', (tester) async {
      await seeded(tester, extra: 6);
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'james');
      await settle(tester);
      expect(find.byKey(const Key('addChooserItem_3')), findsOneWidget);
      expect(find.byKey(const Key('addChooserItem_4')), findsNothing);
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'tom sample');
      await settle(tester);
      expect(find.byKey(const Key('addChooserItem_0')), findsNothing, reason: 'Send Money is the current type: exact match hidden');
    });

    testWidgets('not in the Buy Goods Shop field', (tester) async {
      await seeded(tester);
      await _tap(tester, 'addTypePill_BUY_GOODS');
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'ja');
      await settle(tester);
      expect(find.byKey(const Key('addChooserItem_0')), findsNothing);
    });

    testWidgets('not on a parsed form', (tester) async {
      await seeded(tester);
      await pasteSms(tester, sendMoneySms);
      await tester.enterText(find.byKey(const Key('addReceiverNameField')), 'ja');
      await settle(tester);
      expect(find.byKey(const Key('addChooserItem_0')), findsNothing);
    });

    testWidgets('not when the receiver-details switch is off (the Name field is not there)', (tester) async {
      await seeded(tester);
      await _tap(tester, 'addCaptureCheckbox');
      expect(find.byKey(const Key('addReceiverNameField')), findsNothing);
      expect(find.byKey(const Key('addChooserItem_0')), findsNothing);
    });
  });

  group('AD2 fee hint and CB11 soft note', () {
    Future<void> withdrawalWith(WidgetTester tester, String amount, {String? fee}) async {
      await pumpAdd(tester, FakeAddDb());
      await _tap(tester, 'addTypePill_AGENT_WITHDRAWAL');
      await tester.enterText(find.byKey(const Key('addAmountField')), amount);
      if (fee != null) await tester.enterText(find.byKey(const Key('addFeeField')), fee);
      await settle(tester);
    }

    const line2000 = 'Safaricom’s usual fee for Ksh 2,000. Tap to use it.';

    testWidgets('empty Fee on Withdrawal: the muted line and the pill show; the Fee field is NEVER prefilled', (tester) async {
      await withdrawalWith(tester, '2000');
      expect(find.text(line2000), findsOneWidget);
      expect(find.text('Usual fee Ksh 29'), findsOneWidget);
      expect(_text(tester, 'addFeeField'), isEmpty);
      expect(find.byKey(const Key('addFeeDiffersNote')), findsNothing);
      final pill = tester.getSize(find.byKey(const Key('addFeeHintPill')));
      expect(pill.height, greaterThanOrEqualTo(44));
    });

    testWidgets('tapping the line fills 29.00, editable, and the hint goes', (tester) async {
      await withdrawalWith(tester, '2000');
      await _tap(tester, 'addFeeHintLine');
      expect(_text(tester, 'addFeeField'), '29.00');
      expect(find.text(line2000), findsNothing);
      await tester.enterText(find.byKey(const Key('addFeeField')), '30');
      await settle(tester);
      expect(_text(tester, 'addFeeField'), '30', reason: 'no lock');
    });

    testWidgets('tapping the pill fills the same', (tester) async {
      await withdrawalWith(tester, '2000');
      await _tap(tester, 'addFeeHintPill');
      expect(_text(tester, 'addFeeField'), '29.00');
      expect(_text(tester, 'addAmountField'), '2,000', reason: 'nothing else changes');
    });

    testWidgets('screen readers hear the line once, with the fee in the label; the pill is excluded', (tester) async {
      final handle = tester.ensureSemantics();
      await withdrawalWith(tester, '2000');
      expect(find.bySemanticsLabel('Safaricom’s usual fee for Ksh 2,000 is Ksh 29. Tap to use it.'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Usual fee')), findsNothing);
      handle.dispose();
    });

    for (final amount in ['2000.50', '49', '250001']) {
      testWidgets('no hint for amount $amount (not whole shillings, or out of range)', (tester) async {
        await withdrawalWith(tester, amount);
        expect(find.byKey(const Key('addFeeHintRow')), findsNothing);
        expect(find.byKey(const Key('addFeeDiffersNote')), findsNothing);
      });
    }

    testWidgets('no hint on any other type', (tester) async {
      await pumpAdd(tester, FakeAddDb());
      await tester.enterText(find.byKey(const Key('addAmountField')), '2000');
      await settle(tester);
      expect(find.byKey(const Key('addFeeHintRow')), findsNothing);
      await _tap(tester, 'addTypePill_BUY_GOODS');
      expect(find.byKey(const Key('addFeeHintRow')), findsNothing);
    });

    testWidgets('a fee that differs shows the exact note with the as-of date; it is not a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await withdrawalWith(tester, '2000', fee: '30');
      const note = 'Safaricom’s usual fee for Ksh 2,000 is Ksh 29 (as of 04-08-2026). Check your message.';
      expect(find.text(note), findsOneWidget);
      expect(find.byKey(const Key('addFeeHintRow')), findsNothing, reason: 'the hint is only while Fee is empty');
      final node = tester.getSemantics(find.byKey(const Key('addFeeDiffersNote')));
      expect(node.flagsCollection.isLiveRegion, isFalse);
      handle.dispose();
    });

    testWidgets('a typed 0 against a usual 29 shows the note; the usual fee shows none', (tester) async {
      await withdrawalWith(tester, '2000', fee: '0');
      expect(find.byKey(const Key('addFeeDiffersNote')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('addFeeField')), '29');
      await settle(tester);
      expect(find.byKey(const Key('addFeeDiffersNote')), findsNothing);
    });

    testWidgets('the note recomputes when the amount changes', (tester) async {
      await withdrawalWith(tester, '2000', fee: '29');
      expect(find.byKey(const Key('addFeeDiffersNote')), findsNothing);
      await tester.enterText(find.byKey(const Key('addAmountField')), '3000');
      await settle(tester);
      expect(find.text('Safaricom’s usual fee for Ksh 3,000 is Ksh 52 (as of 04-08-2026). Check your message.'), findsOneWidget);
    });

    testWidgets('a parsed fee equal to the usual one shows no note; a parsed odd fee shows it, is never rewritten, never blocks the save',
        (tester) async {
      final db = FakeAddDb();
      await pumpAdd(tester, db);
      await pasteSms(tester, _withdrawalSms);
      expect(_text(tester, 'addFeeField'), '29.00');
      expect(find.byKey(const Key('addFeeDiffersNote')), findsNothing);
      await _tap(tester, 'addStartOverButton');
      await pasteSms(tester, _withdrawalOddFeeSms);
      expect(_text(tester, 'addFeeField'), '35.00', reason: 'never rewritten');
      expect(find.byKey(const Key('addFeeDiffersNote')), findsOneWidget);
      expect(reviewEnabled(tester), isTrue, reason: 'never blocks');
      await reviewAndConfirm(tester);
      expect(db.insertedTransactions.single['transaction_cost_cents'], 3500);
    });

    testWidgets('the hint sits directly under the Fee field, before anything else in the card', (tester) async {
      await withdrawalWith(tester, '2000');
      final fee = tester.getBottomLeft(find.byKey(const Key('addFeeField'))).dy;
      final hint = tester.getTopLeft(find.byKey(const Key('addFeeHintRow'))).dy;
      expect(hint, greaterThan(fee));
      expect(hint - fee, lessThan(40));
    });
  });
}
