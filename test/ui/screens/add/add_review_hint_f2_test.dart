// F2 (R29, R39): the line under "Review & save" is ONE line that names only what is still
// missing ("Still needed: amount, code, category."), built from the form's real rules
// (AddDraft), and the line keeps its height when empty so the button never moves.
// Invented data only; FakeAddDb, no real database.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/add/add_draft.dart';

import '../../../support/add_harness.dart';
import '../../../support/fake_add_db.dart';

AddDraft _draft({
  String src = 'MPESA',
  String type = 'SEND_MONEY',
  bool on = true,
  bool amount = true,
  bool code = true,
  bool category = true,
  String name = '',
  String sub = '',
  String fee = '',
}) => AddDraft(
  src: src,
  type: type,
  captureIdentity: on,
  amountText: amount ? '500' : '',
  feeText: fee,
  codeText: code ? 'ABCD123456' : '',
  nameText: name,
  subText: sub,
  codeDuplicate: false,
  classificationId: category ? 101 : null,
);

const _types = ['SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL', 'AIRTIME'];

void main() {
  group('the words, from the real rules (AddDraft.reviewHint)', () {
    // Every combination of the three always-needed parts, in the signed order.
    for (final amount in [true, false]) {
      for (final code in [true, false]) {
        for (final category in [true, false]) {
          final want = [if (!amount) 'amount', if (!code) 'code', if (!category) 'category'];
          test('M-Pesa, switch off: amount=$amount code=$code category=$category', () {
            final h = _draft(on: false, amount: amount, code: code, category: category).reviewHint;
            expect(h, want.isEmpty ? '' : 'Still needed: ${want.join(', ')}.');
          });
          test('Cash has no code: amount=$amount code=$code category=$category', () {
            final h = _draft(src: 'CASH', amount: amount, code: code, category: category).reviewHint;
            final w = [if (!amount) 'amount', if (!category) 'category'];
            expect(h, w.isEmpty ? '' : 'Still needed: ${w.join(', ')}.');
          });
        }
      }
    }

    test('Send Money, switch on: name and phone, then just the one that is empty', () {
      expect(_draft().reviewHint, 'Still needed: name and phone.');
      expect(_draft(name: 'Jane Sample').reviewHint, 'Still needed: phone.');
      expect(_draft(sub: '0711000001').reviewHint, 'Still needed: name.');
      expect(_draft(name: 'Jane Sample', sub: '0711000001').reviewHint, '');
    });

    test('Paybill, switch on: business and account, then just the one that is empty', () {
      expect(_draft(type: 'PAYBILL').reviewHint, 'Still needed: business and account.');
      expect(_draft(type: 'PAYBILL', name: 'Sample Water').reviewHint, 'Still needed: account.');
      expect(_draft(type: 'PAYBILL', sub: '12345').reviewHint, 'Still needed: business.');
      expect(_draft(type: 'PAYBILL', name: 'Sample Water', sub: '12345').reviewHint, '');
    });

    test('the receiver part comes after amount, code and category', () {
      expect(
        _draft(amount: false, code: false, category: false).reviewHint,
        'Still needed: amount, code, category, name and phone.',
      );
      expect(_draft(type: 'PAYBILL', code: false).reviewHint, 'Still needed: code, business and account.');
    });

    test('switch off: no receiver words for any type', () {
      for (final t in _types) {
        final h = _draft(type: t, on: false, amount: false, fee: t == 'AGENT_WITHDRAWAL' ? '5' : '').reviewHint;
        expect(h, 'Still needed: amount.', reason: t);
      }
    });

    test('Buy Goods, Pochi and Withdrawal receivers are optional in the real rules, so never named', () {
      for (final t in ['BUY_GOODS', 'POCHI_LA_BIASHARA', 'AGENT_WITHDRAWAL']) {
        final d = _draft(type: t, fee: t == 'AGENT_WITHDRAWAL' ? '5' : '');
        expect(d.canReview, isTrue, reason: '$t: switch on, receiver empty still reviews');
        expect(d.reviewHint, '', reason: t);
      }
    });

    test('the Withdrawal fee is the last word', () {
      expect(_draft(type: 'AGENT_WITHDRAWAL').reviewHint, 'Still needed: fee.');
      expect(_draft(type: 'AGENT_WITHDRAWAL', amount: false).reviewHint, 'Still needed: amount, fee.');
    });

    test('the hint is empty exactly when the form can be reviewed (never out of step with the button)', () {
      for (final t in _types) {
        for (final on in [true, false]) {
          for (final amount in [true, false]) {
            for (final name in ['', 'x']) {
              for (final sub in ['', '1']) {
                final d = _draft(type: t, on: on, amount: amount, name: name, sub: sub, fee: t == 'AGENT_WITHDRAWAL' ? '5' : '');
                expect(d.reviewHint.isEmpty, d.canReview, reason: '$t on=$on amount=$amount name="$name" sub="$sub"');
              }
            }
          }
        }
      }
    });
  });

  group('the bar keeps its height, so Review & save never moves', () {
    Rect button(WidgetTester t) => t.getRect(find.byKey(const Key('addReviewButton')));

    // The test font (Ahem) is about twice as wide as the real one, so the page is made wide enough
    // here for the longest everyday hint to fit one line, as it does on a real 360 dp phone.
    Future<void> wide(WidgetTester t) async {
      t.view.physicalSize = const Size(2400, 4800);
      await t.pumpAndSettle();
    }

    testWidgets('one-line hints and the empty line all leave the button where it is', (t) async {
      await pumpAdd(t, FakeAddDb(), captureReceiver: false);
      await wide(t);
      final start = button(t);
      expect(t.widget<Text>(find.byKey(const Key('addReviewHint'))).data, 'Still needed: amount, code, category.');
      final lineHeight = t.getSize(find.byKey(const Key('addReviewHint'))).height;

      await t.enterText(find.byKey(const Key('addAmountField')), '500');
      await settle(t);
      expect(t.widget<Text>(find.byKey(const Key('addReviewHint'))).data, 'Still needed: code, category.');
      expect(t.getSize(find.byKey(const Key('addReviewHint'))).height, lineHeight);
      expect(button(t), start);

      await t.enterText(find.byKey(const Key('addCodeField')), 'abcd123456');
      await t.tap(find.byKey(const Key('addCategoryChip_101')));
      await settle(t);
      expect(reviewEnabled(t), isTrue);
      expect(find.byKey(const Key('addReviewHint')), findsNothing, reason: 'the words are gone ...');
      expect(find.byKey(const Key('addReviewHintSlot')), findsOneWidget, reason: '... the line is still reserved');
      expect(t.getSize(find.byKey(const Key('addReviewHintSlot'))).height, lineHeight, reason: 'one line of height');
      expect(button(t), start, reason: 'the button did not move');
    });

    testWidgets('receiver switch on: the longest everyday hint is one line and the button stays put', (t) async {
      await pumpAdd(t, FakeAddDb(), captureReceiver: true);
      await wide(t);
      expect(
        t.widget<Text>(find.byKey(const Key('addReviewHint'))).data,
        'Still needed: amount, code, category, name and phone.',
      );
      final start = button(t);
      final lineHeight = t.getSize(find.byKey(const Key('addReviewHint'))).height;
      await t.enterText(find.byKey(const Key('addReceiverNameField')), 'alice wambui');
      await settle(t);
      expect(t.getSize(find.byKey(const Key('addReviewHint'))).height, lineHeight);
      expect(button(t), start);
      await t.enterText(find.byKey(const Key('addReceiverSubField')), '0711000001');
      await settle(t);
      expect(button(t), start);
    });
  });
}
