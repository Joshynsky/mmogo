@Tags(['autoread'])
library;

// F3: WaitingSection (the To do lists) and the page in the
// autoread flavor. The WaitingSection tests also run in the standard flavor
// (the widget does not read the flag); the page tests need the flag.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart' show sortWaitingCategory;
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/todo_copy.dart';
import 'package:mmogo/autoread/ui/unreadable_copy.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/news_heading_bar.dart';
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

Widget _section(WaitingDataSet set, {WaitingActions? actions}) =>
    _host(Scaffold(
      body: SingleChildScrollView(
        child: WaitingSection(
          waiting: waitingSet(set, kFakeNow).items,
          now: kFakeNow,
          actions: actions ?? const WaitingActions(),
        ),
      ),
    ));

Iterable<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.textSpan?.toPlainText() ?? w.data ?? '');

void main() {
  group('WaitingSection', () {
    testWidgets('To do: to parse (soonest first), then to categorize with the gone row last inside it; no news', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.typical));
      // Ready: 1 (2 h held), 2 (12 h), 3 (20 h, expires soonest); 4 is gone; 5, 6, 7 categorize (newest first).
      final order = [_w(3), _w(2), _w(1), _w(5), _w(6), _w(7), _w(4)];
      for (final f in order) {
        expect(f, findsOneWidget);
      }
      final ys = [for (final f in order) _y(t, f)];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: 'row $i out of order');
      }
      final texts = _texts(t).toList();
      expect(texts, containsAll(['$kHeadingToParse (3)', '$kHeadingToCategorize (4)']));
      expect(find.text(kWaitingNotCounted), findsOneWidget);
    });

    testWidgets('To do: ready rows have Parse; the gone row says so; categorize rows have Categorize and no Dismiss',
        (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.typical));
      expect(find.text(kGoneLine), findsOneWidget);
      expect(find.text(kActionParse), findsNWidgets(3));
      expect(find.text(kActionCategorize), findsNWidgets(3));
      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('UNREADABLE row is shown (not lost) with Remove and no Paste; the tap reaches the callback',
        (t) async {
      _size(t, 360);
      final id = heldIdFor(9);
      final items = [WaitingItem(id: id, kind: WaitingKind.unreadable, heldAt: kFakeNow.subtract(const Duration(hours: 20)))];
      final calls = <String>[];
      await t.pumpWidget(_host(Scaffold(
        body: WaitingSection(
          waiting: items,
          now: kFakeNow,
          actions: WaitingActions(
            onPaste: (i) => calls.add('paste ${i.id == id}'),
            onRemove: (i) => calls.add('remove ${i.id == id}'),
          ),
        ),
      )));
      expect(find.text(kUnreadableTitle), findsOneWidget);
      expect(find.text(kActionPaste), findsNothing);
      expect(find.byKey(const Key('waitingRowDimIcon')), findsOneWidget);
      // 0.2.2 (F11): an unreadable row sits inside To categorize; no "To parse (0)".
      expect(_texts(t), contains('$kHeadingToCategorize (1)'));
      expect(_texts(t), isNot(contains('$kHeadingToParse (0)')));
      // F6: Paste goes through the paste sheet, Remove through its question.
      await t.tap(find.text(kActionRemove));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('removeConfirm')));
      await t.pumpAndSettle();
      expect(calls, ['remove true']);
    });

    testWidgets('unwired actions are no-ops (tapping does not throw)', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.typical));
      await t.tap(find.text(kActionRemove).first);
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('GONE row carries the recovery words', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.typical));
      expect(find.text(kGoneLine), findsOneWidget);
      expect(find.text(kGoneRecovery), findsOneWidget);
      expect(find.text(kGoneFooter), findsOneWidget);
    });

    testWidgets('empty: the To do card; with rows there is no card', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.empty));
      expect(find.text(kTodoEmptyTitle), findsOneWidget);
      expect(find.text(kTodoEmptyBody), findsOneWidget);
      await t.pumpWidget(_section(WaitingDataSet.fiveWaiting));
      expect(find.text(kTodoEmptyTitle), findsNothing);
    });

    testWidgets('focusId: a row far down the list is scrolled into view, with no outline', (t) async {
      _size(t, 360);
      final items = waitingSet(WaitingDataSet.many, kFakeNow).items;
      final last = sortWaitingCategory(items, kFakeNow).last;
      await t.pumpWidget(_host(Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            waiting: items,
            now: kFakeNow,
            focusId: last.id,
          ),
        ),
      )));
      await t.pump();
      await t.pump();
      final row = find.byKey(Key('waiting-row-${last.id}'));
      expect(row, findsOneWidget);
      expect(find.byKey(const Key('waiting-row-focused')), findsNothing);
      expect(t.getTopLeft(row).dy, inInclusiveRange(0, 900), reason: 'row is on screen');
    });

    testWidgets('focusId not listed: no scrolling, nothing thrown', (t) async {
      _size(t, 360);
      await t.pumpWidget(_host(Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            waiting: waitingSet(WaitingDataSet.typical, kFakeNow).items,
            now: kFakeNow,
            focusId: heldIdFor(9999),
          ),
        ),
      )));
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('99+ cap on the group headings', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(WaitingDataSet.many));
      expect(_texts(t), contains('$kHeadingToCategorize (99+)'));
    });

    for (final w in [360.0, 390.0]) {
      testWidgets('layout at ${w.toInt()} px, text 1.3: no overflow', (t) async {
        _size(t, w);
        await t.pumpWidget(_host(
          Scaffold(
            body: SingleChildScrollView(
              child: WaitingSection(
                waiting: waitingSet(WaitingDataSet.typical, kFakeNow).items,
                now: kFakeNow,
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

    testWidgets('chips and counts: To do 6 (3 to parse + 3 to categorize), News 4 (unread only)', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews());
      expect(find.byKey(const Key('notif-chip-all')), findsNothing);
      expect(find.byKey(const Key('notif-chip-parse')), findsNothing);
      expect(find.byKey(const Key('notif-chip-categorize')), findsNothing);
      expect([count(t, NotifChip.todo), count(t, NotifChip.news)], ['6', '4']);
      expect(find.bySemanticsLabel('To do, 6'), findsOneWidget);
      expect(find.text('$kHeadingToParse (3)'), findsOneWidget);
      expect(find.text('$kHeadingToCategorize (3)'), findsOneWidget);
      // The gone row is listed under Could not read but is not in the chip number.
      expect(_w(4), findsOneWidget);
    }, skip: skip);

    testWidgets('99+ cap on the chip', (t) async {
      await open(t, WaitingDataSet.many, typicalNews());
      expect(count(t, NotifChip.todo), '99+');
    }, skip: skip);

    testWidgets('To do shows parse and categorize rows together; News is its own list; back to To do', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews());
      expect(_w(3), findsOneWidget);
      expect(_w(5), findsOneWidget);
      expect(_n('n1'), findsNothing); // no news under To do
      await t.tap(find.byKey(const Key('notif-chip-news')));
      await t.pump();
      expect(_w(3), findsNothing);
      await t.tap(find.descendant(of: find.byType(NewsHeadingBar), matching: find.text(kNewsSwitchRead)));
      await t.pump();
      expect(_n('n3'), findsOneWidget);
      await t.tap(find.byKey(const Key('notif-chip-todo')));
      await t.pump();
      await t.tap(find.byKey(const Key('notif-chip-news')));
      await t.pump();
      expect(_n('n3'), findsNothing); // back on Unread
    }, skip: skip);

    testWidgets('an old chip value (parse) opens To do', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews(), chip: NotifChip.parse);
      expect(_w(5), findsOneWidget);
      expect(find.text('$kHeadingToCategorize (3)'), findsOneWidget);
    }, skip: skip);

    testWidgets('a held message the parser cannot read becomes an unreadable row, not lost', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews());
      expect(find.text(kUnreadableTitle), findsNothing);
      await t.tap(find.bySemanticsLabel(RegExp('^$kActionParse the M-Pesa message')).first); // oldest first
      await t.pump();
      await t.pump();
      expect(find.text(kUnreadableTitle), findsOneWidget);
      expect(find.text(kActionRemove), findsNWidgets(2)); // the unreadable one and the gone one
      expect(count(t, NotifChip.todo), '5'); // 2 readable + 3 to categorize
    }, skip: skip);

    testWidgets('reading off: quiet line and the way to turn it on; rows stay', (t) async {
      await open(t, WaitingDataSet.typical, typicalNews(), readingOn: false);
      expect(find.text(kReadingOffLine), findsOneWidget);
      expect(find.text(kTurnOnReading), findsOneWidget);
      expect(_w(3), findsOneWidget);
    }, skip: skip);

    testWidgets('empty states on the page: To do card, then News', (t) async {
      await open(t, WaitingDataSet.empty, const []);
      expect(find.text(kTodoEmptyTitle), findsOneWidget);
      expect(find.text(kTodoEmptyBody), findsOneWidget);
      await t.tap(find.byKey(const Key('notif-chip-news')));
      await t.pump();
      expect(find.text(kNewsEmptyUnreadTitle), findsOneWidget);
      expect([count(t, NotifChip.todo), count(t, NotifChip.news)], ['0', '0']);
    }, skip: skip);

    for (final w in [360.0, 390.0]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('layout at ${w.toInt()} px, text $scale: chips in one row, 44 px, no overflow', (t) async {
          await open(t, WaitingDataSet.many, typicalNews(), width: w, scale: scale);
          expect(t.takeException(), isNull);
          final tops = <double>{};
          for (final c in todoNewsChips) {
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
    testWidgets('no Dismissible, no dismiss control, wired or not', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section(
        WaitingDataSet.typical,
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
  });
}
