@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/remove_confirm.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart';
import '../../support/waiting_fakes.dart';

Widget _host(Widget child, {double scale = 1.0}) => MaterialApp(
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 900);
  addTearDown(t.view.reset);
}

WaitingItem _gone() => WaitingItem(id: heldIdFor(4), kind: WaitingKind.gone, heldAt: kFakeNow);

Widget _section(List<WaitingItem> items, List<WaitingItem> removed, {double scale = 1.0}) => _host(
      WaitingSection(
        chip: NotifChip.parse,
        waiting: items,
        news: const [],
        now: kFakeNow,
        newsRowBuilder: (n) => const SizedBox(),
        actions: WaitingActions(onRemove: removed.add),
      ),
      scale: scale,
    );

Finder _removeLink() => find.descendant(
      of: find.byKey(Key('waiting-row-${heldIdFor(4)}')),
      matching: find.text(kActionRemove),
    );

void main() {
  testWidgets('Confirm true: onRemove called once; wording from the mock', (t) async {
    _size(t, 360);
    final removed = <WaitingItem>[];
    final items = waitingSet(WaitingDataSet.typical, kFakeNow).items;
    await t.pumpWidget(_section(items, removed));
    await t.tap(_removeLink());
    await t.pumpAndSettle();
    expect(find.text(kRemoveTitle), findsOneWidget);
    expect(find.text(kRemoveBody), findsOneWidget);
    expect(removed, isEmpty);
    await t.tap(find.byKey(const Key('removeConfirm')));
    await t.pumpAndSettle();
    expect(removed.map((e) => e.id), [heldIdFor(4)]);
    expect(find.text(kRemoveTitle), findsNothing);
  });

  testWidgets('Cancel, scrim and Back never call onRemove', (t) async {
    _size(t, 360);
    final removed = <WaitingItem>[];
    final items = waitingSet(WaitingDataSet.typical, kFakeNow).items;
    await t.pumpWidget(_section(items, removed));

    await t.tap(_removeLink());
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('removeCancel')));
    await t.pumpAndSettle();
    expect(find.text(kRemoveTitle), findsNothing);

    await t.tap(_removeLink());
    await t.pumpAndSettle();
    await t.tapAt(const Offset(5, 5)); // scrim
    await t.pumpAndSettle();
    expect(find.text(kRemoveTitle), findsNothing);

    await t.tap(_removeLink());
    await t.pumpAndSettle();
    await t.binding.handlePopRoute(); // system Back
    await t.pumpAndSettle();
    expect(find.text(kRemoveTitle), findsNothing);
    expect(removed, isEmpty);
  });

  testWidgets('showRemoveConfirm returns false on Cancel and true on Remove', (t) async {
    _size(t, 360);
    bool? result;
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await showRemoveConfirm(c, item: _gone()),
          child: const Text('go'),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('removeCancel')));
    await t.pumpAndSettle();
    expect(result, isFalse);
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('removeConfirm')));
    await t.pumpAndSettle();
    expect(result, isTrue);
  });

  for (final w in [360.0, 390.0]) {
    testWidgets('text 1.3 at $w px: no overflow, 44 px targets, spoken names', (t) async {
      _size(t, w);
      final h = t.ensureSemantics();
      await t.pumpWidget(_section(waitingSet(WaitingDataSet.typical, kFakeNow).items, [], scale: 1.3));
      await t.tap(_removeLink());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      for (final k in ['removeCancel', 'removeConfirm']) {
        final s = t.getSize(find.byKey(Key(k)));
        expect(s.height, greaterThanOrEqualTo(44), reason: k);
        expect(s.width, greaterThanOrEqualTo(44), reason: k);
      }
      expect(find.bySemanticsLabel(kRemoveCancel), findsOneWidget);
      expect(find.bySemanticsLabel(kRemoveConfirm), findsOneWidget);
      h.dispose();
    });
  }

  testWidgets('the row link is spoken as "Remove this message"', (t) async {
    _size(t, 360);
    final h = t.ensureSemantics();
    await t.pumpWidget(_section(waitingSet(WaitingDataSet.typical, kFakeNow).items, []));
    expect(find.bySemanticsLabel('$kActionRemove this message'), findsOneWidget);
    h.dispose();
  });
}
