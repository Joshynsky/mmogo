// 0.1.2 A5a (WN1, PK2, CW2): the full-screen What's-new page. A banner at the
// top, the title, the intro, six expandable rows (first open, several can be
// open), one pinned Got it, the system Back key (closes, marks nothing), the
// two injected route buttons, the banner link, 44 px, dark, text scale 1.3 and
// the row semantics. Stub routes only: the real Settings and Backup pages are
// never built; nothing touches prefs or network.
//
// The standard build (the default) is tested in the main groups. The
// auto-read build is a compile-time flag: its group runs only with
// `--dart-define=MMOGO_AUTOREAD=true` (and is skipped otherwise).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/ui/whats_new_autoread_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/copy/whats_new_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/whats_new/whats_new_cards.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host {
  bool? result;
  final opened = <String>[];
}

const _gotIt = Key('whatsNewGotIt');
const _pager = Key('whatsNewPager');
const _scroll = Key('whatsNewScroll');

Key _head(String id) => Key('whatsNewItemHead-$id');
Key _body(String id) => Key('whatsNewItemBody-$id');
Key _summary(String id) => Key('whatsNewItemSummary-$id');

const _ids = ['withdrawals', 'weeks', 'phone', 'backups', 'notifications', 'privacy'];

Future<_Host> _pump(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1.0,
  Size size = const Size(400, 900),
  bool open = true,
  VoidCallback? onOpenSite,
}) async {
  SharedPreferences.setMockInitialValues({});
  WhatsNewProcess.resetForTest();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final host = _Host();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: dark ? Brightness.dark : Brightness.light,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      routes: {
        '/settings': (_) => Scaffold(appBar: AppBar(title: const Text('SETTINGS STUB'))),
        '/backup': (_) => Scaffold(appBar: AppBar(title: const Text('BACKUP STUB'))),
      },
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('openPager'),
              onPressed: () async {
                host.result = await showWhatsNewPager(
                  context,
                  onOpenSettings: () {
                    host.opened.add('settings');
                    Navigator.of(context).pushNamed('/settings');
                  },
                  onOpenBackup: () {
                    host.opened.add('backup');
                    Navigator.of(context).pushNamed('/backup');
                  },
                  onOpenSite: onOpenSite ?? () => host.opened.add('site'),
                );
              },
              child: const Text('HOME'),
            ),
          ),
        ),
      ),
    ),
  );
  if (open) {
    await tester.tap(find.byKey(const Key('openPager')));
    await tester.pumpAndSettle();
  }
  return host;
}

/// Opens a row (scrolling to it first); a closed row's header is tapped.
Future<void> _toggle(WidgetTester tester, String id) async {
  await tester.ensureVisible(find.byKey(_head(id)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_head(id)));
  await tester.pumpAndSettle();
}

Future<void> _openRow(WidgetTester tester, String id) async {
  if (find.byKey(_body(id)).evaluate().isEmpty) await _toggle(tester, id);
}

String _text(WidgetTester tester, Key k) => tester.widget<Text>(find.byKey(k)).data!;

