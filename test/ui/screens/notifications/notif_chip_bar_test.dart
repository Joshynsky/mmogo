import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/screens/notifications/notif_chip_bar.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

List<NotifChipSpec> _chips({
  int all = 10,
  int parse = 3,
  int cat = 3,
  int news = 4,
}) => [
  NotifChipSpec(
    chip: NotifChip.all,
    label: 'All',
    spokenName: 'All',
    count: all,
  ),
  NotifChipSpec(
    chip: NotifChip.parse,
    label: 'Parse',
    spokenName: 'To parse',
    count: parse,
  ),
  NotifChipSpec(
    chip: NotifChip.categorize,
    label: 'Categorize',
    spokenName: 'To categorize',
    count: cat,
  ),
  NotifChipSpec(
    chip: NotifChip.news,
    label: 'News',
    spokenName: 'News',
    count: news,
  ),
];

Widget _wrap(
  List<NotifChipSpec> chips, {
  double width = 360,
  double scale = 1.0,
  NotifChip selected = NotifChip.all,
  ValueChanged<NotifChip>? onSelected,
}) => MaterialApp(
  theme: AppTheme.theme,
  home: MediaQuery(
    data: MediaQueryData(
      size: Size(width, 800),
      textScaler: TextScaler.linear(scale),
    ),
    child: Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: NotifChipBar(
          chips: chips,
          selected: selected,
          onSelected: onSelected ?? (_) {},
        ),
      ),
    ),
  ),
);

/// Makes the real viewport [width] wide (the MediaQuery alone does not).
void _size(WidgetTester t, double width) {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 800);
  addTearDown(t.view.reset);
}

Rect _r(WidgetTester t, NotifChip c) =>
    t.getRect(find.byKey(Key('notif-chip-${c.name}')));

void main() {
  for (final width in [360.0, 390.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('four chips fit one row at $width px, scale $scale', (
        t,
      ) async {
        _size(t, width);
        await t.pumpWidget(
          _wrap(_chips(all: 150, news: 120), width: width, scale: scale),
        );
        expect(t.takeException(), isNull);
        final rects = [for (final c in NotifChip.values) _r(t, c)];
        for (final r in rects) {
          expect(r.top, rects.first.top);
          expect(r.height, greaterThanOrEqualTo(44));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width));
        }
        for (var i = 1; i < rects.length; i++) {
          expect(rects[i].left, greaterThanOrEqualTo(rects[i - 1].right));
        }
        expect(find.text('99+'), findsNWidgets(2));
        expect(find.byType(Scrollable), findsNothing);
        if (scale == 1.3) expect(rects.first.height, 44);
      });
    }
  }

  testWidgets('selected chip semantics and spoken name', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_wrap(_chips(), selected: NotifChip.parse));
    final node = t.getSemantics(find.byKey(const Key('notif-chip-parse')));
    expect(node.label, 'To parse, 3');
    expect(node.flagsCollection.isSelected == Tristate.isTrue, isTrue);
    final other = t.getSemantics(find.byKey(const Key('notif-chip-news')));
    expect(other.label, 'News, 4');
    expect(other.flagsCollection.isSelected == Tristate.isTrue, isFalse);
    h.dispose();
  });

  testWidgets('zero-count chip is dimmed but tappable', (t) async {
    NotifChip? got;
    await t.pumpWidget(_wrap(_chips(cat: 0), onSelected: (c) => got = c));
    final opacity = t.widget<Opacity>(
      find.descendant(
        of: find.byKey(const Key('notif-chip-categorize')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, lessThan(1));
    await t.tap(find.byKey(const Key('notif-chip-categorize')));
    expect(got, NotifChip.categorize);
  });

  testWidgets('tap calls onSelected', (t) async {
    NotifChip? got;
    await t.pumpWidget(_wrap(_chips(), onSelected: (c) => got = c));
    await t.tap(find.byKey(const Key('notif-chip-news')));
    expect(got, NotifChip.news);
  });

  testWidgets('fewer than two chips renders nothing', (t) async {
    await t.pumpWidget(_wrap([_chips()[3]]));
    expect(find.byKey(const Key('notif-chip-news')), findsNothing);
    await t.pumpWidget(_wrap(const []));
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('count beside the label at 1.0, under it above 1.15', (t) async {
    await t.pumpWidget(_wrap(_chips()));
    var label = t.getRect(
      find.descendant(
        of: find.byKey(const Key('notif-chip-parse')),
        matching: find.text('Parse'),
      ),
    );
    var count = t.getRect(find.byKey(const Key('notif-chip-count-parse')));
    expect(count.left, greaterThanOrEqualTo(label.right));
    expect((count.center.dy - label.center.dy).abs(), lessThan(3));

    await t.pumpWidget(_wrap(_chips(), scale: 1.3));
    label = t.getRect(
      find.descendant(
        of: find.byKey(const Key('notif-chip-parse')),
        matching: find.text('Parse'),
      ),
    );
    count = t.getRect(find.byKey(const Key('notif-chip-count-parse')));
    expect(count.top, greaterThanOrEqualTo(label.bottom - 1));
    expect(_r(t, NotifChip.parse).height, 44);
  });
}
