// 0.2.2 S-C (F10/F11): the To do page order and list contents, on TodoSection with plain builders.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart' show ReceiverType;
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart' show kHardRecentlyRecorded;
import 'package:mmogo/autoread/ui/notifications/recorded_auto_section.dart';
import 'package:mmogo/autoread/ui/notifications/suggestion_card.dart';
import 'package:mmogo/autoread/ui/notifications/notifications_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/todo_section.dart';
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
  WaitingItem ready(int n) =>
      WaitingItem(id: heldIdFor(n), kind: WaitingKind.readyToParse, heldAt: kFakeNow.subtract(Duration(hours: n)));

  Future<void> pump(WidgetTester t, List<WaitingItem> items,
      {bool toChoose = true, int offerCount = 3, List<AutoRecorded> trail = const []}) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(390, 2400);
    addTearDown(t.view.reset);
    final offers = [for (var i = 0; i < offerCount; i++) Offer(type: ReceiverType.sendMoney, key: 'p$i', categoryId: 1, name: 'NAME$i', run: 3)];
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: TodoSection(
            waiting: items,
            now: kFakeNow,
            rowBuilder: (w) => Text('row-${w.id}', key: Key('row-${w.id}')),
            isAskFirst: (w) => w.id == heldIdFor(9),
            toChoose: toChoose ? const Text('TO-CHOOSE') : null,
            hasToChoose: toChoose,
            suggestions: offers.isEmpty
                ? null
                : SuggestionsSection(offers: offers, categoryName: (_) => 'Fuel', onNotNow: (_) {}, onConfirm: (_) {}),
            hasSuggestions: offers.isNotEmpty,
            trail: trail.isEmpty
                ? null
                : RecordedAutoSection(entries: trail, now: kFakeNow, onUndo: (_) {}, onChangeInSettings: () {}),
            hasTrail: trail.isNotEmpty,
          ),
        ),
      ),
    ));
  }

  double y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

  testWidgets('order: To confirm, To parse, To choose, Suggestions, To categorize, Could not read, Recorded automatically last', (t) async {
    final trail = [
      AutoRecorded(rowId: 5, amountCents: 50000, at: kFakeNow.subtract(const Duration(minutes: 3)), partyLabel: 'JOHN D', categoryName: 'Fuel'),
    ];
    await pump(t, [cat(9), ready(1), cat(4), unreadable(3)], trail: trail);
    final order = [
      y(t, find.text('$kHeadingToConfirm (1)')),
      y(t, find.text('$kHeadingToParse (1)')),
      y(t, find.text('TO-CHOOSE')),
      y(t, find.text('$kHeadingSuggestions (3)')),
      y(t, find.text('$kHeadingToCategorize (1)')),
      y(t, find.text('$kHeadingCouldNotRead (1)')),
      y(t, find.text('$kHardRecentlyRecorded (1)')),
    ];
    expect(order, [...order]..sort());
    expect(order.toSet(), hasLength(7));
  });

  // 0.2.2 item 2 (B-3, F-1): unreadable rows left To categorize; they sit under their own heading after it.
  testWidgets('Suggestions is ONE card with "2 more"; unreadable row is under Could not read, after To categorize', (t) async {
    await pump(t, [cat(4), unreadable(3)], toChoose: false);
    expect(find.byKey(const Key('suggestion-confirm')), findsOneWidget);
    expect(find.text('2 more'), findsOneWidget);
    expect(find.text('$kHeadingToCategorize (1)'), findsOneWidget); // count excludes the unreadable row
    expect(find.text('$kHeadingCouldNotRead (1)'), findsOneWidget);
    expect(y(t, find.byKey(Key('row-${heldIdFor(4)}'))), lessThan(y(t, find.text('$kHeadingCouldNotRead (1)'))));
    expect(y(t, find.text('$kHeadingCouldNotRead (1)')), lessThan(y(t, find.byKey(Key('row-${heldIdFor(3)}')))));
  });

  testWidgets('only an unreadable message: Could not read (1), no empty To categorize heading', (t) async {
    await pump(t, [unreadable(3)], toChoose: false, offerCount: 0);
    expect(find.textContaining(kHeadingToCategorize), findsNothing);
    expect(find.text(kWaitingNotCounted), findsNothing);
    expect(find.text('$kHeadingCouldNotRead (1)'), findsOneWidget);
    expect(find.byKey(Key('row-${heldIdFor(3)}')), findsOneWidget);
  });

  testWidgets('list shows a chip entry as "Recorded as Fuel." with Undo and no Change in Settings; airtime keeps its words', (t) async {
    final trail = [
      AutoRecorded(rowId: 5, amountCents: 50000, at: kFakeNow.subtract(const Duration(minutes: 3)), partyLabel: 'JOHN D', categoryName: 'Fuel'),
      AutoRecorded(rowId: 6, amountCents: 500, at: kFakeNow.subtract(const Duration(minutes: 9))),
    ];
    await pump(t, const [], toChoose: false, offerCount: 0, trail: trail);
    expect(find.text('JOHN D, Ksh 500'), findsOneWidget);
    expect(find.text('Recorded as Fuel.'), findsOneWidget);
    expect(find.text(kAutoRecordedSub), findsOneWidget);
    expect(find.text(kAutoRecordedUndo), findsNWidgets(2));
    expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
  });
}
