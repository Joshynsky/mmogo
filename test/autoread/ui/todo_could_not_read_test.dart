// 0.2.2 item 2, U-TODO (B-3, F-1): unreadable messages leave To categorize and its count and sit
// under their own heading (kHeadingCouldNotRead) right after it. Text 200%, dark and light,
// screen-reader headings, RTL. Built on TodoSection with plain row builders.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/todo_section.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart' show kFakeNow;
import '../../support/waiting_fakes.dart';

void main() {
  WaitingItem cat(int n) => WaitingItem(
        id: heldIdFor(n),
        kind: WaitingKind.waitingCategory,
        heldAt: kFakeNow.subtract(Duration(minutes: n)),
        parsed: sampleFields(n, kFakeNow.subtract(Duration(minutes: n))),
      );
  WaitingItem unreadable(int n) =>
      WaitingItem(id: heldIdFor(n), kind: WaitingKind.unreadable, heldAt: kFakeNow.subtract(const Duration(hours: 2)));

  Future<void> pump(
    WidgetTester t,
    List<WaitingItem> items, {
    double scale = 1.0,
    bool dark = false,
    double width = 390,
    TextDirection dir = TextDirection.ltr,
    Widget? decision,
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = Size(width, 2400);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: dark ? AppTheme.forPalette(AppPalette.dark) : AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: dir, child: c!),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodoSection(
            waiting: items,
            now: kFakeNow,
            rowBuilder: (w) => Text('row-${w.id}', key: Key('row-${w.id}')),
            decision: decision,
          ),
        ),
      ),
    ));
  }

  double y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

  testWidgets('To categorize count excludes unreadable rows; the decision item still counts', (t) async {
    await pump(t, [cat(4), cat(5), unreadable(1), unreadable(2)], decision: const Text('DECISION'));
    expect(find.text('$kHeadingToCategorize (3)'), findsOneWidget); // 2 readable + 1 decision
    expect(find.text('$kHeadingCouldNotRead (2)'), findsOneWidget);
  });

  testWidgets('order: To categorize heading, its rows, then Could not read heading, then its rows', (t) async {
    await pump(t, [unreadable(1), cat(4), cat(5), unreadable(2)]);
    final catHead = y(t, find.text('$kHeadingToCategorize (2)'));
    final lastCat = [y(t, find.byKey(Key('row-${heldIdFor(4)}'))), y(t, find.byKey(Key('row-${heldIdFor(5)}')))]
        .reduce((a, b) => a > b ? a : b);
    final cnrHead = y(t, find.text('$kHeadingCouldNotRead (2)'));
    final firstUnread = [y(t, find.byKey(Key('row-${heldIdFor(1)}'))), y(t, find.byKey(Key('row-${heldIdFor(2)}')))]
        .reduce((a, b) => a < b ? a : b);
    expect(catHead, lessThan(lastCat));
    expect(lastCat, lessThan(cnrHead));
    expect(cnrHead, lessThan(firstUnread));
  });

  testWidgets('only unreadable: no empty To categorize heading, no quiet totals line', (t) async {
    await pump(t, [unreadable(1), unreadable(2)]);
    expect(find.textContaining(kHeadingToCategorize), findsNothing);
    expect(find.text(kWaitingNotCounted), findsNothing);
    expect(find.text('$kHeadingCouldNotRead (2)'), findsOneWidget);
  });

  testWidgets('no unreadable: no Could not read heading', (t) async {
    await pump(t, [cat(4)]);
    expect(find.textContaining(kHeadingCouldNotRead), findsNothing);
    expect(find.text('$kHeadingToCategorize (1)'), findsOneWidget);
  });

  testWidgets('screen reader: both headings are headers with their visible words', (t) async {
    final h = t.ensureSemantics();
    await pump(t, [cat(4), unreadable(1)]);
    expect(t.getSemantics(find.text('$kHeadingToCategorize (1)')),
        containsSemantics(label: '$kHeadingToCategorize (1)', isHeader: true));
    expect(t.getSemantics(find.text('$kHeadingCouldNotRead (1)')),
        containsSemantics(label: '$kHeadingCouldNotRead (1)', isHeader: true));
    h.dispose();
  });

  for (final dark in [false, true]) {
    for (final dir in TextDirection.values) {
      testWidgets('text 200%, dark $dark, ${dir.name}: no overflow, heading fully shown', (t) async {
        await pump(t, [cat(4), unreadable(1), unreadable(2)], scale: 2.0, dark: dark, width: 320, dir: dir);
        expect(t.takeException(), isNull);
        final head = find.text('$kHeadingCouldNotRead (2)');
        expect(head, findsOneWidget);
        final box = t.getRect(head);
        expect(box.left, greaterThanOrEqualTo(0));
        expect(box.right, lessThanOrEqualTo(320));
        expect(t.renderObject<RenderParagraph>(head).didExceedMaxLines, isFalse);
      });
    }
  }
}
