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
import 'package:mmogo/ui/whats_new/whats_new_items.dart';
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

const _headIds = ['search', 'regroup', 'black', 'backups', 'ocean'];
const _moreIds = ['home', 'samename', 'notnow', 'receiver'];
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
        data: MediaQuery.of(
          context,
        ).copyWith(platformBrightness: dark ? Brightness.dark : Brightness.light, textScaler: TextScaler.linear(scale)),
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
    testWidgets('banner, title, intro, five headline rows, the fold, and the signed words', (tester) async {
      await _pump(tester);
      expect(find.byKey(_pager), findsOneWidget);
      expect(_text(tester, const Key('whatsNewPagerTitle')), "What's new in mmogo 0.2.2");
      expect(_text(tester, const Key('whatsNewIntro')), 'Tap one to read it.');
      // The banner is above the title.
      expect(
        tester.getTopLeft(find.byKey(const Key('whatsNewBanner'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('whatsNewPagerTitle'))).dy),
      );
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the standard version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'There is a second version that reads your M‑Pesa messages for you. '
        'It asks for SMS permission, so Google Play Protect may block it when you install it. '
        'The guide shows how to get past that. It is separate and optional.',
      );
      expect(find.text('Read the install guide'), findsOneWidget);
      // Folded: the five headline rows, then Privacy; the "More changes" rows are not built.
      expect(find.byType(WhatsNewItemView), findsNWidgets(6));
      expect(_titles(tester, _headIds), ['Search in Settings', 'Settings is regrouped', 'New black theme', 'Backups', 'Ocean looks clearer']);
      for (final id in _moreIds) {
        expect(find.byKey(_head(id)), findsNothing, reason: id);
      }
      await tester.ensureVisible(find.byKey(const Key('whatsNewMoreToggle')));
      expect(find.text('Show more changes'), findsOneWidget);
      expect(_text(tester, const Key('whatsNewStill')), 'Everything from 0.2.1 is still here.');
      // After the fold button, in order: the line, then Privacy.
      expect(
        tester.getTopLeft(find.byKey(const Key('whatsNewMoreToggle'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const Key('whatsNewStill'))).dy),
      );
      expect(tester.getTopLeft(find.byKey(const Key('whatsNewStill'))).dy, lessThan(tester.getTopLeft(find.byKey(_head('privacy'))).dy));
      await tester.tap(find.byKey(const Key('whatsNewMoreToggle')));
      await tester.pumpAndSettle();
      expect(find.text('Hide more changes'), findsOneWidget);
      expect(_text(tester, const Key('whatsNewMoreLabel')), 'MORE CHANGES');
      expect(_titles(tester, _moreIds), ['Home', 'Same name, two people', 'Not now and Back', 'Record receiver details']);
      expect(find.byType(WhatsNewItemView), findsNWidgets(10));
      await tester.tap(find.byKey(const Key('whatsNewMoreToggle')));
      await tester.pumpAndSettle();
      expect(find.byType(WhatsNewItemView), findsNWidgets(6), reason: 'the fold closes again');
    }, skip: standardOnly != null);

    testWidgets('every item carries the tag "New in 0.2.2"', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      for (final id in _ids) {
        await tester.ensureVisible(find.byKey(Key('whatsNewItemTag-$id')));
        expect(_text(tester, Key('whatsNewItemTag-$id')), 'New in 0.2.2', reason: id);
      }
    }, skip: standardOnly != null);

    testWidgets('the standard banner says nothing of auto-read, even in its spoken words', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      final all = [
        _text(tester, const Key('whatsNewBannerHead')),
        _text(tester, const Key('whatsNewBannerBody')),
        kWhatsNewBannerLink,
        kWhatsNewIntro,
      ];
      for (final t in all) {
        expect(t.toLowerCase(), isNot(contains('auto-read')), reason: t);
        expect(t.toLowerCase(), isNot(contains('autoread')), reason: t);
      }
      h.dispose();
    }, skip: standardOnly != null);

    testWidgets('the standard page never shows an auto-read only item or line, and no "planned" or "suggest yet" line', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      for (final id in ['autorecord', 'pause', 'suggest', 'reset', 'todo', 'fixes']) {
        expect(find.byKey(_head(id)), findsNothing, reason: id);
      }
      expect(find.textContaining('planned for the next update'), findsNothing);
      expect(find.textContaining('does not suggest categories yet'), findsNothing);
      expect(find.textContaining('Keep it?'), findsNothing);
      expect(find.byKey(const Key('whatsNewCalSettings')), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('the first row starts open, the others closed; each closed row shows its one-line summary', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      expect(find.byKey(_body('search')), findsOneWidget);
      expect(find.byKey(_summary('search')), findsNothing, reason: 'open: the summary is not repeated');
      for (final id in _ids.skip(1)) {
        expect(find.byKey(_body(id)), findsNothing, reason: id);
        await tester.ensureVisible(find.byKey(_summary(id)));
        expect(find.byKey(_summary(id)), findsOneWidget, reason: id);
      }
      expect(_text(tester, _summary('black')), 'Appearance now has a Black choice.');
      expect(_text(tester, _summary('regroup')), 'Settings is sorted into clearer groups.');
      expect(_text(tester, _summary('backups')), 'A backup made with 0.2.2 cannot be restored by 0.2.1 or older.');
      expect(_text(tester, _summary('ocean')), 'The Ocean look is refreshed.');
      expect(_text(tester, _summary('privacy')), 'No permissions except internet, used only to check for updates (switchable off).');
    }, skip: standardOnly != null);

    testWidgets('a tap opens a row and a second tap closes it; only one row is open at a time', (tester) async {
      await _pump(tester);
      await _toggle(tester, 'black');
      expect(find.byKey(_body('black')), findsOneWidget);
      expect(find.byKey(_body('search')), findsNothing, reason: 'opening a row closes the one that was open');
      expect(find.byKey(_summary('search')), findsOneWidget);
      await _toggle(tester, 'backups');
      expect(find.byKey(_body('backups')), findsOneWidget);
      expect(find.byKey(_body('black')), findsNothing);
      await _toggle(tester, 'backups');
      expect(find.byKey(_body('backups')), findsNothing, reason: 'tapping the open row closes it');
      expect(find.byKey(_summary('backups')), findsOneWidget);
    }, skip: standardOnly != null);

    testWidgets('the shared items say what the signed draft says', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'black');
      expect(_text(tester, const Key('whatsNewPara-black-0')), kWhatsNewBlackBody);
      expect(
        _text(tester, const Key('whatsNewPara-black-0')),
        startsWith('Appearance now has four choices: System, Light, Dark and Black.'),
      );
      await _openRow(tester, 'search');
      expect(_text(tester, const Key('whatsNewPara-search-0')), contains('Tap the magnifier at the top right of Settings.'));
      await _openRow(tester, 'regroup');
      expect(_text(tester, const Key('whatsNewPara-regroup-0')), 'The order is now Look, Adding entries, Your data and About.');
      await _openRow(tester, 'ocean');
      expect(_text(tester, const Key('whatsNewPara-ocean-0')), endsWith('Leaf and Indigo are unchanged.'));
    }, skip: standardOnly != null);

    testWidgets('Backups (standard): only the direction lines, no people settings, no button', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'backups');
      expect(
        _text(tester, const Key('whatsNewPara-backups-0')),
        'Backups from 0.2.1 and earlier still restore. A backup made with 0.2.2 cannot be restored by 0.2.1 or older.',
      );
      expect(find.byKey(const Key('whatsNewPara-backups-1')), findsNothing);
      expect(find.textContaining("people's settings"), findsNothing);
      expect(find.byKey(const Key('whatsNewOpenBackup')), findsNothing);
    }, skip: standardOnly != null);

    testWidgets('More changes: the four both-build lines say what the signed draft says', (tester) async {
      await _pump(tester);
      await _showMore(tester);
      await _openRow(tester, 'home');
      expect(_text(tester, const Key('whatsNewPara-home-0')), contains('Entries made in the same minute stay in the order they happened.'));
      await _openRow(tester, 'samename');
      expect(_text(tester, const Key('whatsNewPara-samename-0')), contains('0722***555'));
      await _openRow(tester, 'notnow');
      expect(_text(tester, const Key('whatsNewPara-notnow-0')), contains('Android Back closes the keyboard first.'));
      await _openRow(tester, 'receiver');
      expect(_text(tester, const Key('whatsNewPara-receiver-0')), contains('Forget all and Delete data still erase them.'));
    }, skip: standardOnly != null);

    test('the Updates entry body is the signed line (standard)', () {
      expect(whatsNewEntryBody(), "Black, search in Settings, a regrouped Settings, and backups that keep people's settings.");
    }, skip: standardOnly != null);

    testWidgets('Privacy: the signed sentence in bold, then the rules line; sign-off last; no expander', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'privacy');
      expect(_text(tester, const Key('whatsNewPara-privacy-0')), kPrivacySentenceStandard);
      expect(
        _text(tester, const Key('whatsNewPara-privacy-0')),
        'No permissions except internet, used only to check for updates (switchable off).',
      );
      expect(
        _text(tester, const Key('whatsNewPara-privacy-1')),
        kWhatsNewPrivacyRules,
      );
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
    testWidgets('"Read the install guide" calls the opener, is a 44 px button, and marks nothing', (tester) async {
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
      await _toggle(tester, 'search');
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
      await _openRow(tester, 'autorecord');
      await tester.ensureVisible(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(host.opened, ['settings']);
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.byKey(_body('autorecord')), findsOneWidget);
      expect(host.result, isNull);
    }, skip: autoreadOnly != null);
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
      await _openRow(tester, 'search');
      final palette = AppPalette.of(tester.element(find.byKey(_pager)));
      expect(palette.brightness, Brightness.dark);
      double ratio(Color a, Color b) {
        final x = a.computeLuminance();
        final y = b.computeLuminance();
        return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
      }

      final body = tester.widget<Text>(find.byKey(const Key('whatsNewPara-search-0'))).style!.color!;
      final title = tester.widget<Text>(find.byKey(const Key('whatsNewItemTitle-search'))).style!.color!;
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
      expect(tester.getSemantics(find.byKey(_head(kAutoReadCompiled ? 'autorecord' : 'search'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
      await tester.ensureVisible(find.byKey(_head('black')));
      final closed = tester.getSemantics(find.byKey(_head('black')));
      expect(closed.flagsCollection.isButton, isTrue);
      expect(closed.flagsCollection.isExpanded, ui.Tristate.isFalse);
      expect(closed.label, contains('New black theme'));
      expect(closed.label, contains(kWhatsNewBlackSummary));
      await _toggle(tester, 'black');
      expect(tester.getSemantics(find.byKey(_head('black'))).flagsCollection.isExpanded, ui.Tristate.isTrue);
      handle.dispose();
    });

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
      expect(kWhatsNewPagerVersion, '0.2.2');
    });
  });

  group('the auto-read build (flag on)', () {
    testWidgets('banner, nine headline rows, the fold of six, and its signed Privacy item', (tester) async {
      await _pump(tester);
      expect(_text(tester, const Key('whatsNewBannerHead')), 'This is the auto-read version of mmogo');
      expect(
        _text(tester, const Key('whatsNewBannerBody')),
        'It reads your M‑Pesa messages and puts them on a waiting list for you to categorize and review. '
        'If you do not want SMS permission, the standard version works without it. '
        'If your phone blocked the install, the install guide shows how.',
      );
      expect(find.text('Open the install guide'), findsOneWidget);
      expect(_text(tester, const Key('whatsNewIntro')), kWhatsNewIntro);
      expect(find.byType(WhatsNewItemView), findsNWidgets(10), reason: 'nine headline rows and Privacy; the fold is closed');
      expect(_titles(tester, ['autorecord', 'pause', 'suggest', 'reset', 'search', 'regroup', 'black', 'backups', 'ocean']), [
        'Auto-record',
        'Pause all Auto-record',
        'Suggested categories',
        'Reset and Forget',
        'Search in Settings',
        'Settings is regrouped',
        'New black theme',
        "Backups keep people's settings",
        'Ocean looks clearer',
      ]);
      await _showMore(tester);
      expect(_titles(tester, ['home', 'samename', 'notnow', 'receiver', 'todo', 'fixes']), [
        'Home',
        'Same name, two people',
        'Not now and Back',
        'Record receiver details',
        'To do page',
        'Fixes',
      ]);
      expect(find.byType(WhatsNewItemView), findsNWidgets(16));
      await tester.ensureVisible(find.byKey(const Key('whatsNewItemTag-privacy')));
      expect(_text(tester, const Key('whatsNewItemTag-privacy')), 'New in 0.2.2');
      expect(find.byKey(_body('autorecord')), findsOneWidget, reason: 'the first row starts open');
      await _openRow(tester, 'privacy');
      final privacy = _text(tester, const Key('whatsNewPara-privacy-0'));
      expect(privacy, 'This version asks for SMS and notification permission. Your messages stay on this phone.');
      expect(privacy, kWhatsNewPrivacyAutoReadBody);
      expect(privacy, isNot(contains(kPrivacySentenceStandard)));
      expect(
        _text(tester, const Key('whatsNewPara-privacy-1')),
        kWhatsNewPrivacyRules,
      );
    }, skip: autoreadOnly != null);

    testWidgets('Backups (auto-read) has the people settings, the direction lines and the Keep it? paragraph', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'backups');
      expect(
        _text(tester, const Key('whatsNewPara-backups-0')),
        "A backup now holds each person's level, limit and category suggestions. "
        "Backups from 0.2.1 and earlier still restore, without people's settings. "
        'A backup made with 0.2.2 cannot be restored by 0.2.1 or older.',
      );
      expect(_text(tester, const Key('whatsNewPara-backups-1')), contains('"Keep it?", with Keep and Turn off.'));
    }, skip: autoreadOnly != null);

    testWidgets('Auto-record, Pause, Suggested categories and Reset say what the signed draft says', (tester) async {
      await _pump(tester);
      await _openRow(tester, 'regroup');
      expect(_text(tester, const Key('whatsNewPara-regroup-0')), contains('Look, Adding entries, Reading messages, Auto-record, Your data and About.'));
      await _openRow(tester, 'autorecord');
      expect(_text(tester, const Key('whatsNewPara-autorecord-0')), contains('Paybill always asks first.'));
      expect(
        _text(tester, const Key('whatsNewPara-autorecord-1')),
        'You get a pop-up when a message arrives. The entry is added the next time you open mmogo.',
      );
      expect(_text(tester, const Key('whatsNewPara-autorecord-2')), contains('To stop it, change their level or pause.'));
      expect(find.text('Open in Settings'), findsOneWidget);
      await _openRow(tester, 'pause');
      expect(_text(tester, const Key('whatsNewPara-pause-0')), endsWith('Your settings are kept.'));
      await _openRow(tester, 'suggest');
      expect(_text(tester, const Key('whatsNewPara-suggest-0')), contains('in their last 10 payments'));
      await _openRow(tester, 'reset');
      expect(_text(tester, const Key('whatsNewPara-reset-0')), endsWith('Nothing already recorded changes.'));
    }, skip: autoreadOnly != null);

    testWidgets('R13 (F4): "Open in Settings" is a real button, 44 px high, not a link', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      await _openRow(tester, 'autorecord');
      const k = Key('whatsNewCalSettings');
      await tester.ensureVisible(find.byKey(k));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.descendant(of: find.byKey(k), matching: find.text('Open in Settings')));
      final sem = tester.getSemantics(find.byKey(k));
      expect(sem.flagsCollection.isButton, isTrue);
      expect(sem.label, 'Open in Settings');
      expect(tester.getSize(find.byKey(k)).height, greaterThanOrEqualTo(44));
      expect(text.style?.decoration, isNull, reason: 'no underline: not a link');
      h.dispose();
    }, skip: autoreadOnly != null);

    testWidgets('no line anywhere says Auto-record is planned or that Suggested does not suggest yet', (tester) async {
      await _pump(tester);
      for (final id in ['autorecord', 'pause', 'suggest', 'reset']) {
        await _openRow(tester, id);
      }
      expect(find.textContaining('planned for the next update'), findsNothing);
      expect(find.textContaining('does not suggest categories yet'), findsNothing);
      expect(
        whatsNewEntryBody(),
        "Black, search in Settings, a regrouped Settings, and backups that keep people's settings. Auto-record for people you choose.",
      );
    }, skip: autoreadOnly != null);
  });
}
