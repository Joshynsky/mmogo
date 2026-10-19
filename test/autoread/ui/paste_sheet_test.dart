@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/paste_sheet.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 900);
  addTearDown(t.view.reset);
}

Widget _host({required VoidCallback onGo, double scale = 1.0}) => MaterialApp(
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showPasteSheet(c, onContinueToAdd: onGo),
          child: const Text('open'),
        ),
      ),
    );

Future<void> _open(WidgetTester t) async {
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('Continue calls once, even on a double tap, then closes', (t) async {
    _size(t, 360);
    var n = 0;
    await t.pumpWidget(_host(onGo: () => n++));
    await _open(t);
    expect(find.text(kPasteSheetHeading), findsOneWidget);
    expect(find.text('Copy the M-Pesa message first, then continue to Add.'), findsOneWidget);
    final b = find.byKey(const Key('pasteContinue'));
    await t.tap(b);
    await t.tap(b, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(n, 1);
    expect(find.text(kPasteSheetHeading), findsNothing);
    // The route below is still there (not popped twice).
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('"Already copied it?" also goes to Add once', (t) async {
    _size(t, 360);
    var n = 0;
    await t.pumpWidget(_host(onGo: () => n++));
    await _open(t);
    await t.tap(find.byKey(const Key('pasteGoStraight')));
    await t.pumpAndSettle();
    expect(n, 1);
  });

  testWidgets('Close, scrim and Back call nothing', (t) async {
    _size(t, 360);
    var n = 0;
    await t.pumpWidget(_host(onGo: () => n++));
    await _open(t);
    await t.tap(find.byKey(const Key('pasteClose')));
    await t.pumpAndSettle();
    expect(find.text(kPasteSheetHeading), findsNothing);
    await _open(t);
    await t.tapAt(const Offset(180, 20));
    await t.pumpAndSettle();
    expect(find.text(kPasteSheetHeading), findsNothing);
    await _open(t);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text(kPasteSheetHeading), findsNothing);
    expect(n, 0);
  });

  testWidgets('Paste on a gone row opens the sheet and Continue calls onPaste', (t) async {
    _size(t, 360);
    final pasted = <String>[];
    final items = waitingSet(WaitingDataSet.typical, kFakeNow).items;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            chip: NotifChip.parse,
            waiting: items,
            news: const [],
            now: kFakeNow,
            newsRowBuilder: (n) => const SizedBox(),
            actions: WaitingActions(onPaste: (w) => pasted.add(w.id)),
          ),
        ),
      ),
    ));
    await t.tap(find.descendant(
      of: find.byKey(Key('waiting-row-${heldIdFor(4)}')),
      matching: find.text(kActionPaste),
    ));
    await t.pumpAndSettle();
    expect(pasted, isEmpty);
    await t.tap(find.byKey(const Key('pasteContinue')));
    await t.pumpAndSettle();
    expect(pasted, [heldIdFor(4)]);
  });

  for (final w in [360.0, 390.0]) {
    testWidgets('text 1.3 at $w px: no overflow, 44 px targets, spoken names', (t) async {
      _size(t, w);
      final h = t.ensureSemantics();
      await t.pumpWidget(_host(onGo: () {}, scale: 1.3));
      await _open(t);
      expect(t.takeException(), isNull);
      for (final k in ['pasteContinue', 'pasteGoStraight', 'pasteClose']) {
        final s = t.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.byTooltip(kPasteClose), findsOneWidget);
      expect(find.bySemanticsLabel(kPasteContinue), findsOneWidget);
      h.dispose();
    });
  }
}
