@Tags(['autoread'])
library;

// The To do page frame. Chips, counts equal to the bell numbers, section
// order and headings, empty card, quiet note, scroll-only focus, text 1.3, dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/logic/all_view_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/quiet_note.dart';
import 'package:mmogo/autoread/ui/todo_copy.dart';
import 'package:mmogo/autoread/ui/waiting_bell_numbers.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

Widget _host(Widget child, {double scale = 1.0, bool dark = false}) => MaterialApp(
      theme: dark ? AppTheme.forPalette(AppPalette.dark) : AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: child,
    );

void main() {
  final skip = !kAutoReadCompiled; // autoread flavor only
  final readyOnly = WaitingItem(id: heldIdFor(1), kind: WaitingKind.readyToParse, heldAt: kFakeNow.subtract(const Duration(hours: 1)));
  WaitingItem cat(int n) => WaitingItem(
        id: heldIdFor(n),
        kind: WaitingKind.waitingCategory,
        heldAt: kFakeNow.subtract(Duration(minutes: n)),
        parsed: sampleFields(n, kFakeNow.subtract(Duration(minutes: n))),
      );
  WaitingItem unreadable(int n) =>
      WaitingItem(id: heldIdFor(n), kind: WaitingKind.unreadable, heldAt: kFakeNow.subtract(const Duration(hours: 2)));
  WaitingItem ready(int n) =>
      WaitingItem(id: heldIdFor(n), kind: WaitingKind.readyToParse, heldAt: kFakeNow.subtract(Duration(hours: n)));

  Future<FakeAutoReadWaitingRepository> open(
    WidgetTester t,
    List<WaitingItem> items, {
    double scale = 1.0,
    bool dark = false,
    NotifChip chip = NotifChip.todo,
    ValueNotifier<String?>? note,
    String? focusId,
    double width = 390,
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = Size(width, 900);
    addTearDown(t.view.reset);
    final repo = FakeAutoReadWaitingRepository(items, now: () => kFakeNow);
    await t.pumpWidget(_host(
      NotificationsPage(
        news: FakeNotificationsRepository(const []),
        waiting: repo,
        initialChip: chip,
        clock: () => kFakeNow,
        quietNote: note,
        focusId: focusId,
        waitingActions: WaitingActions(onParse: (_) {}, onParseAll: (_) {}),
      ),
      scale: scale,
      dark: dark,
    ));
    await t.pump();
    await t.pump();
    return repo;
  }

  String count(WidgetTester t) => t.widget<Text>(find.byKey(const Key('notif-chip-count-todo'))).data!;

  group('To do chips and counts', () {
    testWidgets('two chips only: To do and News', (t) async {
      await open(t, [readyOnly]);
      expect(find.byKey(const Key('notif-chip-todo')), findsOneWidget);
      expect(find.byKey(const Key('notif-chip-news')), findsOneWidget);
      for (final k in ['all', 'parse', 'categorize']) {
        expect(find.byKey(Key('notif-chip-$k')), findsNothing);
      }
      expect(find.text(kTodoChipLabel), findsOneWidget);
    }, skip: skip);

    for (final (name, items) in <(String, List<WaitingItem>)>[
      ('0', []),
      ('1', [ready(1)]),
      ('n', [ready(1), ready(2), cat(3), cat(4), cat(5), unreadable(6)]),
    ]) {
      testWidgets('chip number equals the two bell numbers added, for $name', (t) async {
        await open(t, items);
        final bell = (await t.runAsync(() =>
            waitingBellNumbers(FakeAutoReadWaitingRepository(items, now: () => kFakeNow), () => kFakeNow).first))!;
        expect(count(t), '${bell.waiting + bell.readyToParse}');
        expect(todoCount(items, kFakeNow), bell.waiting + bell.readyToParse);
        // Could not read is not in the number.
        expect(find.text('$kHeadingToParse (${items.where((i) => i.kind == WaitingKind.readyToParse).length})'),
            items.any((i) => i.kind == WaitingKind.readyToParse) ? findsOneWidget : findsNothing);
      }, skip: skip);
    }

    testWidgets('heading counts equal the rows under them', (t) async {
      await open(t, [ready(1), ready(2), unreadable(3), cat(4), cat(5), cat(6)]);
      expect(find.text('$kHeadingToParse (2)'), findsOneWidget);
      expect(find.text('$kHeadingCouldNotRead (1)'), findsOneWidget);
      expect(find.text('$kHeadingToCategorize (3)'), findsOneWidget);
      expect(find.byKey(Key('waiting-row-${heldIdFor(4)}')), findsOneWidget);
      expect(count(t), '5');
    }, skip: skip);

    testWidgets('any chip that opens To do opens To do', (t) async {
      for (final c in [NotifChip.all, NotifChip.parse, NotifChip.categorize, NotifChip.todo]) {
        await open(t, [cat(1)], chip: c);
        expect(find.text('$kHeadingToCategorize (1)'), findsOneWidget, reason: c.name);
      }
    }, skip: skip);
  });

  group('To do sections', () {
    testWidgets('order: To parse, Could not read, To categorize', (t) async {
      await open(t, [cat(4), unreadable(3), ready(1)]);
      double y(String text) => t.getTopLeft(find.text(text)).dy;
      expect(y('$kHeadingToParse (1)'), lessThan(y('$kHeadingCouldNotRead (1)')));
      expect(y('$kHeadingCouldNotRead (1)'), lessThan(y('$kHeadingToCategorize (1)')));
    }, skip: skip);

    testWidgets('empty card with the mock words; no news under To do', (t) async {
      await open(t, const []);
      expect(find.text(kTodoEmptyTitle), findsOneWidget);
      expect(find.text(kTodoEmptyBody), findsOneWidget);
      expect(count(t), '0');
    }, skip: skip);

    testWidgets('focus scrolls the row into view and draws no outline', (t) async {
      final items = [for (var i = 1; i <= 12; i++) cat(i)];
      await open(t, items, focusId: heldIdFor(12));
      await t.pump();
      await t.pump();
      expect(find.byKey(const Key('waiting-row-focused')), findsNothing);
      expect(t.getTopLeft(find.byKey(Key('waiting-row-${heldIdFor(12)}'))).dy, lessThan(900));
    }, skip: skip);

    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('text $scale, dark $dark: no overflow, chips 44 px, one row', (t) async {
          await open(t, [ready(1), ready(2), unreadable(3), cat(4)], scale: scale, dark: dark, width: 360);
          expect(t.takeException(), isNull);
          final tops = <double>{};
          for (final c in todoNewsChips) {
            final f = find.byKey(Key('notif-chip-${c.name}'));
            expect(t.getSize(f).height, greaterThanOrEqualTo(44));
            tops.add(t.getTopLeft(f).dy);
          }
          expect(tops.length, 1);
        }, skip: skip);
      }
    }
  });

  group('QuietNote', () {
    testWidgets('shows the text as a live region and goes on the next tap', (t) async {
      final note = ValueNotifier<String?>(null);
      await open(t, [cat(1)], note: note);
      expect(find.byKey(const Key('quiet-note')), findsNothing);
      note.value = 'Moved to To categorize.';
      await t.pump();
      expect(find.text('Moved to To categorize.'), findsOneWidget);
      expect(find.byType(QuietNote), findsOneWidget);
      await t.tapAt(const Offset(200, 600));
      await t.pump();
      expect(note.value, isNull);
      expect(find.byKey(const Key('quiet-note')), findsNothing);
    }, skip: skip);
  });
}
