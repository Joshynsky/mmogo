// S11b TS2 matrix, part 1: Add (every mode and its sheets). See
// test/support/a11y_matrix.dart for the checks. Fakes only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/add/add_screen.dart';
import 'package:mmogo/ui/screens/add/name_only_ask.dart';

import '../../support/a11y_matrix.dart';
import '../../support/add_harness.dart' show sendMoneySms;
import '../../support/fake_add_db.dart';

Finder _k(String key) => find.byKey(Key(key));

/// Scrolls the control into view first (at 1.3 the page opens scrolled).
Future<void> _tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(_k(key));
  await t.pump();
  await t.tap(_k(key));
  await a11ySettle(t);
}

const _seen = <String, Object>{'tour_seen_add': true};

Future<void> _pill(WidgetTester t, String type) async {
  await t.ensureVisible(_k('addTypePill_$type'));
  await t.tap(_k('addTypePill_$type'));
  await a11ySettle(t);
}

List<A11yAction> _common() => [
  A11yAction('Close', _k('addCloseButton')),
  A11yAction('Help', _k('pageHelpButton')),
  A11yAction('M-Pesa switch', _k('addSrcSeg_MPESA')),
  A11yAction('Cash switch', _k('addSrcSeg_CASH')),
];

void main() {
  tearDownAll(printA11yLog);

  final types = <String, String>{
    'Send Money': 'SEND_MONEY',
    'Paybill': 'PAYBILL',
    'Buy Goods': 'BUY_GOODS',
    'Pochi': 'POCHI_LA_BIASHARA',
    'Withdrawal': 'AGENT_WITHDRAWAL',
    'Airtime': 'AIRTIME',
  };
  for (final e in types.entries) {
    a11ySubject(
      'Add, ${e.key} mode',
      prefs: _seen,
      home: () => AddScreen(db: FakeAddDb()),
      open: e.value == 'SEND_MONEY' ? null : (t) => _pill(t, e.value),
      actions: () => [
        ..._common(),
        A11yAction('Paste a message', _k('addPasteButton')),
        A11yAction('Type pill ${e.value}', _k('addTypePill_${e.value}')),
        A11yAction('Review & save', _k('addReviewButton')),
      ],
    );
  }

  a11ySubject(
    'Add, Cash mode',
    prefs: _seen,
    home: () => AddScreen(db: FakeAddDb()),
    open: (t) async {
      await _tapKey(t, 'addSrcSeg_CASH');
      await a11ySettle(t);
    },
    actions: () => [..._common(), A11yAction('Review & save', _k('addReviewButton'))],
  );

  a11ySubject(
    'Add, paste sheet',
    prefs: _seen,
    home: () => AddScreen(db: FakeAddDb()),
    open: (t) async {
      await _tapKey(t, 'addPasteButton');
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Parse', _k('addPasteSubmitButton')),
      A11yAction('Cancel', _k('addPasteCancelButton')),
    ],
  );

  a11ySubject(
    'Add, after a parse (filled strip, start over)',
    prefs: _seen,
    home: () => AddScreen(db: FakeAddDb()),
    open: (t) async {
      await _tapKey(t, 'addPasteButton');
      await a11ySettle(t);
      await t.enterText(_k('addPasteTextField'), sendMoneySms);
      await _tapKey(t, 'addPasteSubmitButton');
      await a11ySettle(t);
    },
    actions: () => [
      ..._common(),
      A11yAction('Start over', _k('addStartOverButton')),
      A11yAction('Review & save', _k('addReviewButton')),
    ],
  );

  a11ySubject(
    'Add, review sheet',
    prefs: _seen,
    home: () => AddScreen(db: FakeAddDb()),
    open: (t) async {
      await _tapKey(t, 'addPasteButton');
      await a11ySettle(t);
      await t.enterText(_k('addPasteTextField'), sendMoneySms);
      await _tapKey(t, 'addPasteSubmitButton');
      await a11ySettle(t);
      await t.ensureVisible(_k('addReviewButton'));
      await _tapKey(t, 'addCategoryChip_101');
      await _tapKey(t, 'addReviewButton');
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Confirm & save', _k('addReviewConfirmButton')),
      A11yAction('Back to edit', _k('addReviewBackButton')),
    ],
  );

  a11ySubject(
    'Add, name-only ask sheet',
    home: () => Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('openAsk'),
            onPressed: () => showNameOnlyAsk(
              context,
              name: 'JOHN KAMAU',
              current: null,
              showTick: true,
              change: false,
              tick: false,
              onTick: (_) {},
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
    open: (t) async {
      await t.tap(_k('openAsk'));
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Pochi', _k('addAskPochi')),
      A11yAction('Send Money', _k('addAskSendMoney')),
    ],
  );
}
