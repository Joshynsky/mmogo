@Tags(['autoread'])
library;

// F3: WaitingSection (the Parse, Categorize and All lists) and the page in the
// autoread flavor. The WaitingSection tests also run in the standard flavor
// (the widget does not read the flag); the page tests need the flag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart' show sortWaitingCategory;
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/news_heading_bar.dart';
import 'package:mmogo/ui/screens/notifications/news_row.dart' as nr;
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

Widget _host(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: child,
    );

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 900);
  addTearDown(t.view.reset);
}

Finder _w(int n) => find.byKey(Key('waiting-row-${heldIdFor(n)}'));
Finder _n(String id) => find.byKey(Key('news-row-$id'));
double _y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

Widget _section(NotifChip chip, WaitingDataSet set, List<NewsItem> news, {WaitingActions? actions}) =>
    _host(Scaffold(
      body: SingleChildScrollView(
        child: WaitingSection(
          chip: chip,
          waiting: waitingSet(set, kFakeNow).items,
          news: news,
          now: kFakeNow,
          newsRowBuilder: (n) => nr.NewsRow(n, kFakeNow),
          actions: actions ?? const WaitingActions(),
        ),
      ),
    ));

Iterable<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '');

void main() {
  group('WaitingSection', () {
    testWidgets('All: to parse (soonest first, unreadable and gone last), to categorize, then unread news',
        (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.all, WaitingDataSet.typical, typicalNews()));
      // Ready: 1 (2 h held), 2 (12 h), 3 (20 h, expires soonest); 4 is gone; 5, 6, 7 categorize (newest first).
      final order = [_w(3), _w(2), _w(1), _w(4), _w(5), _w(6), _w(7), _n('upd1'), _n('n1'), _n('n2'), _n('wn1')];
      for (final f in order) {
        expect(f, findsOneWidget);
      }
      final ys = [for (final f in order) _y(t, f)];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: 'row $i out of order');
      }
      expect(_n('n3'), findsNothing); // read news only under News > Read
      final texts = _texts(t).toList();
      expect(texts, containsAll(['$kHeadingToParse (3)', '$kHeadingToCategorize (3)', 'News (4)']));
      expect(find.text(kWaitingNotCounted), findsOneWidget);
    });

    testWidgets('Parse: ready rows then the unreadable-looking gone row, count is readable only', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.parse, WaitingDataSet.typical, typicalNews()));
      expect(_texts(t), contains('$kHeadingToParse (3)'));
      expect(_w(3), findsOneWidget);
      expect(_w(4), findsOneWidget);
      expect(_w(5), findsNothing); // categorize rows are not here
      expect(_n('n1'), findsNothing); // no news here
      expect(find.text(kGoneLine), findsOneWidget);
      expect(find.text(kActionParse), findsNWidgets(3));
    });

    testWidgets('Categorize: quiet line, three rows, no Dismiss anywhere', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.categorize, WaitingDataSet.typical, typicalNews()));
      expect(_texts(t), contains('$kHeadingToCategorize (3)'));
      expect(find.text(kWaitingNotCounted), findsOneWidget);
      expect(find.text(kActionCategorize), findsNWidgets(3));
      expect(find.text('Dismiss'), findsNothing);
      expect(_w(1), findsNothing);
    });

    testWidgets('UNREADABLE row is shown (not lost) with Paste and Remove; taps reach the callbacks',
        (t) async {
      _size(t, 360);
      final id = heldIdFor(9);
      final items = [WaitingItem(id: id, kind: WaitingKind.unreadable, heldAt: kFakeNow.subtract(const Duration(hours: 20)))];
      final calls = <String>[];
      await t.pumpWidget(_host(Scaffold(
        body: WaitingSection(
          chip: NotifChip.parse,
          waiting: items,
          news: const [],
          now: kFakeNow,
          newsRowBuilder: (n) => const SizedBox(),
          actions: WaitingActions(
            onPaste: (i) => calls.add('paste ${i.id == id}'),
            onRemove: (i) => calls.add('remove ${i.id == id}'),
          ),
        ),
      )));
      expect(find.text(kCouldNotRead), findsOneWidget);
      expect(find.byKey(const Key('waitingRowDimIcon')), findsOneWidget);
      expect(_texts(t), contains('$kHeadingToParse (0)')); // shown, but not counted
      // F6: Paste goes through the paste sheet, Remove through its question.
      await t.tap(find.text(kActionPaste));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pasteContinue')));
      await t.pumpAndSettle();
      await t.tap(find.text(kActionRemove));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('removeConfirm')));
      await t.pumpAndSettle();
      expect(calls, ['paste true', 'remove true']);
      expect(find.text(kEmptyParseTitle), findsNothing);
    });

    testWidgets('unwired actions are no-ops (tapping does not throw)', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.parse, WaitingDataSet.typical, const []));
      await t.tap(find.text(kActionRemove).first);
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('GONE row on All carries the recovery words', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.all, WaitingDataSet.typical, const []));
      expect(find.text(kGoneLine), findsOneWidget);
      expect(find.text(kGoneRecovery), findsOneWidget);
      expect(find.text(kGoneFooter), findsOneWidget);
    });

    testWidgets('empty states per chip', (t) async {
      _size(t, 360);
      for (final c in [
        (NotifChip.parse, kEmptyParseTitle, kEmptyParseBody),
        (NotifChip.categorize, kEmptyCategorizeTitle, kEmptyCategorizeBody),
        (NotifChip.all, kEmptyAllTitle, kEmptyAllBody),
      ]) {
        await t.pumpWidget(_section(c.$1, WaitingDataSet.empty, const []));
        expect(find.text(c.$2), findsOneWidget, reason: c.$1.name);
        expect(find.text(c.$3), findsOneWidget, reason: c.$1.name);
      }
      // Parse empty while categorize has rows.
      await t.pumpWidget(_section(NotifChip.parse, WaitingDataSet.fiveWaiting, const []));
      expect(find.text(kEmptyParseTitle), findsOneWidget);
    });

    testWidgets('focusId: a row far down the list is scrolled into view and outlined', (t) async {
      _size(t, 360);
      final items = waitingSet(WaitingDataSet.many, kFakeNow).items;
      final last = sortWaitingCategory(items, kFakeNow).last;
      await t.pumpWidget(_host(Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            chip: NotifChip.categorize,
            waiting: items,
            news: const [],
            now: kFakeNow,
            newsRowBuilder: (n) => nr.NewsRow(n, kFakeNow),
            focusId: last.id,
          ),
        ),
      )));
      await t.pump();
      await t.pump();
      final row = find.byKey(Key('waiting-row-${last.id}'));
      expect(row, findsOneWidget);
      expect(find.byKey(const Key('waiting-row-focused')), findsOneWidget);
      expect(t.getTopLeft(row).dy, inInclusiveRange(0, 900), reason: 'row is on screen');
    });

    testWidgets('focusId not listed: no outline, no scrolling', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.parse, WaitingDataSet.typical, const []));
      await t.pumpWidget(_host(Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            chip: NotifChip.parse,
            waiting: waitingSet(WaitingDataSet.typical, kFakeNow).items,
            news: const [],
            now: kFakeNow,
            newsRowBuilder: (n) => nr.NewsRow(n, kFakeNow),
            focusId: heldIdFor(9999),
          ),
        ),
      )));
      await t.pump();
      expect(find.byKey(const Key('waiting-row-focused')), findsNothing);
    });
    testWidgets('99+ cap on the group headings', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(NotifChip.categorize, WaitingDataSet.many, const []));
      expect(_texts(t), contains('$kHeadingToCategorize (99+)'));
    });

    for (final w in [360.0, 390.0]) {
      testWidgets('layout at ${w.toInt()} px, text 1.3: no overflow', (t) async {
        _size(t, w);
        await t.pumpWidget(_host(
          Scaffold(
            body: SingleChildScrollView(
              child: WaitingSection(
                chip: NotifChip.all,
                waiting: waitingSet(WaitingDataSet.typical, kFakeNow).items,
                news: typicalNews(),
                now: kFakeNow,
                newsRowBuilder: (n) => nr.NewsRow(n, kFakeNow),
              ),
            ),
          ),
          scale: 1.3,
        ));
        expect(t.takeException(), isNull);
      });
    }
  });

  group('NotificationsPage, autoread flavor', () {
    final skip = !kAutoReadCompiled; // autoread flavor only (--dart-define=MMOGO_AUTOREAD=true)

    Future<FakeAutoReadWaitingRepository> open(
      WidgetTester t,
      WaitingDataSet set,
      List<NewsItem> news, {
      double width = 360,
      double scale = 1.0,
      NotifChip chip = NotifChip.all,
      bool readingOn = true,
    }) async {
      _size(t, width);
      final waiting = FakeAutoReadWaitingRepository.forSet(set, () => kFakeNow);
      await t.pumpWidget(_host(
        NotificationsPage(
          news: FakeNotificationsRepository(news),
          waiting: waiting,
          initialChip: chip,
          clock: () => kFakeNow,
          readingOn: readingOn,
          waitingActions: WaitingActions(onParse: (i) => waiting.parse(i.id)),
        ),
        scale: scale,
      ));
      await t.pump();
      await t.pump();
      return waiting;
    }

    String count(WidgetTester t, NotifChip c) =>
        t.widget<Text>(find.byKey(Key('notif-chip-count-${c.name}'))).data!;

    testWidgets('chips and counts: All 10, Parse 3, Categorize 3, News 4 (unread only)', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews());
      expect([for (final c in NotifChip.values) count(t, c)], ['10', '3', '3', '4']);
      expect(find.bySemanticsLabel('$kHeadingToParse, 3'), findsOneWidget);
      expect(find.bySemanticsLabel('$kHeadingToCategorize, 3'), findsOneWidget);
      // Unreadable and gone rows are not counted: the gone row is on the list but not in Parse 3.
      expect(_w(4), findsOneWidget);
    }, skip: skip);

    testWidgets('99+ cap on the chips', (t) async {
      await open(t, WaitingDataSet.many, typicalNews());
      expect(count(t, NotifChip.categorize), '99+');
      expect(count(t, NotifChip.all), '99+');
      expect(count(t, NotifChip.parse), '12');
    }, skip: skip);

    testWidgets('selecting chips shows each list; switching resets Unread | Read', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews());
      await t.tap(find.byKey(const Key('notif-chip-parse')));
      await t.pump();
      expect(_w(3), findsOneWidget);
      expect(_w(5), findsNothing);
      await t.tap(find.byKey(const Key('notif-chip-categorize')));
      await t.pump();
      expect(_w(5), findsOneWidget);
      expect(_w(3), findsNothing);
      await t.tap(find.byKey(const Key('notif-chip-news')));
      await t.pump();
      await t.tap(find.descendant(of: find.byType(NewsHeadingBar), matching: find.text(kNewsSwitchRead)));
      await t.pump();
      expect(_n('n3'), findsOneWidget);
      await t.tap(find.byKey(const Key('notif-chip-all')));
      await t.pump();
      await t.tap(find.byKey(const Key('notif-chip-news')));
      await t.pump();
      expect(_n('n3'), findsNothing); // back on Unread
    }, skip: skip);

    testWidgets('a held message the parser cannot read becomes an unreadable row, not lost', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews(), chip: NotifChip.parse);
      expect(find.text(kCouldNotRead), findsNothing);
      await t.tap(find.bySemanticsLabel(RegExp('^$kActionParse the M-Pesa message')).first); // oldest first
      await t.pump();
      await t.pump();
      expect(find.text(kCouldNotRead), findsOneWidget);
      expect(find.text(kActionPaste), findsNWidgets(2)); // unreadable and gone
      expect(find.text(kActionRemove), findsNWidgets(2)); // the unreadable one and the gone one
      expect(count(t, NotifChip.parse), '2');
    }, skip: skip);

    testWidgets('reading off: quiet line and the way to turn it on; rows stay', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews(), readingOn: false);
      expect(find.text(kReadingOffLine), findsOneWidget);
      expect(find.text(kTurnOnReading), findsOneWidget);
      expect(_w(3), findsOneWidget);
    }, skip: skip);

    testWidgets('empty states per chip on the page', (t) async {
      await open(t, WaitingDataSet.empty, const []);
      expect(find.text(kEmptyAllTitle), findsOneWidget);
      for (final (chip, title) in [
        (NotifChip.parse, kEmptyParseTitle),
        (NotifChip.categorize, kEmptyCategorizeTitle),
        (NotifChip.news, kNewsEmptyUnreadTitle),
      ]) {
        await t.tap(find.byKey(Key('notif-chip-${chip.name}')));
        await t.pump();
        expect(find.text(title), findsOneWidget, reason: chip.name);
      }
      expect([for (final c in NotifChip.values) count(t, c)], ['0', '0', '0', '0']);
    }, skip: skip);

    for (final w in [360.0, 390.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('layout at ${w.toInt()} px, text $scale: chips in one row, 44 px, no overflow', (t) async {
          await open(t, WaitingDataSet.many, typicalNews(), width: w, scale: scale);
          expect(t.takeException(), isNull);
          final tops = <double>{};
          for (final c in NotifChip.values) {
            final f = find.byKey(Key('notif-chip-${c.name}'));
            expect(t.getSize(f).height, greaterThanOrEqualTo(44), reason: c.name);
            tops.add(t.getTopLeft(f).dy);
          }
          expect(tops.length, 1, reason: 'chips must share one row');
          expect(t.getBottomRight(find.byKey(const Key('notif-chip-news'))).dx, lessThanOrEqualTo(w));
        }, skip: skip);
      }
    }
  });

  group('WaitingSection F6: no dismiss of a waiting item', () {
    for (final chip in [NotifChip.all, NotifChip.parse, NotifChip.categorize]) {
      testWidgets('${chip.name}: no Dismissible, no dismiss control, wired or not', (t) async {
        _size(t, 360);
        await t.pumpWidget(_section(
          chip,
          WaitingDataSet.typical,
          const [],
          actions: WaitingActions(
            onParse: (_) {},
            onCategorize: (_) {},
            onPaste: (_) {},
            onRemove: (_) {},
            onParseAll: (_) {},
          ),
        ));
        expect(find.byType(Dismissible), findsNothing);
        expect(find.byType(Draggable), findsNothing);
        expect(
            find.byType(GestureDetector).evaluate().where((e) {
              final w = e.widget as GestureDetector;
              return w.onHorizontalDragEnd != null || w.onHorizontalDragUpdate != null;
            }),
            isEmpty);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);
        expect(find.byIcon(Icons.clear), findsNothing);
      });
    }
  });
}
