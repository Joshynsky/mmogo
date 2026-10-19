@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
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

/// [n] readable ready items, plus a gone one that never counts.
List<WaitingItem> _ready(int n) => [
      for (var i = 1; i <= n; i++)
        WaitingItem(
            id: heldIdFor(i),
            kind: WaitingKind.readyToParse,
            heldAt: kFakeNow.subtract(Duration(minutes: 30 * i))),
      WaitingItem(id: heldIdFor(900), kind: WaitingKind.gone, heldAt: kFakeNow),
    ];

Widget _bar(List<WaitingItem> items, List<List<WaitingItem>> calls,
        {double scale = 1.0, NotifChip chip = NotifChip.parse, bool wired = true}) =>
    MaterialApp(
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: WaitingSection(
            chip: chip,
            waiting: items,
            news: const [],
            now: kFakeNow,
            newsRowBuilder: (n) => const SizedBox(),
            actions: wired ? WaitingActions(onParseAll: calls.add) : const WaitingActions(),
          ),
        ),
      ),
    );

final _barF = find.byKey(const Key('parseAllBar'));

void main() {
  for (final n in [0, 1]) {
    testWidgets('hidden with $n readable item(s)', (t) async {
      _size(t, 360);
      await t.pumpWidget(_bar(_ready(n), []));
      expect(_barF, findsNothing);
    });
  }

  for (final n in [2, 3]) {
    testWidgets('$n readable: shown, runs directly with no question', (t) async {
      _size(t, 360);
      final calls = <List<WaitingItem>>[];
      await t.pumpWidget(_bar(_ready(n), calls));
      expect(find.text(parseAllBarLabel('$n')), findsOneWidget);
      await t.tap(_barF);
      await t.pumpAndSettle();
      expect(calls.length, 1);
      expect(calls.single.length, n);
      expect(calls.single.every((e) => e.kind == WaitingKind.readyToParse), isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }

  testWidgets('4 readable: asks with the real number; confirm runs once', (t) async {
    _size(t, 360);
    final calls = <List<WaitingItem>>[];
    await t.pumpWidget(_bar(_ready(4), calls));
    await t.tap(_barF);
    await t.pumpAndSettle();
    expect(find.text('Parse all 4 messages?'), findsOneWidget);
    expect(find.text(kParseAllBody), findsOneWidget);
    expect(calls, isEmpty);
    await t.tap(find.byKey(const Key('parseAllConfirm')));
    await t.pumpAndSettle();
    expect(calls.length, 1);
    expect(calls.single.length, 4);
  });

  testWidgets('cancel, scrim and Back do nothing', (t) async {
    _size(t, 360);
    final calls = <List<WaitingItem>>[];
    await t.pumpWidget(_bar(_ready(5), calls));
    await t.tap(_barF);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('parseAllCancel')));
    await t.pumpAndSettle();
    await t.tap(_barF);
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    await t.tap(_barF);
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(calls, isEmpty);
  });

  testWidgets('99+ counts data (12 ready): label is the count, the question shows 12', (t) async {
    _size(t, 360);
    final calls = <List<WaitingItem>>[];
    final items = waitingSet(WaitingDataSet.many, kFakeNow).items;
    await t.pumpWidget(_bar(items, calls));
    expect(find.text('Parse all (12)'), findsOneWidget);
    await t.tap(_barF);
    await t.pumpAndSettle();
    expect(find.text('Parse all 12 messages?'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('more than 99 readable: label says 99+, question the real number', (t) async {
    _size(t, 360);
    final items = [
      for (var i = 1; i <= 105; i++)
        WaitingItem(
            id: heldIdFor(i),
            kind: WaitingKind.readyToParse,
            heldAt: kFakeNow.subtract(Duration(minutes: i))),
    ];
    await t.pumpWidget(_bar(items, []));
    expect(find.text('Parse all (99+)'), findsOneWidget);
    await t.tap(_barF);
    await t.pumpAndSettle();
    expect(find.text('Parse all 105 messages?'), findsOneWidget);
  });

  testWidgets('All chip: the bar sits under To parse; not wired means no bar', (t) async {
    _size(t, 360);
    final items = _ready(3);
    await t.pumpWidget(_bar(items, [], chip: NotifChip.all));
    expect(_barF, findsOneWidget);
    expect(t.getTopLeft(_barF).dy,
        lessThan(t.getTopLeft(find.byKey(Key('waiting-row-${heldIdFor(1)}'))).dy));
    await t.pumpWidget(_bar(items, [], chip: NotifChip.all, wired: false));
    expect(_barF, findsNothing);
  });

  for (final w in [360.0, 390.0]) {
    testWidgets('text 1.3 at $w px: no overflow, 44 px target, spoken name', (t) async {
      _size(t, w);
      final h = t.ensureSemantics();
      final items = waitingSet(WaitingDataSet.many, kFakeNow).items;
      await t.pumpWidget(_bar(items, [], scale: 1.3));
      expect(t.takeException(), isNull);
      expect(t.getSize(_barF).height, greaterThanOrEqualTo(44));
      expect(t.getBottomRight(_barF).dx, lessThanOrEqualTo(w));
      expect(find.bySemanticsLabel(parseAllBarSpoken(12)), findsOneWidget);
      await t.tap(_barF);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byKey(const Key('parseAllConfirm'))).height, greaterThanOrEqualTo(44));
      h.dispose();
    });
  }
}