void main() {
  const standardOnly = kAutoReadCompiled ? 'standard build only' : null;
  const autoreadOnly = kAutoReadCompiled ? null : 'run with --dart-define=MMOGO_AUTOREAD=true';

  group('the page, in the signed order (standard build)', () {
    testWidgets('banner, title, intro and six rows, with the mock\'s words', (tester) async {
      await _pump(tester);
      expect(find.byKey(_pager), findsOneWidget);
      expect(_text(tester, const Key('whatsNewPagerTitle')), "What's new in mmogo 0.1.2");
      expect(_text(tester, const Key('whatsNewIntro')), 'Six things changed. Tap one to read it. Tap Got it when you are done.');
      // The banner is above the title.
      expect(tester.getTopLeft(find.byKey(const Key('whatsNewBanner'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('whatsNewPagerTitle'))).dy));
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the standard version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'There is a second version that can read and parse your M\u2011Pesa messages for you. '
        'It puts them on a waiting list for you to categorize and review. '
        'It asks for SMS permission, so it is separate and optional.',
      );
      expect(find.text('Open the mmogo page'), findsOneWidget);
      final titles = <String>[];
      for (final id in _ids) {
        await tester.ensureVisible(find.byKey(Key('whatsNewItemTitle-$id')));
        titles.add(_text(tester, Key('whatsNewItemTitle-$id')));
      }
      expect(titles, [
        'Withdrawals, airtime and Pochi',
        'Weeks',
        'Same phone number = one person',
        'Backups',
        'Notifications',
        'Privacy',
      ]);
      expect(find.byType(WhatsNewItemView), findsNWidgets(6));
    }, skip: standardOnly != null);

    testWidgets('the standard banner says nothing of auto-read, even in its spoken words', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      final all = [_text(tester, const Key('whatsNewBannerHead')), _text(tester, const Key('whatsNewBannerBody')), kWhatsNewBannerLink, kWhatsNewIntro];
      for (final t in all) {
        expect(t.toLowerCase(), isNot(contains('auto-read')), reason: t);
        expect(t.toLowerCase(), isNot(contains('autoread')), reason: t);
      }
      h.dispose();
    }, skip: standardOnly != null);

    testWidgets('the first row starts open, the others closed; each closed row shows its one-line summary', (tester) async {
      await _pump(tester);
      expect(find.byKey(_body('withdrawals')), findsOneWidget);
      expect(find.byKey(_summary('withdrawals')), findsNothing, reason: 'open: the summary is not repeated');
      for (final id in _ids.skip(1)) {
        expect(find.byKey(_body(id)), findsNothing, reason: id);
        await tester.ensureVisible(find.byKey(_summary(id)));
        expect(find.byKey(_summary(id)), findsOneWidget, reason: id);
      }
      expect(_text(tester, _summary('weeks')), 'A week now runs from the day you choose, Monday unless you change it.');
      expect(_text(tester, _summary('phone')), 'The same number written two ways now counts as one person.');
      expect(_text(tester, _summary('backups')), 'Backups from 0.1.1 still restore.');
      expect(_text(tester, _summary('notifications')), 'The bell now opens Notifications. Updates is now in Settings, under About.');
      expect(_text(tester, _summary('privacy')), 'No permissions except internet, used only to check for updates.');
    }, skip: standardOnly != null);

    testWidgets('a tap opens a row and a second tap closes it; several can be open at once', (tester) async {
      await _pump(tester);
      await _toggle(tester, 'weeks');
      expect(find.byKey(_body('weeks')), findsOneWidget);
      expect(find.byKey(_body('withdrawals')), findsOneWidget, reason: 'the first stays open');
      await _toggle(tester, 'backups');
      expect(find.byKey(_body('backups')), findsOneWidget);
      expect(find.byKey(_body('weeks')), findsOneWidget);
      await _toggle(tester, 'weeks');
      expect(find.byKey(_body('weeks')), findsNothing);
      expect(find.byKey(_summary('weeks')), findsOneWidget);
      await _toggle(tester, 'withdrawals');
      expect(find.byKey(_body('withdrawals')), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('item 1: the placeholder wording (Paid to, not Analytics) and the withdrawal text', (tester) async {
      await _pump(tester);
      final first = _text(tester, const Key('whatsNewPara-withdrawals-0'));
      expect(first, contains('Paid to shows how many payments you made and what they cost.'));
      expect(first, isNot(contains('Analytics')));
      expect(first, contains('M\u2011Pesa'));
      final second = _text(tester, const Key('whatsNewPara-withdrawals-1'));
      expect(second, contains('it adds nothing to what you spent. Its transaction cost is still tracked.'));
      expect(second, endsWith('mmogo tracks spending.'));
    }, skip: standardOnly != null);

    testWidgets('item 2: Weeks text with the regrouped sentence and the Change in Settings button', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'weeks');
      final body = _text(tester, const Key('whatsNewPara-weeks-0'));
      expect(body, kWhatsNewCard2Body);
      expect(body, contains('A week now runs from the day you choose in Settings (Monday unless you change it).'));
      expect(body, contains('Before, a week meant the last 7 days: today and the 6 days before it.'));
      expect(body, contains('Past weekly figures are regrouped to match; nothing saved changes.'));
      expect(find.byKey(const Key('whatsNewCalSettings')), findsOneWidget);
      expect(find.text('Change in Settings'), findsOneWidget);
    }, skip: standardOnly != null);

    testWidgets('item 3: picture, the signed extra paragraph, names both forms, no setting', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'phone');
      final body = _text(tester, const Key('whatsNewPara-phone-0'));
      expect(body, contains('(07 and 01 numbers alike)'));
      expect(body, contains('We have corrected that: they now count as one person on Paid to,'));
      expect(body, isNot(contains('mistake')));
      expect(body, contains('0712 345 678 and +254 712 345 678'));
      expect(body, contains('The numbers saved on your entries do not change.'));
      expect(find.text(kWhatsNewCard3Extra), findsOneWidget);
      expect(
        kWhatsNewCard3Extra,
        'A number written 07... or +254 7... is the same number, so it joins. '
        'The same goes for 01... and +254 1.... '
        'A 07 number and a 01 number are different numbers and stay separate.',
      );
      expect(find.byKey(const Key('whatsNewPicture')), findsOneWidget);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(kWhatsNewPicLabel), findsOneWidget);
      handle.dispose();
      expect(find.byType(Switch), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('item 4: Backups with the 0.1.1 sentence, the D7 constant, W3 and the Open Backup button', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'backups');
      final body = _text(tester, const Key('whatsNewPara-backups-0'));
      expect(body, contains('Backups from 0.1.1 still restore.'));
      expect(body, contains(kBackupNotRestorableByOlder));
      expect(body, contains(kUninstallErasesNotice));
      expect(find.byKey(const Key('whatsNewOpenBackup')), findsOneWidget);
      expect(find.text(kWhatsNewOpenBackup), findsOneWidget);
    }, skip: standardOnly != null);

    testWidgets('R13 (F4): "Change in Settings" and "Open Backup and restore" are real buttons of one style, 44 px high', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      await _openRow(tester, 'weeks');
      await _openRow(tester, 'backups');
      Future<(Size, Color?, TextDecoration?)> look(Key k, String label) async {
        await tester.ensureVisible(find.byKey(k));
        await tester.pumpAndSettle();
        final b = tester.widget<FilledButton>(find.byKey(k));
        final text = tester.widget<Text>(find.descendant(of: find.byKey(k), matching: find.text(label)));
        final sem = tester.getSemantics(find.byKey(k));
        expect(sem.flagsCollection.isButton, isTrue, reason: label);
        expect(sem.label, label);
        return (tester.getSize(find.byKey(k)), b.style?.backgroundColor?.resolve({}), text.style?.decoration);
      }

      final settings = await look(const Key('whatsNewCalSettings'), 'Change in Settings');
      final backup = await look(const Key('whatsNewOpenBackup'), 'Open Backup and restore');
      expect(settings.$1.height, greaterThanOrEqualTo(44));
      expect(backup.$1.height, greaterThanOrEqualTo(44));
      expect(backup.$2, isNotNull);
      expect(backup.$2, settings.$2, reason: 'same fill on both');
      expect(backup.$3, isNull, reason: 'no underline: not a link');
      h.dispose();
    });

    testWidgets('item 5: Notifications says what the bell does and where Updates went; no reading words', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'notifications');
      final body = _text(tester, const Key('whatsNewPara-notifications-0'));
      expect(body, kWhatsNewCardNotificationsBody);
      expect(body, contains('The bell now opens Notifications.'));
      expect(body, contains('now in Settings, under About'));
      for (final w in ['SMS', 'permission', 'read your', 'auto']) {
        expect(body.toLowerCase(), isNot(contains(w.toLowerCase())), reason: w);
      }
    }, skip: standardOnly != null);

    testWidgets('item 6: the signed sentence in bold, then W7\'s second half; sign-off last; no expander', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'privacy');
      expect(_text(tester, const Key('whatsNewPara-privacy-0')), kPrivacySentenceStandard);
      expect(
        _text(tester, const Key('whatsNewPara-privacy-0')),
        'No permissions except internet, used only to check for updates (switchable off).',
      );
      expect(_text(tester, const Key('whatsNewPara-privacy-1')), kNetworkSeenSentence);
      expect(
        _text(tester, const Key('whatsNewPara-privacy-1')),
        'GitHub sees your IP address and that the request comes from the mmogo app. No entries, names or messages are sent.',
      );
      expect(tester.widget<Text>(find.byKey(const Key('whatsNewPara-privacy-0'))).style!.fontWeight, FontWeight.w700);
      await tester.ensureVisible(find.byKey(const Key('whatsNewSignOff')));
      expect(_text(tester, const Key('whatsNewSignOff')), kWhatsNewSignOff);
      expect(kWhatsNewSignOff, '— Josh');
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.textContaining(kIndependenceFull), findsNothing);
    }, skip: standardOnly != null);
  });

  group('the banner link', () {
    testWidgets('"Open the mmogo page" calls the site opener, is a 44 px button, and marks nothing', (tester) async {
      final host = await _pump(tester);
      final size = tester.getSize(find.byKey(const Key('whatsNewBannerLink')));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      await tester.tap(find.byKey(const Key('whatsNewBannerLink')));
      await tester.pumpAndSettle();
      expect(host.opened, ['site']);
      expect(find.byKey(_pager), findsOneWidget);
      expect(host.result, isNull);
    }, skip: standardOnly != null);
  });

  group('closing', () {
    testWidgets('Got it is pinned: on screen at the top of the page and after scrolling to the end', (tester) async {
      await _pump(tester, size: const Size(360, 640), scale: 1.3);
      final before = tester.getRect(find.byKey(_gotIt));
      expect(before.bottom, lessThanOrEqualTo(640));
      await tester.drag(find.byKey(_scroll), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_gotIt)), before);
      expect(find.text('Got it'), findsOneWidget);
    });

    testWidgets('Got it closes the page and returns true to the page it was opened from', (tester) async {
      final host = await _pump(tester);
      await tester.tap(find.byKey(_gotIt));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(host.result, isTrue);
    });

    testWidgets('system Back closes the page and returns false (unseen), at any scroll position', (tester) async {
      final host = await _pump(tester);
      await _toggle(tester, 'weeks');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(host.result, isFalse);
    });

    testWidgets('a second page cannot be opened while one is on screen', (tester) async {
      await _pump(tester);
      final ctx = tester.element(find.byKey(_pager));
      final second = await showWhatsNewPager(ctx, onOpenSettings: () {}, onOpenBackup: () {});
      await tester.pumpAndSettle();
      expect(second, isFalse);
      expect(find.byKey(_pager), findsOneWidget);
    });

    testWidgets('the page is a full-screen route (not a sheet): no sheet shell, its own Scaffold', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('backupSheetScroll')), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      final size = tester.getSize(find.byKey(_pager));
      expect(size, const Size(400, 900));
    });
  });

  group('the two route buttons (injected, pushed over the page)', () {
    testWidgets('Change in Settings opens the stub route; Back returns to the same page and rows; nothing is marked', (tester) async {
      final host = await _pump(tester);
      await _openRow(tester, 'weeks');
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(host.opened, ['settings']);
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.byKey(_body('weeks')), findsOneWidget);
      expect(host.result, isNull);
    }, skip: standardOnly != null);

    testWidgets('Open Backup and restore opens the stub route; Back returns to the open Backups row', (tester) async {
      final host = await _pump(tester);
      await _openRow(tester, 'backups');
      await tester.tap(find.byKey(const Key('whatsNewOpenBackup')));
      await tester.pumpAndSettle();
      expect(host.opened, ['backup']);
      expect(find.text('BACKUP STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_body('backups')), findsOneWidget);
      expect(host.result, isNull);
    }, skip: standardOnly != null);
  });

  group('44 px, dark, text scale 1.3', () {
    testWidgets('every row header is at least 56 high and every button at least 44 x 44', (tester) async {
      await _pump(tester);
      for (final id in _ids) {
        await _openRow(tester, id);
      }
      for (final id in _ids) {
        await tester.ensureVisible(find.byKey(_head(id)));
        expect(tester.getSize(find.byKey(_head(id))).height, greaterThanOrEqualTo(56), reason: id);
      }
      for (final k in [_gotIt, const Key('whatsNewCalSettings'), const Key('whatsNewOpenBackup'), const Key('whatsNewBannerLink')]) {
        final f = find.byKey(k);
        if (f.evaluate().isEmpty) continue;
        await tester.ensureVisible(f);
        final size = tester.getSize(f);
        expect(size.height, greaterThanOrEqualTo(44), reason: '$k height');
        expect(size.width, greaterThanOrEqualTo(44), reason: '$k width');
      }
    });

    testWidgets('dark and 1.3 at 360 x 640: no overflow with every row open; Got it stays pinned on screen', (tester) async {
      await _pump(tester, dark: true, scale: 1.3, size: const Size(360, 640));
      for (final id in _ids) {
        await _openRow(tester, id);
        expect(tester.takeException(), isNull, reason: 'row $id');
      }
      final rect = tester.getRect(find.byKey(_gotIt));
      expect(rect.bottom, lessThanOrEqualTo(640));
      expect(rect.height, greaterThanOrEqualTo(44));
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(_scroll), matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('dark: the row text contrasts with the row surface (4.5:1)', (tester) async {
      await _pump(tester, dark: true);
      await _openRow(tester, 'withdrawals');
      final palette = AppPalette.of(tester.element(find.byKey(_pager)));
      expect(palette.brightness, Brightness.dark);
      double ratio(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      final body = tester.widget<Text>(find.byKey(const Key('whatsNewPara-withdrawals-0'))).style!.color!;
      final title = tester.widget<Text>(find.byKey(const Key('whatsNewItemTitle-withdrawals'))).style!.color!;
      expect(ratio(palette.card, body), greaterThan(4.5));
      expect(ratio(palette.card, title), greaterThan(4.5));
      final bannerInk = tester.widget<Text>(find.byKey(const Key('whatsNewBannerBody'))).style!.color!;
      expect(ratio(palette.tint, bannerInk), greaterThan(4.5));
    });
  });

  group('semantics and focus', () {
    testWidgets('each row header is a button that says whether it is expanded, and follows a tap', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(tester.getSemantics(find.byKey(_head('withdrawals'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
      await tester.ensureVisible(find.byKey(_head('weeks')));
      final closed = tester.getSemantics(find.byKey(_head('weeks')));
      expect(closed.flagsCollection.isButton, isTrue);
      expect(closed.flagsCollection.isExpanded, ui.Tristate.isFalse);
      expect(closed.label, contains('Weeks'));
      expect(closed.label, contains(kWhatsNewCard2Summary));
      await _toggle(tester, 'weeks');
      expect(tester.getSemantics(find.byKey(_head('weeks'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
      handle.dispose();
    }, skip: standardOnly != null);

    testWidgets('the title is a header; focus starts on it', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(tester.getSemantics(find.byKey(const Key('whatsNewPagerTitle'))).flagsCollection.isHeader, isTrue);
      expect(tester.widget<Focus>(find.byKey(const Key('whatsNewTitleFocus'))).focusNode!.hasPrimaryFocus, isTrue);
      handle.dispose();
    });

    testWidgets('the number badge and the chevron are not spoken', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      await tester.ensureVisible(find.byKey(_head('weeks')));
      final label = tester.getSemantics(find.byKey(_head('weeks'))).label;
      expect(label, isNot(contains('2')));
      handle.dispose();
    });

    test('the title is a fixed constant, not the app version', () {
      expect(kWhatsNewPagerVersion, '0.1.2');
    });
  });

  group('the auto-read build (flag on)', () {
    testWidgets('banner, seven items with Auto-read first, its Notifications and its provisional Privacy', (tester) async {
      await _pump(tester);
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the auto-read version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
        'If you do not want SMS permission, the standard version works without it.',
      );
      expect(find.byKey(const Key('whatsNewBannerLink')), findsNothing, reason: 'no link on this banner');
      expect(_text(tester, const Key('whatsNewIntro')), startsWith('Seven things changed.'));
      expect(find.byType(WhatsNewItemView), findsNWidgets(7));
      expect(_text(tester, const Key('whatsNewItemTitle-reading')), 'Auto-read');
      expect(find.byKey(_body('reading')), findsOneWidget, reason: 'the first row starts open');
      expect(_text(tester, const Key('whatsNewPara-reading-1')), contains('(kept up to 24 hours)'));
      await _openRow(tester, 'notifications');
      expect(_text(tester, const Key('whatsNewPara-notifications-0')), kWhatsNewAutoNotificationsBody);
      await _openRow(tester, 'privacy');
      final privacy = _text(tester, const Key('whatsNewPara-privacy-0'));
      expect(privacy, kWhatsNewPrivacyAutoReadBodyProvisional);
      expect(privacy, isNot(contains(kPrivacySentenceStandard)));
      expect(find.byKey(const Key('whatsNewPara-privacy-1')), findsNothing);
    }, skip: autoreadOnly != null);
  });
}
