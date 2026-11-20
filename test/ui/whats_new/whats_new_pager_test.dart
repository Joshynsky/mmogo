// 0.1.2 A5a (WN1, PK2, CW2): the full-screen What's-new page. A banner at the
// top, the title, the intro, expandable rows (first open, one open at a time, can be
// open), one pinned Got it, the system Back key (closes, marks nothing), the
// injected Settings route button, the banner link, 44 px, dark, text scale 1.3 and
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

const _headIds = ['withdrawals', 'suggest', 'paidto', 'backups'];
const _moreIds = ['pochi', 'updates', 'links', 'pill'];
const _ids = [..._headIds, ..._moreIds, 'privacy'];

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
                  onOpenSettings: (_) {
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

/// Opens the "More changes" fold if it is closed.
Future<void> _showMore(WidgetTester tester) async {
  if (find.byKey(const Key('whatsNewMoreLabel')).evaluate().isNotEmpty) return;
  await tester.ensureVisible(find.byKey(const Key('whatsNewMoreToggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('whatsNewMoreToggle')));
  await tester.pumpAndSettle();
}

List<String> _titles(WidgetTester tester, List<String> ids) => [for (final id in ids) _text(tester, Key('whatsNewItemTitle-$id'))];

/// Opens a row (scrolling to it first); a closed row's header is tapped. A row in the fold opens the fold first.
Future<void> _toggle(WidgetTester tester, String id) async {
  if (find.byKey(_head(id)).evaluate().isEmpty) await _showMore(tester); // the row is in the fold
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
    testWidgets('banner, title, intro, four headline rows, the fold, and the mock words', (tester) async {
      await _pump(tester);
      expect(find.byKey(_pager), findsOneWidget);
      expect(_text(tester, const Key('whatsNewPagerTitle')), "What's new in mmogo 0.2.1");
      expect(_text(tester, const Key('whatsNewIntro')), 'Tap one to read it.');
      // The banner is above the title.
      expect(tester.getTopLeft(find.byKey(const Key('whatsNewBanner'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('whatsNewPagerTitle'))).dy));
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the standard version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'There is a second version that can read and parse your M‑Pesa messages for you. '
        'It puts them on a waiting list for you to categorize and review. '
        'It asks for SMS permission, so it is separate and optional.',
      );
      expect(find.text('Open the mmogo page'), findsOneWidget);
      // Folded: the four headline rows, then Privacy; the "More changes" rows are not built.
      expect(find.byType(WhatsNewItemView), findsNWidgets(5));
      expect(_titles(tester, _headIds), ['Withdrawals', 'Suggested categories', 'Paid to: choose an account', 'Backups']);
      for (final id in _moreIds) {
        expect(find.byKey(_head(id)), findsNothing, reason: id);
      }
      await tester.ensureVisible(find.byKey(const Key('whatsNewMoreToggle')));
      expect(find.text('Show more changes'), findsOneWidget);
      expect(_text(tester, const Key('whatsNewStill')), 'Everything from 0.2.0 is still here.');
      // After the fold button, in order: the line, then Privacy.
      expect(tester.getTopLeft(find.byKey(const Key('whatsNewMoreToggle'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('whatsNewStill'))).dy));
      expect(tester.getTopLeft(find.byKey(const Key('whatsNewStill'))).dy, lessThan(tester.getTopLeft(find.byKey(_head('privacy'))).dy));
      await tester.tap(find.byKey(const Key('whatsNewMoreToggle')));
      await tester.pumpAndSettle();
      expect(find.text('Hide more changes'), findsOneWidget);
      expect(_text(tester, const Key('whatsNewMoreLabel')), 'MORE CHANGES');
      expect(_titles(tester, _moreIds), ['Pochi', 'Updates', 'What’s new links to Settings', 'Pop-up messages']);
      expect(find.byType(WhatsNewItemView), findsNWidgets(9));
      await tester.tap(find.byKey(const Key('whatsNewMoreToggle')));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewItemView), findsNWidgets(5), reason: 'the fold closes again');
    }, skip: standardOnly != null);

    testWidgets('every item carries the tag "New in 0.2.1"', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      for (final id in _ids) {
        await tester.ensureVisible(find.byKey(Key('whatsNewItemTag-$id')));
        expect(_text(tester, Key('whatsNewItemTag-$id')), 'New in 0.2.1', reason: id);
      }
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

    testWidgets('the standard page never shows an auto-read only item or line', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      for (final id in ['ask', 'notif', 'hide', 'recorded']) {
        expect(find.byKey(_head(id)), findsNothing, reason: id);
      }
      await _openRow(tester, 'withdrawals');
      expect(find.byKey(const Key('whatsNewPara-withdrawals-6')), findsNothing, reason: 'the extra Notifications line is for the other build');
      expect(find.byKey(const Key('whatsNewPara-withdrawals-5')), findsOneWidget);
      await _openRow(tester, 'suggest');
      expect(find.byKey(const Key('whatsNewPara-suggest-3')), findsNothing, reason: 'two shared paragraphs and the last one: three');
      expect(find.textContaining('planned for the next update'), findsNothing);
      expect(find.textContaining('Ask first'), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('the first row starts open, the others closed; each closed row shows its one-line summary', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      expect(find.byKey(_body('withdrawals')), findsOneWidget);
      expect(find.byKey(_summary('withdrawals')), findsNothing, reason: 'open: the summary is not repeated');
      for (final id in _ids.skip(1)) {
        expect(find.byKey(_body(id)), findsNothing, reason: id);
        await tester.ensureVisible(find.byKey(_summary(id)));
        expect(find.byKey(_summary(id)), findsOneWidget, reason: id);
      }
      expect(_text(tester, _summary('suggest')), 'mmogo suggests the categories you use most for each person.');
      expect(_text(tester, _summary('paidto')), 'When one person has several accounts, you choose which one to look at.');
      expect(_text(tester, _summary('backups')), 'A backup made with 0.2.1 cannot be restored by 0.2.0 or older.');
      expect(_text(tester, _summary('pochi')), 'When a Pochi message is read, you choose Pochi or Send Money.');
      expect(_text(tester, _summary('updates')), 'Check for updates from Settings, under About.');
      expect(_text(tester, _summary('links')), 'Items now open the Settings area they describe.');
      expect(_text(tester, _summary('pill')), 'Messages like Undo now show at the top and follow your theme.');
      expect(_text(tester, _summary('privacy')), 'No permissions except internet, used only to check for updates (switchable off).');
    }, skip: standardOnly != null);

    testWidgets('a tap opens a row and a second tap closes it; only one row is open at a time', (tester) async {
      await _pump(tester);
      await _toggle(tester, 'suggest');
      expect(find.byKey(_body('suggest')), findsOneWidget);
      expect(find.byKey(_body('withdrawals')), findsNothing, reason: 'opening a row closes the one that was open');
      expect(find.byKey(_summary('withdrawals')), findsOneWidget);
      await _toggle(tester, 'backups');
      expect(find.byKey(_body('backups')), findsOneWidget);
      expect(find.byKey(_body('suggest')), findsNothing);
      await _toggle(tester, 'backups');
      expect(find.byKey(_body('backups')), findsNothing, reason: 'tapping the open row closes it');
      expect(find.byKey(_summary('backups')), findsOneWidget);
    }, skip: standardOnly != null);

    testWidgets('Withdrawals: the six paragraphs of the mock, in order', (tester) async {
      await _pump(tester);
      final paras = [for (var i = 0; i < 6; i++) _text(tester, Key('whatsNewPara-withdrawals-$i'))];
      expect(paras, kWhatsNewWithdrawalsBody);
      expect(paras.first, 'A cash withdrawal stays a withdrawal. It is not counted as spending.');
      expect(paras[1], contains('"Cash only" is the default: nothing is added.'));
      expect(paras[3], contains('Recently deleted brings them all back within 1 hour.'));
      expect(paras.last, 'Withdrawals you saved before this update are not changed. Open one to say what the cash was for.');
    }, skip: standardOnly != null);

    testWidgets('Suggested categories: the text and the Open in Settings button (no auto-record line)', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'suggest');
      expect(_text(tester, const Key('whatsNewPara-suggest-0')), kWhatsNewSuggestBody[0]);
      expect(_text(tester, const Key('whatsNewPara-suggest-1')), contains('Pick one type at a time: Send Money, Paybill, Buy Goods, Pochi, Withdrawals (muted) or Airtime.'));
      expect(
        _text(tester, const Key('whatsNewPara-suggest-2')),
        'These rules stay on this phone and are not in backups. If you restore a backup with Replace, everyone goes back to Suggested.',
      );
      expect(find.byKey(const Key('whatsNewCalSettings')), findsOneWidget);
      expect(find.text('Open in Settings'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('Backups says 0.2.1 / 0.2.0 and has no button; Paid to and the More rows say what the mock says', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      await _openRow(tester, 'backups');
      expect(
        _text(tester, const Key('whatsNewPara-backups-0')),
        'A backup made with 0.2.1 cannot be restored by 0.2.0 or older. Older backups still restore.',
      );
      expect(find.byKey(const Key('whatsNewOpenBackup')), findsNothing);
      await _openRow(tester, 'paidto');
      expect(_text(tester, const Key('whatsNewPara-paidto-0')), kWhatsNewPaidToBody);
      await _openRow(tester, 'pochi');
      expect(_text(tester, const Key('whatsNewPara-pochi-0')), 'When mmogo reads a Pochi message, you choose whether it is Pochi or Send Money.');
      await _openRow(tester, 'updates');
      expect(_text(tester, const Key('whatsNewPara-updates-0')), contains('"Check for updates now"'));
      await _openRow(tester, 'links');
      expect(_text(tester, const Key('whatsNewPara-links-0')), contains('Back returns you to the item you were reading.'));
      await _openRow(tester, 'pill');
      expect(_text(tester, const Key('whatsNewPara-pill-0')), contains('It follows your light or dark theme.'));
    }, skip: standardOnly != null);

    testWidgets('R13 (F4): "Open in Settings" is a real button, 44 px high, not a link', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      await _openRow(tester, 'suggest');
      const k = Key('whatsNewCalSettings');
      await tester.ensureVisible(find.byKey(k));
      await tester.pumpAndSettle();
      final b = tester.widget<FilledButton>(find.byKey(k));
      final text = tester.widget<Text>(find.descendant(of: find.byKey(k), matching: find.text('Open in Settings')));
      final sem = tester.getSemantics(find.byKey(k));
      expect(sem.flagsCollection.isButton, isTrue);
      expect(sem.label, 'Open in Settings');
      expect(tester.getSize(find.byKey(k)).height, greaterThanOrEqualTo(44));
      expect(b.style?.backgroundColor?.resolve({}), isNotNull);
      expect(text.style?.decoration, isNull, reason: 'no underline: not a link');
      h.dispose();
    });

    testWidgets('Privacy: the signed sentence in bold, then the rules line; sign-off last; no expander', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'privacy');
      expect(_text(tester, const Key('whatsNewPara-privacy-0')), kPrivacySentenceStandard);
      expect(
        _text(tester, const Key('whatsNewPara-privacy-0')),
        'No permissions except internet, used only to check for updates (switchable off).',
      );
      expect(_text(tester, const Key('whatsNewPara-privacy-1')), 'The rules you set for each person stay on this phone. They are not in backups.');
      expect(find.byKey(const Key('whatsNewPara-privacy-2')), findsNothing);
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
      await _toggle(tester, 'suggest');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(host.result, isFalse);
    });

    testWidgets('a second page cannot be opened while one is on screen', (tester) async {
      await _pump(tester);
      final ctx = tester.element(find.byKey(_pager));
      final second = await showWhatsNewPager(ctx, onOpenSettings: (_) {}, onOpenBackup: () {});
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

  group('the Settings route button (injected, pushed over the page)', () {
    testWidgets('Open in Settings opens the stub route; Back returns to the same page and rows; nothing is marked', (tester) async {
      final host = await _pump(tester);
      await _openRow(tester, 'suggest');
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(host.opened, ['settings']);
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.byKey(_body('suggest')), findsOneWidget);
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
      await _openRow(tester, 'suggest');
      final palette = AppPalette.of(tester.element(find.byKey(_pager)));
      expect(palette.brightness, Brightness.dark);
      double ratio(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      final body = tester.widget<Text>(find.byKey(const Key('whatsNewPara-suggest-0'))).style!.color!;
      final title = tester.widget<Text>(find.byKey(const Key('whatsNewItemTitle-suggest'))).style!.color!;
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
      await tester.ensureVisible(find.byKey(_head('suggest')));
      final closed = tester.getSemantics(find.byKey(_head('suggest')));
      expect(closed.flagsCollection.isButton, isTrue);
      expect(closed.flagsCollection.isExpanded, ui.Tristate.isFalse);
      expect(closed.label, contains('Suggested categories'));
      expect(closed.label, contains(kWhatsNewSuggestSummary));
      await _toggle(tester, 'suggest');
      expect(tester.getSemantics(find.byKey(_head('suggest'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
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
      await tester.ensureVisible(find.byKey(_head('backups')));
      final label = tester.getSemantics(find.byKey(_head('backups'))).label;
      expect(label, isNot(contains('4')), reason: 'backups is item 4; the badge is not spoken');
      expect(label, contains(kWhatsNewTagNew), reason: 'the origin tag is spoken');
      handle.dispose();
    });

    test('the title is a fixed constant, not the app version', () {
      expect(kWhatsNewPagerVersion, '0.2.1');
    });
  });

  group('the auto-read build (flag on)', () {
    testWidgets('banner, four headline rows (Ask first among them), the fold of eight, and its signed Privacy item', (tester) async {
      await _pump(tester);
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the auto-read version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'It reads your M‑Pesa messages and puts them on a waiting list for you to categorize and review. '
        'If you do not want SMS permission, the standard version works without it.',
      );
      expect(find.byKey(const Key('whatsNewBannerLink')), findsNothing, reason: 'no link on this banner');
      expect(_text(tester, const Key('whatsNewIntro')), kWhatsNewIntro);
      expect(find.byType(WhatsNewItemView), findsNWidgets(5), reason: 'four headline rows and Privacy; the fold is closed');
      expect(_titles(tester, ['withdrawals', 'ask', 'suggest', 'backups']), ['Withdrawals', 'Ask first', 'Suggested categories', 'Backups']);
      await _showMore(tester);
      const more = ['notif', 'paidto', 'pochi', 'hide', 'recorded', 'updates', 'links', 'pill'];
      expect(
        _titles(tester, more),
        [
          'Notifications page',
          'Paid to: choose an account',
          'Pochi',
          'Hide details after',
          'Recorded automatically filter',
          'Updates',
          'What’s new links to Settings',
          'Pop-up messages',
        ],
      );
      expect(find.byType(WhatsNewItemView), findsNWidgets(13));
      await tester.ensureVisible(find.byKey(const Key('whatsNewItemTag-privacy')));
      expect(_text(tester, const Key('whatsNewItemTag-privacy')), 'New in 0.2.1');
      expect(find.byKey(_body('withdrawals')), findsOneWidget, reason: 'the first row starts open');
      await _openRow(tester, 'privacy');
      final privacy = _text(tester, const Key('whatsNewPara-privacy-0'));
      expect(privacy, 'This version asks for SMS and notification permission. Your messages stay on this phone.');
      expect(privacy, kWhatsNewPrivacyAutoReadBody);
      expect(privacy, isNot(contains(kPrivacySentenceStandard)));
      expect(_text(tester, const Key('whatsNewPara-privacy-1')), 'The rules you set for each person stay on this phone. They are not in backups.');
      expect(find.byKey(const Key('whatsNewPara-privacy-2')), findsNothing);
    }, skip: autoreadOnly != null);

    testWidgets('Withdrawals adds the Notifications paragraph; Suggested adds the level lines and says Auto-record is planned', (tester) async {
      await _pump(tester);
      expect(_text(tester, const Key('whatsNewPara-withdrawals-6')), kWhatsNewAutoWithdrawalsExtra);
      expect(_text(tester, const Key('whatsNewPara-withdrawals-6')), contains('"3 withdrawals need a decision"'));
      await _openRow(tester, 'suggest');
      expect(_text(tester, const Key('whatsNewPara-suggest-2')), 'For each person you choose a level: Suggested or Ask first.');
      expect(
        _text(tester, const Key('whatsNewPara-suggest-3')),
        'A third level, Auto-record, where mmogo records without asking for people you choose, is planned for the next update. It is not in this one.',
      );
      expect(_text(tester, const Key('whatsNewPara-suggest-4')), kWhatsNewSuggestLast);
      expect(find.byKey(const Key('whatsNewCalSettings')), findsOneWidget);
    }, skip: autoreadOnly != null);

    testWidgets('Ask first, Notifications page (the four lists), Hide details after and the filter say what the mock says', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'ask');
      expect([for (var i = 0; i < 5; i++) _text(tester, Key('whatsNewPara-ask-$i'))], kWhatsNewAskBody);
      expect(_text(tester, const Key('whatsNewPara-ask-1')), 'A tap always decides. Nothing is recorded without a tap.');
      await _openRow(tester, 'notif');
      expect(
        _text(tester, const Key('whatsNewPara-notif-0')),
        'The Notifications page groups what needs you into lists: To confirm, To parse, To categorize and Could not read. '
        'The bell shows how many are waiting.',
      );
      await _openRow(tester, 'hide');
      expect(_text(tester, const Key('whatsNewPara-hide-0')), contains('Never, 5 minutes, 15 minutes, 30 minutes or 1 hour.'));
      expect(_text(tester, const Key('whatsNewPara-hide-1')), 'Only the alert goes away. The message stays for 24 hours.');
      await _openRow(tester, 'recorded');
      expect(_text(tester, const Key('whatsNewPara-recorded-0')), 'A "Recorded automatically" filter now covers entries from 0.2.1 onward.');
    }, skip: autoreadOnly != null);
  });
}
