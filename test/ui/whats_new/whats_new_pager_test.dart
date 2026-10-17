// 0.1.2 S11a (WN1, PK2, CW2): the What's-new pager. Five cards in the signed
// order, Next / Back / swipe, only the last card has Got it, the system Back
// key, no outside-tap or drag close, the two injected route buttons, 44 px,
// dark, text scale 1.3 and the announcements. Stub routes only: the real
// Settings and Backup pages are never built; nothing touches prefs or network.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

const _next = Key('whatsNewNext');
const _back = Key('whatsNewBack');
const _gotIt = Key('whatsNewGotIt');
const _pager = Key('whatsNewPager');
const _title = Key('whatsNewCardTitle');
const _body = Key('whatsNewCardBody');

Future<_Host> _pump(
  WidgetTester tester, {
  bool dark = false,
  double scale = 1.0,
  Size size = const Size(400, 900),
  bool open = true,
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

Future<void> _tapNext(WidgetTester tester, [int times = 1]) async {
  for (var i = 0; i < times; i++) {
    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
  }
}

String _titleText(WidgetTester tester) => tester.widget<Text>(find.byKey(_title)).data!;
String _bodyText(WidgetTester tester) => tester.widget<Text>(find.byKey(_body)).data!;

void main() {
  group('the five cards, in the signed order', () {
    testWidgets('titles and bodies are the named constants, card 1 to card 5', (tester) async {
      await _pump(tester);
      expect(find.text(kWhatsNewPagerTitle), findsOneWidget);
      expect(kWhatsNewPagerTitle, "What's new in mmogo 0.1.2");
      final titles = <String>[];
      final bodies = <String>[];
      for (var i = 0; i < 5; i++) {
        titles.add(_titleText(tester));
        bodies.add(_bodyText(tester));
        if (i < 4) await _tapNext(tester);
      }
      expect(titles, [
        'Withdrawals, airtime and Pochi',
        'Weeks',
        'Same phone number = one person',
        'Backups',
        'Privacy',
      ]);
      expect(bodies, [kWhatsNewCard1Body, kWhatsNewCard2Body, kWhatsNewCard3Body, kWhatsNewCard4Body, kWhatsNewCard5Body]);
    });

    testWidgets('card 1: the truthful placeholder, no Analytics claim, the short independence line', (tester) async {
      await _pump(tester);
      final body = _bodyText(tester);
      expect(body, contains('Home and Paid to show how many you made and what they cost.'));
      expect(body, contains('A withdrawal adds 0 to what you spent; only its Transaction cost counts toward costs.'));
      expect(body, isNot(contains('Analytics shows how many')));
      expect(tester.widget<Text>(find.byKey(const Key('whatsNewIndependence'))).data, kIndependenceShort);
    });

    testWidgets('card 2: Weeks text with the regrouped sentence and the Change in Settings button', (tester) async {
      await _pump(tester);
      await _tapNext(tester);
      expect(_bodyText(tester), contains('A week now runs from the day you choose in Settings (Monday unless you change it).'));
      expect(_bodyText(tester), contains('Before, a week meant the last 7 days: today and the 6 days before it.'));
      expect(_bodyText(tester), contains('Past weekly figures are regrouped to match; nothing saved changes.'));
      expect(find.byKey(const Key('whatsNewCalSettings')), findsOneWidget);
      expect(find.text('Change in Settings'), findsOneWidget);
    });

    testWidgets('card 3: before / after picture with an invented name, names both the 07 and 01 forms, the softer wording (F4 R10), no setting', (tester) async {
      await _pump(tester);
      await _tapNext(tester, 2);
      final body = _bodyText(tester);
      expect(body, contains('(07 and 01 numbers alike)'));
      expect(body, contains('We have corrected that: they now count as one person on Paid to,'));
      expect(body, isNot(contains('mistake')));
      expect(body, contains('0712 345 678 and +254 712 345 678'));
      expect(body, contains('totals are added together'));
      expect(body, contains('The numbers saved on your entries do not change.'));
      expect(find.text(kWhatsNewCard3Extra), findsOneWidget);
      expect(
        kWhatsNewCard3Extra,
        'A number written 07... or +254 7... is the same number, so it joins. '
        'The same goes for 01... and +254 1.... '
        'A 07 number and a 01 number are different numbers and stay separate.',
      );
      expect(find.byKey(const Key('whatsNewPicture')), findsOneWidget);
      // The picture is read as one image with the mock's description.
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel(kWhatsNewPicLabel), findsOneWidget);
      handle.dispose();
      // No setting and no Off state on this card.
      expect(find.byType(Switch), findsNothing);
      expect(find.textContaining('Off'), findsNothing);
      expect(find.byKey(const Key('whatsNewCalSettings')), findsNothing);
    });

    testWidgets('card 4: Backups with the 0.1.1 sentence, the D7 constant, W3 and the Open Backup button', (tester) async {
      await _pump(tester);
      await _tapNext(tester, 3);
      final body = _bodyText(tester);
      expect(body, contains('Backups from 0.1.1 still restore.'));
      expect(body, contains(kBackupNotRestorableByOlder));
      expect(body, contains(kUninstallErasesNotice));
      expect(find.byKey(const Key('whatsNewOpenBackup')), findsOneWidget);
      expect(find.text(kWhatsNewOpenBackup), findsOneWidget);
    });

    testWidgets('R13 (F4): "Change in Settings" and "Open Backup and restore" are real buttons of one style, 44 px high', (tester) async {
      final h = tester.ensureSemantics();
      await _pump(tester);
      Future<(Size, Color?, TextDecoration?)> look(Key k, String label) async {
        final b = tester.widget<FilledButton>(find.byKey(k));
        final text = tester.widget<Text>(find.descendant(of: find.byKey(k), matching: find.text(label)));
        final sem = tester.getSemantics(find.byKey(k));
        expect(sem.flagsCollection.isButton, isTrue, reason: label);
        expect(sem.label, label);
        return (tester.getSize(find.byKey(k)), b.style?.backgroundColor?.resolve({}), text.style?.decoration);
      }

      await _tapNext(tester);
      final settings = await look(const Key('whatsNewCalSettings'), 'Change in Settings');
      await _tapNext(tester, 2);
      final backup = await look(const Key('whatsNewOpenBackup'), 'Open Backup and restore');
      expect(settings.$1.height, greaterThanOrEqualTo(44));
      expect(backup.$1.height, greaterThanOrEqualTo(44));
      expect(backup.$2, isNotNull);
      expect(backup.$2, settings.$2, reason: 'same fill on cards 2 and 4');
      expect(backup.$3, isNull, reason: 'no underline: not a link');
      expect(find.byType(TextButton), findsNothing);
      h.dispose();
    });

    testWidgets('card 5: the canonical sentence, W7, the sign-off, plain text with no expander', (tester) async {
      await _pump(tester);
      await _tapNext(tester, 4);
      // R14 (F4): the canonical sentence, then only the second half of W7 (no repeated "used only to check for updates").
      expect(_bodyText(tester), '$kPrivacySentenceStandard $kNetworkSeenSentence');
      expect(
        _bodyText(tester),
        'No permissions except internet, used only to check for updates (switchable off). '
        'GitHub sees your IP address and that the request comes from the mmogo app. '
        'No entries, names or messages are sent.',
      );
      expect('used only to check for updates'.allMatches(_bodyText(tester)), hasLength(1));
      expect(tester.widget<Text>(find.byKey(const Key('whatsNewSignOff'))).data, kWhatsNewSignOff);
      expect(kWhatsNewSignOff, '— Josh');
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      // The full independence sentence belongs to the Privacy page, not here.
      expect(find.textContaining(kIndependenceFull), findsNothing);
    });
  });

  group('moving between cards', () {
    testWidgets('Next and Back move one card; there is no Back on the first card', (tester) async {
      await _pump(tester);
      expect(find.byKey(_back), findsNothing);
      await _tapNext(tester, 2);
      expect(_titleText(tester), kWhatsNewCard3Title);
      expect(find.byKey(_back), findsOneWidget);
      await tester.tap(find.byKey(_back));
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard2Title);
    });

    testWidgets('a swipe left goes forward, a swipe right goes back, and the ends do not wrap', (tester) async {
      await _pump(tester);
      await tester.fling(find.byKey(_body), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard2Title);
      await tester.fling(find.byKey(_body), const Offset(300, 0), 1200);
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard1Title);
      await tester.fling(find.byKey(_body), const Offset(300, 0), 1200);
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard1Title);
      expect(find.byKey(_pager), findsOneWidget);
      await _tapNext(tester, 4);
      await tester.fling(find.byKey(_body), const Offset(-300, 0), 1200);
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard5Title);
    });

    testWidgets('the dots show five and are not tappable', (tester) async {
      await _pump(tester);
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(Key('whatsNewDot$i')), findsOneWidget);
      }
      await tester.tap(find.byKey(const Key('whatsNewDot3')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard1Title);
    });

    testWidgets('only the last card has Got it; the others have Next', (tester) async {
      await _pump(tester);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(_gotIt), findsNothing, reason: 'card ${i + 1}');
        expect(find.byKey(_next), findsOneWidget, reason: 'card ${i + 1}');
        expect(find.text('Got it'), findsNothing);
        await _tapNext(tester);
      }
      expect(find.byKey(_gotIt), findsOneWidget);
      expect(find.byKey(_next), findsNothing);
      expect(find.text('Got it'), findsOneWidget);
    });
  });

  group('closing', () {
    testWidgets('Got it closes the pager and returns true to the page it was opened from', (tester) async {
      final host = await _pump(tester);
      await _tapNext(tester, 4);
      await tester.tap(find.byKey(_gotIt));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(host.result, isTrue);
    });

    testWidgets('system Back steps back one card; on the first card it closes and returns false (unseen)', (tester) async {
      final host = await _pump(tester);
      await _tapNext(tester, 2);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard2Title);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard1Title);
      expect(host.result, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(host.result, isFalse);
    });

    testWidgets('an outside tap and a downward drag do nothing', (tester) async {
      final host = await _pump(tester);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      await tester.drag(find.byKey(const Key('whatsNewPagerTitle')), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(host.result, isNull);
    });

    testWidgets('a second pager cannot be opened while one is on screen', (tester) async {
      await _pump(tester);
      final ctx = tester.element(find.byKey(_pager));
      final second = await showWhatsNewPager(ctx, onOpenSettings: () {}, onOpenBackup: () {});
      await tester.pumpAndSettle();
      expect(second, isFalse);
      expect(find.byKey(_pager), findsOneWidget);
    });
  });

  group('the two route buttons (injected, pushed over the pager)', () {
    testWidgets('Change in Settings opens the stub route; Back returns to the same card; nothing closes or is marked', (tester) async {
      final host = await _pump(tester);
      await _tapNext(tester);
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(host.opened, ['settings']);
      expect(find.text('SETTINGS STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(_titleText(tester), kWhatsNewCard2Title);
      expect(host.result, isNull);
    });

    testWidgets('Open Backup and restore opens the stub route; Back returns to card 4', (tester) async {
      final host = await _pump(tester);
      await _tapNext(tester, 3);
      await tester.tap(find.byKey(const Key('whatsNewOpenBackup')));
      await tester.pumpAndSettle();
      expect(host.opened, ['backup']);
      expect(find.text('BACKUP STUB'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(_titleText(tester), kWhatsNewCard4Title);
      expect(host.result, isNull);
    });
  });

  group('44 px, dark, text scale 1.3', () {
    Future<void> every44(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        for (final k in [_next, _back, _gotIt, const Key('whatsNewCalSettings'), const Key('whatsNewOpenBackup')]) {
          final f = find.byKey(k);
          if (f.evaluate().isEmpty) continue;
          final size = tester.getSize(f);
          expect(size.height, greaterThanOrEqualTo(44), reason: 'card ${i + 1} $k height');
          expect(size.width, greaterThanOrEqualTo(44), reason: 'card ${i + 1} $k width');
        }
        if (i < 4) await _tapNext(tester);
      }
    }

    testWidgets('every button is at least 44 x 44', (tester) async {
      await _pump(tester);
      await every44(tester);
    });

    testWidgets('dark and 1.3: the buttons stay pinned and on screen, the card scrolls', (tester) async {
      await _pump(tester, dark: true, scale: 1.3, size: const Size(360, 520));
      for (var i = 0; i < 5; i++) {
        final primary = find.byKey(i < 4 ? _next : _gotIt);
        final rect = tester.getRect(primary);
        expect(rect.bottom, lessThanOrEqualTo(520), reason: 'card ${i + 1} button inside the screen');
        expect(rect.height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull, reason: 'card ${i + 1} no overflow');
        if (i < 4) await _tapNext(tester);
      }
      // Card 5 is long at 1.3 on a short screen: the scroll area has room to move, the buttons do not.
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(const Key('backupSheetScroll')), matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final before = tester.getRect(find.byKey(_gotIt));
      await tester.drag(find.byKey(const Key('backupSheetScroll')), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byKey(_gotIt)), before);
    });

    testWidgets('dark: the card text contrasts with the sheet surface', (tester) async {
      await _pump(tester, dark: true);
      final ctx = tester.element(find.byKey(_title));
      final palette = AppPalette.of(ctx);
      expect(palette.brightness, Brightness.dark);
      final ink = tester.widget<Text>(find.byKey(_body)).style!.color!;
      final a = palette.card.computeLuminance();
      final b = ink.computeLuminance();
      final ratio = (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
      expect(ratio, greaterThan(4.5));
    });
  });

  group('semantics and focus', () {
    testWidgets('"Card N of 5" is announced as a live region and follows the card', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(find.bySemanticsLabel(whatsNewCardOfText(1)), findsOneWidget);
      expect(whatsNewCardOfText(1), 'Card 1 of 5');
      final node = tester.getSemantics(find.bySemanticsLabel('Card 1 of 5'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      await _tapNext(tester, 2);
      expect(find.bySemanticsLabel('Card 3 of 5'), findsOneWidget);
      expect(find.bySemanticsLabel('Card 1 of 5'), findsNothing);
      handle.dispose();
    });

    testWidgets('focus goes to the card title when the card opens and on every change', (tester) async {
      await _pump(tester);
      bool titleFocused() => tester.widget<Focus>(find.byKey(const Key('whatsNewCardTitleFocus'))).focusNode!.hasPrimaryFocus;
      expect(titleFocused(), isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(titleFocused(), isFalse);
      await _tapNext(tester);
      expect(titleFocused(), isTrue);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(_back));
      await tester.pumpAndSettle();
      expect(titleFocused(), isTrue);
    });

    testWidgets('the card title is a header and the sheet is named by the pager title', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester);
      expect(tester.getSemantics(find.byKey(_title)).flagsCollection.isHeader, isTrue);
      expect(find.bySemanticsLabel(kWhatsNewPagerTitle), findsWidgets);
      handle.dispose();
    });

    test('the title is a fixed constant, not the app version', () {
      expect(kWhatsNewPagerVersion, '0.1.2');
      expect(WhatsNewCardView.titleOf(0), kWhatsNewCard1Title);
    });
  });
}
