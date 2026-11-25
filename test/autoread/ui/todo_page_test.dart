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
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/shell/bell_counts.dart' show WaitingBellNumbers;
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

    testWidgets('the withdrawals-decision item counts as ONE in the To do number; Could not read still does not', (t) async {
      t.view.devicePixelRatio = 1.0;
      t.view.physicalSize = const Size(390, 900);
      addTearDown(t.view.reset);
      final undecided = ValueNotifier<List<AnalyticsTransactionRow>>([
        for (final i in [1, 2])
          AnalyticsTransactionRow(
            id: i,
            displayCode: 'WDU000000$i',
            sourceType: 'AGENT_WITHDRAWAL',
            amountCents: 100000,
            counterpartyLabel: 'Test Agent',
            counterpartyPhone: null,
            paybillAccountNumber: null,
            classificationId: 1,
            classificationName: 'Withdrawal',
            occurredAt: kFakeNow,
            transactionCostCents: 0,
          ),
      ]);
      final items = [ready(1), ready(2), unreadable(3), cat(4)];
      await t.pumpWidget(_host(NotificationsPage(
        news: FakeNotificationsRepository(const []),
        waiting: FakeAutoReadWaitingRepository(items, now: () => kFakeNow),
        initialChip: NotifChip.todo,
        clock: () => kFakeNow,
        waitingActions: WaitingActions(onParse: (_) {}, undecided: undecided, onDecisionCashOnly: (_) async {}, onDecisionCategorize: (_) async {}),
      )));
      await t.pump();
      await t.pump();
      expect(count(t), '4'); // 2 to parse + 1 to categorize + the ONE decision item (2 withdrawals)
      // The bell (same source) shows the same total: the decision item is ONE in the amber number.
      final repo = FakeAutoReadWaitingRepository(items, now: () => kFakeNow);
      final seen = <WaitingBellNumbers>[];
      final sub = waitingBellNumbers(repo, () => kFakeNow, undecided: undecided).listen(seen.add);
      addTearDown(sub.cancel);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(seen.last.waiting, 2); // 1 to categorize + the decision item
      expect(seen.last.readyToParse, 2);
      expect(seen.last.waiting + seen.last.readyToParse, int.parse(count(t)));
      undecided.value = const [];
      await t.pump();
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(count(t), '3');
      expect(seen.last.waiting + seen.last.readyToParse, 3); // the bell dropped with the item
    }, skip: skip);

    testWidgets('zero number with a Could not read row listed: chip shows To do with no number', (t) async {
      final h = t.ensureSemantics();
      await open(t, [unreadable(1)]);
      expect(todoCount([unreadable(1)], kFakeNow), 0); // the number itself is unchanged
      expect(find.byKey(const Key('notif-chip-count-todo')), findsNothing);
      expect(find.text('$kHeadingToCategorize (1)'), findsOneWidget); // F11: unreadable lives in To categorize
      expect(t.getSemantics(find.byKey(const Key('notif-chip-todo'))).label, kTodoChipSpoken);
      h.dispose();
    }, skip: skip);

    testWidgets('zero number and nothing listed: To do 0 as before; nonzero unchanged', (t) async {
      final h = t.ensureSemantics();
      await open(t, []);
      expect(count(t), '0');
      expect(t.getSemantics(find.byKey(const Key('notif-chip-todo'))).label, '$kTodoChipSpoken, 0');
      h.dispose();
    }, skip: skip);

    testWidgets('nonzero number with a Could not read row: number and spoken number unchanged', (t) async {
      final h = t.ensureSemantics();
      await open(t, [ready(1), unreadable(2)]);
      expect(count(t), '1');
      expect(t.getSemantics(find.byKey(const Key('notif-chip-todo'))).label, '$kTodoChipSpoken, 1');
      h.dispose();
    }, skip: skip);

    testWidgets('heading counts equal the rows under them', (t) async {
      await open(t, [ready(1), ready(2), unreadable(3), cat(4), cat(5), cat(6)]);
      expect(find.text('$kHeadingToParse (2)'), findsOneWidget);
      expect(find.text('$kHeadingCouldNotRead (1)'), findsNothing); // F11
      expect(find.text('$kHeadingToCategorize (4)'), findsOneWidget); // 3 readable + 1 unreadable
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
    testWidgets('order: To parse, then To categorize with the unreadable row last inside it', (t) async {
      await open(t, [cat(4), unreadable(3), ready(1)]);
      double y(String text) => t.getTopLeft(find.text(text)).dy;
      expect(y('$kHeadingToParse (1)'), lessThan(y('$kHeadingToCategorize (2)')));
      expect(find.text('$kHeadingCouldNotRead (1)'), findsNothing);
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
