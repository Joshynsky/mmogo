// S11b CB5 cross-check, rewritten for the full-screen What's-new page (A5a): the
// page at 360 x 640, 1.3, light and dark: Got it is pinned (found without
// scrolling the page, on screen, hit-testable, 44 px, not overlapping), and the
// banner link and the two route buttons are reached and are 44 px. Two states:
// the page as it opens (first row open) and every row open. The page's own tests
// are in test/ui/whats_new/whats_new_pager_test.dart (A5a); this only runs the
// same states through the shared matrix helper. Plus B3: item 1 never breaks
// inside "M-Pesa" (written with the non-breaking hyphen).
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';

import '../../support/a11y_matrix.dart';

Finder _k(String key) => find.byKey(Key(key));

Widget _host() => Builder(
  builder: (context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('openPager'),
        onPressed: () => showWhatsNewPager(context, onOpenSettings: () {}, onOpenBackup: () {}, onOpenSite: () {}),
        child: const Text('HOME'),
      ),
    ),
  ),
);

const _rows = ['withdrawals', 'weeks', 'phone', 'backups', 'notifications', 'privacy'];

void main() {
  tearDownAll(printA11yLog);

  a11ySubject(
    'What\'s new page, as it opens (first row open)',
    before: () async => WhatsNewProcess.resetForTest(),
    home: _host,
    open: (t) async {
      await t.tap(_k('openPager'));
      await a11ySettle(t);
    },
    actions: () => [
      A11yAction('Got it', _k('whatsNewGotIt')),
      if (!kAutoReadCompiled) A11yAction('Open the mmogo page', _k('whatsNewBannerLink')),
    ],
  );

  a11ySubject(
    'What\'s new page, every row open',
    before: () async => WhatsNewProcess.resetForTest(),
    home: _host,
    open: (t) async {
      await t.tap(_k('openPager'));
      await a11ySettle(t);
      for (final id in _rows) {
        if (_k('whatsNewItemBody-$id').evaluate().isNotEmpty) continue;
        await t.ensureVisible(_k('whatsNewItemHead-$id'));
        await a11ySettle(t);
        await t.tap(_k('whatsNewItemHead-$id'));
        await a11ySettle(t);
      }
    },
    actions: () => [
      A11yAction('Got it', _k('whatsNewGotIt')),
      A11yAction('Change in Settings', _k('whatsNewCalSettings')),
      A11yAction('Open Backup and restore', _k('whatsNewOpenBackup')),
      if (!kAutoReadCompiled) A11yAction('Open the mmogo page', _k('whatsNewBannerLink')),
    ],
  );

  testWidgets('B3: item 1 at 360 px and 1.3 never breaks inside M-Pesa (non-breaking hyphen)', (t) async {
    addTearDown(t.view.reset);
    WhatsNewProcess.resetForTest();
    await pumpA11y(t, _host(), variant: kA11yVariants[1]);
    await t.tap(_k('openPager'));
    await a11ySettle(t);
    if (_k('whatsNewPara-withdrawals-0').evaluate().isEmpty) {
      await t.ensureVisible(_k('whatsNewItemHead-withdrawals'));
      await a11ySettle(t);
      await t.tap(_k('whatsNewItemHead-withdrawals'));
      await a11ySettle(t);
    }
    final body = t.widget<Text>(_k('whatsNewPara-withdrawals-0')).data!;
    expect(body, contains('M\u2011Pesa'));
    expect(body.contains('M-Pesa'), isFalse);
    final i = body.indexOf('M\u2011Pesa');
    final paragraph = t.renderObject<RenderParagraph>(_k('whatsNewPara-withdrawals-0'));
    final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 'M\u2011Pesa'.length));
    expect({for (final b in boxes) b.top.round()}.length, 1, reason: 'the word is on one line: $boxes');
    expect(kWhatsNewCard1Body.contains('M\u2011Pesa'), isTrue);
    expect(kWhatsNewBannerBody.contains('M\u2011Pesa'), isTrue);
  });
}
