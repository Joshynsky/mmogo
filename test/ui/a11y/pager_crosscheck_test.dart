// S11b CB5 cross-check: the What's new pager, card 1 to card 5, at 360 x 640,
// 1.3, light and dark: its buttons are pinned (found without scrolling the page,
// on screen, hit-testable, 44 px, not overlapping). The pager's own tests are in
// test/ui/whats_new/whats_new_pager_test.dart (S11a); this only runs the same
// states through the shared matrix helper. Plus B3: the first card never breaks
// inside "M-Pesa" (written with the non-breaking hyphen).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';

import '../../support/a11y_matrix.dart';

Finder _k(String key) => find.byKey(Key(key));

Widget _host() => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('openPager'),
        onPressed: () => showWhatsNewPager(context, onOpenSettings: () {}, onOpenBackup: () {}),
        child: const Text('HOME'),
      ),
    ),
  ),
);

void main() {
  tearDownAll(printA11yLog);

  for (var card = 1; card <= 5; card++) {
    a11ySubject(
      'What\'s new pager, card $card',
      before: () async => WhatsNewProcess.resetForTest(),
      home: _host,
      open: (t) async {
        await t.tap(_k('openPager'));
        await a11ySettle(t);
        for (var i = 1; i < card; i++) {
          await t.tap(_k('whatsNewNext'));
          await a11ySettle(t);
        }
      },
      actions: () => [
        if (card > 1) A11yAction('Back', _k('whatsNewBack')),
        A11yAction(card == 5 ? 'Got it' : 'Next', _k(card == 5 ? 'whatsNewGotIt' : 'whatsNewNext')),
      ],
    );
  }

  testWidgets('B3: card 1 at 360 px and 1.3 never breaks inside M-Pesa (non-breaking hyphen)', (t) async {
    addTearDown(t.view.reset);
    WhatsNewProcess.resetForTest();
    await pumpA11y(t, _host(), variant: kA11yVariants[1]);
    await t.tap(_k('openPager'));
    await a11ySettle(t);
    final body = t.widget<Text>(_k('whatsNewCardBody')).data!;
    expect(body, contains('M\u2011Pesa'));
    expect(body.contains('M-Pesa'), isFalse);
    final i = body.indexOf('M\u2011Pesa');
    final paragraph = t.renderObject<RenderParagraph>(_k('whatsNewCardBody'));
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 'M\u2011Pesa'.length));
    expect({for (final b in boxes) b.top.round()}.length, 1, reason: 'the word is on one line: $boxes');
    expect(kWhatsNewCard1Body.contains('M\u2011Pesa'), isTrue);
  });
}
