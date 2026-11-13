// The held-message description on the row and in the Details sheet (autoread
// build). Invented values only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/message_details.dart';
import 'package:mmogo/autoread/model/held_description.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/held_row_describer.dart';
import 'package:mmogo/autoread/ui/message_details_sheet.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/unreadable_copy.dart';
import 'package:mmogo/autoread/ui/waiting_row.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../support/waiting_fakes.dart' show heldIdFor;

final DateTime _now = DateTime(2026, 11, 13, 14, 0);
const String kSentinel = 'zebraquartz';

WaitingItem _held(WaitingKind k, {int n = 1}) =>
    WaitingItem(id: heldIdFor(n), kind: k, heldAt: _now.subtract(const Duration(hours: 4)));

Widget _host(Widget child, {String mode = 'light', double scale = 1.0}) => AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child))),
      ),
    );

void _size(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(360, 800);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Iterable<String> _texts(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText))
    .map((w) => w.text.toPlainText());

void main() {
  group('ready row', () {
    testWidgets('described: the description is the title, the fine line is under it; spoken label has it', (t) async {
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(WaitingRow(_held(WaitingKind.readyToParse), _now,
          description: const HeldDescription(what: 'Sent Ksh 200 to Wanjiru Kamau'), onParse: () {})));
      expect(find.text('Sent Ksh 200 to Wanjiru Kamau'), findsOneWidget);
      expect(find.text(kReadyRowFine), findsOneWidget);
      expect(find.text(kReadyRowTitle), findsNothing);
      expect(find.bySemanticsLabel(RegExp(r'^Ready to parse\. Sent Ksh 200 to Wanjiru Kamau\. ')), findsOneWidget);
      // No digit in the spoken label other than the description's own and the age/expiry words.
      final label = t.getSemantics(find.byType(WaitingRow)).label;
      final extra = RegExp(r'\d+').allMatches(label).map((m) => m.group(0)).toSet()
        ..removeAll(['200', '4', '20']);
      expect(extra, isEmpty, reason: label);
      h.dispose();
    });

    testWidgets('no description (failed or busy look): the plain title, no fine line', (t) async {
      await t.pumpWidget(_host(WaitingRow(_held(WaitingKind.readyToParse), _now, onParse: () {})));
      expect(find.text(kReadyRowTitle), findsOneWidget);
      expect(find.text(kReadyRowFine), findsNothing);
    });
  });

  group('unreadable row', () {
    Future<void> pump(WidgetTester t, HeldDescription? d, {double scale = 1.0, String mode = 'light'}) async {
      _size(t);
      await t.pumpWidget(_host(
          WaitingRow(_held(WaitingKind.unreadable), _now, description: d, onDetails: () {}, onRemove: () {}),
          scale: scale, mode: mode));
    }

    testWidgets('code, amount, time: the mock subline; Details and Remove; no Paste; tap row opens Details', (t) async {
      var opened = 0;
      _size(t);
      await t.pumpWidget(_host(WaitingRow(_held(WaitingKind.unreadable), _now,
          description: const HeldDescription(code: 'UFGH123456', amount: 'Ksh 5', time: '14:08'),
          onDetails: () => opened++,
          onRemove: () {})));
      expect(find.text(kUnreadableTitle), findsOneWidget);
      expect(find.text('UFGH123456 · Ksh 5 · 14:08. $kUnreadableTapHint'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.text(kActionRemove), findsOneWidget);
      expect(find.text(kActionPaste), findsNothing);
      await t.tap(find.text(kUnreadableTitle));
      expect(opened, 1);
    });

    testWidgets('fallbacks: code only, amount only, time missing, neither (time it arrived)', (t) async {
      for (final (d, line) in <(HeldDescription?, String)>[
        (const HeldDescription(code: 'UFGH123456'), 'UFGH123456.'),
        (const HeldDescription(amount: 'Ksh 5'), 'Ksh 5.'),
        (const HeldDescription(code: 'UFGH123456', amount: 'Ksh 5'), 'UFGH123456 · Ksh 5.'),
        (null, 'Received 10:00.'),
        (const HeldDescription(), 'Received 10:00.'),
      ]) {
        await pump(t, d);
        expect(find.text('$line $kUnreadableTapHint'), findsOneWidget, reason: line);
      }
    });

    for (final scale in [1.0, 1.3]) {
      for (final mode in ['light', 'dark']) {
        testWidgets('360 px, text $scale, $mode: no overflow, 44 px targets', (t) async {
          await pump(t, const HeldDescription(code: 'UFGH123456', amount: 'Ksh 1,250.50', time: '14:08'),
              scale: scale, mode: mode);
          expect(t.takeException(), isNull);
          for (final e in find.byType(InkWell).evaluate()) {
            final s = t.getSize(find.byElementPredicate((x) => x == e));
            expect(s.height, greaterThanOrEqualTo(44));
            expect(s.width, greaterThanOrEqualTo(44));
          }
        });
      }
    }
  });

  group('unreadable Details sheet', () {
    testWidgets('code, amount, time, time left; Not found for gaps; no body words; Remove then Close', (t) async {
      _size(t);
      final d = buildMessageDetails(_held(WaitingKind.unreadable), _now,
          light: const HeldDescription(code: 'UFGH123456'));
      var removed = 0;
      await t.pumpWidget(_host(Builder(
          builder: (c) => TextButton(
              onPressed: () => showMessageDetailsSheet(c, details: d, onRemove: () => removed++),
              child: const Text('open')))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text(kUnreadableCodeLabel), findsOneWidget);
      expect(find.text('UFGH123456'), findsOneWidget);
      expect(find.text(kNotFound), findsNWidgets(2)); // amount and time
      expect(find.text(kDetailsTimeLeftLabel), findsOneWidget);
      expect(find.text(kUnreadablePasteWithCode), findsOneWidget);
      expect(find.text(kUnreadableFine), findsOneWidget);
      final all = _texts(t).join('|');
      for (final gone in ['First words', 'What failed', 'left out on purpose', kSentinel]) {
        expect(all.contains(gone), isFalse, reason: gone);
      }
      await t.tap(find.byKey(const Key('detailsRemove')));
      await t.pumpAndSettle();
      expect(removed, 1);
    });

    testWidgets('no code: the "look for a message sent at" sentence, no Remove without a callback', (t) async {
      _size(t);
      final d = buildMessageDetails(_held(WaitingKind.unreadable), _now, light: const HeldDescription(time: '14:08'));
      await t.pumpWidget(_host(Builder(
          builder: (c) => TextButton(onPressed: () => showMessageDetailsSheet(c, details: d), child: const Text('open')))));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('$kUnreadablePasteNoCodePrefix 14:08.'), findsOneWidget);
      expect(find.byKey(const Key('detailsRemove')), findsNothing);
    });
  });

  group('HeldRowDescriber: lifetime on screen', () {
    testWidgets('one look per row on show; dropped on pause and the repository told; looks again on resume', (t) async {
      final looks = <String>[];
      var cleared = 0;
      final item = _held(WaitingKind.readyToParse);
      await t.pumpWidget(_host(HeldRowDescriber(
        item: item,
        describe: (i) async {
          looks.add(i.id);
          return const HeldDescription(what: 'Sent Ksh 200');
        },
        clear: () => cleared++,
        builder: (c, d) => Text(d?.what ?? 'plain'),
      )));
      await t.pump();
      expect(looks.length, 1);
      expect(find.text('Sent Ksh 200'), findsOneWidget);

      // Leaving the app: the first step (frames still paint) shows the plain title.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
      expect(find.text('plain'), findsOneWidget);
      expect(cleared, 0); // inactive only masks; nothing is forgotten yet
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      expect(find.text('Sent Ksh 200'), findsOneWidget);
      expect(looks.length, 1);

      // Backgrounded: the repository is told, and coming back looks again.
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(cleared, greaterThanOrEqualTo(1));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await t.pump();
      await t.pump();
      expect(looks.length, 2);
      expect(find.text('Sent Ksh 200'), findsOneWidget);
    });

    testWidgets('a pause while a look is running: the late answer is not shown', (t) async {
      final item = _held(WaitingKind.readyToParse);
      await t.pumpWidget(_host(HeldRowDescriber(
        item: item,
        describe: (i) async => const HeldDescription(what: 'LATE'),
        builder: (c, d) => Text(d?.what ?? 'plain'),
      )));
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await t.pump();
      await t.pump();
      expect(find.text('LATE'), findsNothing);
    });

    testWidgets('the last such row leaving clears the repository; a gone row is not asked', (t) async {
      var cleared = 0;
      var looks = 0;
      Widget rows(List<WaitingItem> items) => _host(Column(children: [
            for (final i in items)
              HeldRowDescriber(
                key: ValueKey(i.id),
                item: i,
                describe: (x) async {
                  looks++;
                  return null;
                },
                clear: () => cleared++,
                builder: (c, d) => Text(i.id.substring(28)),
              ),
          ]));
      await t.pumpWidget(rows([_held(WaitingKind.readyToParse, n: 1), _held(WaitingKind.readyToParse, n: 2)]));
      await t.pump();
      await t.pumpWidget(rows([_held(WaitingKind.readyToParse, n: 1)]));
      expect(cleared, 0);
      await t.pumpWidget(rows([]));
      expect(cleared, 1);
      await t.pumpWidget(rows([_held(WaitingKind.gone, n: 3)]));
      await t.pump();
      expect(looks, 2);
    });
  });
}
