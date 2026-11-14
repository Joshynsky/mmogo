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

const _ids = ['airother', 'backups', 'nav', 'airtime', 'receiver', 'deleted', 'exports', 'privacy'];

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
    testWidgets('banner, title, intro and eight rows, with the mock\'s words', (tester) async {
      await _pump(tester);
      expect(find.byKey(_pager), findsOneWidget);
      expect(_text(tester, const Key('whatsNewPagerTitle')), "What's new in mmogo 0.2.0");
      expect(_text(tester, const Key('whatsNewIntro')), kWhatsNewIntro);
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
        'Airtime for another number',
        'Backups',
        'Navigation bar',
        'Airtime on Paid to',
        'Receiver details',
        'Recently deleted',
        'Exports',
        'Privacy',
      ]);
      expect(find.byType(WhatsNewItemView), findsNWidgets(8));
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
      expect(find.byKey(_body('airother')), findsOneWidget);
      expect(find.byKey(_summary('airother')), findsNothing, reason: 'open: the summary is not repeated');
      for (final id in _ids.skip(1)) {
        expect(find.byKey(_body(id)), findsNothing, reason: id);
        await tester.ensureVisible(find.byKey(_summary(id)));
        expect(find.byKey(_summary(id)), findsOneWidget, reason: id);
      }
      expect(_text(tester, _summary('airtime')), 'Paid to now counts airtime.');
      expect(_text(tester, _summary('receiver')), 'You choose whether receiver names and numbers are kept.');
      expect(_text(tester, _summary('deleted')), 'Recently deleted says how long you can restore.');
      expect(_text(tester, _summary('exports')), 'Exports no longer leave copies behind.');
      expect(_text(tester, _summary('privacy')), 'No permissions except internet, used only to check for updates.');
    }, skip: standardOnly != null);

    testWidgets('a tap opens a row and a second tap closes it; only one row is open at a time', (tester) async {
      await _pump(tester);
      await _toggle(tester, 'receiver');
      expect(find.byKey(_body('receiver')), findsOneWidget);
      expect(find.byKey(_body('airother')), findsNothing, reason: 'opening a row closes the one that was open');
      expect(find.byKey(_summary('airother')), findsOneWidget);
      await _toggle(tester, 'exports');
      expect(find.byKey(_body('exports')), findsOneWidget);
      expect(find.byKey(_body('receiver')), findsNothing);
      await _toggle(tester, 'exports');
      expect(find.byKey(_body('exports')), findsNothing, reason: 'tapping the open row closes it');
      expect(find.byKey(_summary('exports')), findsOneWidget);
    }, skip: standardOnly != null);

    testWidgets('item 1: the bottom bar text', (tester) async {
      await _pump(tester);
      await _toggle(tester, 'nav');
      final body = _text(tester, const Key('whatsNewPara-nav-0'));
      expect(body, kWhatsNewNavBody);
      expect(body, contains('the Home, Analytics, Paid to and Profile tabs were covered'));
      expect(body, contains('They now sit above the buttons.'));
    }, skip: standardOnly != null);

    testWidgets('item 2: airtime on Paid to, the overview line and when it is hidden', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'airtime');
      final body = _text(tester, const Key('whatsNewPara-airtime-0'));
      expect(body, kWhatsNewAirtimeBody);
      expect(body, contains('Paid out on Paid to now matches This month on Home.'));
      expect(body, contains('It is hidden while you search or filter by category.'));
    }, skip: standardOnly != null);

    testWidgets('item 3: receiver details text and the Change in Settings button', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'receiver');
      final body = _text(tester, const Key('whatsNewPara-receiver-0'));
      expect(body, kWhatsNewReceiverBody);
      expect(body, contains('In Settings, Record receiver details is on or off.'));
      expect(body, contains('Entries you already saved are not changed.'));
      expect(find.byKey(const Key('whatsNewCalSettings')), findsOneWidget);
      expect(find.text('Change in Settings'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('item 4: Recently deleted says 1 hour and that the web row is gone', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'deleted');
      final body = _text(tester, const Key('whatsNewPara-deleted-0'));
      expect(body, kWhatsNewDeletedBody);
      expect(body, contains('You can restore a deleted entry for 1 hour.'));
    }, skip: standardOnly != null);

    testWidgets('item 5: exports say the temporary copies are removed, and Delete data clears old ones', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'exports');
      final body = _text(tester, const Key('whatsNewPara-exports-0'));
      expect(body, kWhatsNewExportsBody);
      expect(body, contains('the temporary copies mmogo made are removed'));
      expect(body, contains('Delete data also removes any left over from an earlier version.'));
    }, skip: standardOnly != null);

    testWidgets('R13 (F4): "Change in Settings" is a real button, 44 px high, not a link', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      await _openRow(tester, 'receiver');
      const k = Key('whatsNewCalSettings');
      await tester.ensureVisible(find.byKey(k));
      await tester.pumpAndSettle();
      final b = tester.widget<FilledButton>(find.byKey(k));
      final text = tester.widget<Text>(find.descendant(of: find.byKey(k), matching: find.text('Change in Settings')));
      final sem = tester.getSemantics(find.byKey(k));
      expect(sem.flagsCollection.isButton, isTrue);
      expect(sem.label, 'Change in Settings');
      expect(tester.getSize(find.byKey(k)).height, greaterThanOrEqualTo(44));
      expect(b.style?.backgroundColor?.resolve({}), isNotNull);
      expect(text.style?.decoration, isNull, reason: 'no underline: not a link');
      expect(find.byKey(const Key('whatsNewOpenBackup')), findsNothing, reason: 'no item has the Backup button in 0.1.3');
      h.dispose();
    });

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
      expect(_text(tester, const Key('whatsNewPara-privacy-2')), kWhatsNewCard5Receiver);
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
      await _toggle(tester, 'receiver');
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

  group('the Settings route button (injected, pushed over the page)', () {
    testWidgets('Change in Settings opens the stub route; Back returns to the same page and rows; nothing is marked', (tester) async {
      final host = await _pump(tester);
      await _openRow(tester, 'receiver');
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(host.opened, ['settings']);
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.byKey(_body('receiver')), findsOneWidget);
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
      await _openRow(tester, 'nav');
      final palette = AppPalette.of(tester.element(find.byKey(_pager)));
      expect(palette.brightness, Brightness.dark);
      double ratio(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      final body = tester.widget<Text>(find.byKey(const Key('whatsNewPara-nav-0'))).style!.color!;
      final title = tester.widget<Text>(find.byKey(const Key('whatsNewItemTitle-nav'))).style!.color!;
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
      expect(tester.getSemantics(find.byKey(_head('airother'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
      await tester.ensureVisible(find.byKey(_head('receiver')));
      final closed = tester.getSemantics(find.byKey(_head('receiver')));
      expect(closed.flagsCollection.isButton, isTrue);
      expect(closed.flagsCollection.isExpanded, ui.Tristate.isFalse);
      expect(closed.label, contains('Receiver details'));
      expect(closed.label, contains(kWhatsNewReceiverSummary));
      await _toggle(tester, 'receiver');
      expect(tester.getSemantics(find.byKey(_head('receiver'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
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
      await tester.ensureVisible(find.byKey(_head('receiver')));
      final label = tester.getSemantics(find.byKey(_head('receiver'))).label;
      expect(label, isNot(contains('5')), reason: 'receiver is item 5; the badge is not spoken');
      expect(label, contains(kWhatsNewTagFrom013), reason: 'the origin tag is spoken');
      handle.dispose();
    });

    test('the title is a fixed constant, not the app version', () {
      expect(kWhatsNewPagerVersion, '0.2.0');
    });
  });

  group('the auto-read build (flag on)', () {
    testWidgets('banner, twelve items (new in 0.2.0 first, then the 0.1.3 six) and its signed Privacy item', (tester) async {
      await _pump(tester);
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the auto-read version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'It reads your M\u2011Pesa messages and puts them on a waiting list for you to categorize and review. '
        'If you do not want SMS permission, the standard version works without it.',
      );
      expect(find.byKey(const Key('whatsNewBannerLink')), findsNothing, reason: 'no link on this banner');
      expect(_text(tester, const Key('whatsNewIntro')), kWhatsNewIntro);
      expect(find.byType(WhatsNewItemView), findsNWidgets(12));
      expect(find.byKey(const Key('whatsNewItemTitle-reading')), findsNothing);
      expect(find.byKey(_body('airother')), findsOneWidget, reason: 'the first row starts open');
      await _openRow(tester, 'privacy');
      final privacy = _text(tester, const Key('whatsNewPara-privacy-0'));
      expect(privacy, kWhatsNewPrivacyAutoReadBody);
      expect(privacy, isNot(contains(kPrivacySentenceStandard)));
      expect(_text(tester, const Key('whatsNewPara-privacy-1')), kWhatsNewPrivacyAutoReadTrail);
      expect(_text(tester, const Key('whatsNewPara-privacy-2')), kWhatsNewPrivacyAutoReadKept);
      expect(_text(tester, const Key('whatsNewPara-privacy-3')), kWhatsNewPrivacyAutoReadReceiverNote);
      expect(find.byKey(const Key('whatsNewPara-privacy-4')), findsNothing);
    }, skip: autoreadOnly != null);
  });
}
