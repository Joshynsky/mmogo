import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/notifications/news_heading_bar.dart';

Widget _wrap({
  required int count,
  bool read = false,
  ValueChanged<bool>? on,
  double scale = 1.0,
}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(360, 640), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: NewsHeadingBar(
                unreadCount: count, readView: read, onChanged: on ?? (_) {}),
          ),
        ),
      ),
    );

void main() {
  testWidgets('shows unread count and 99+ cap', (t) async {
    await t.pumpWidget(_wrap(count: 3));
    expect(find.text('News (3)'), findsOneWidget);
    await t.pumpWidget(_wrap(count: 150));
    expect(find.text('News (99+)'), findsOneWidget);
  });

  testWidgets('count stays unread count in Read view', (t) async {
    await t.pumpWidget(_wrap(count: 2, read: true));
    expect(find.text('News (2)'), findsOneWidget);
  });

  testWidgets('taps call onChanged', (t) async {
    final calls = <bool>[];
    await t.pumpWidget(_wrap(count: 1, on: calls.add));
    await t.tap(find.text('Read'));
    await t.tap(find.text('Unread'));
    expect(calls, [true, false]);
  });

  testWidgets('selected semantics', (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(_wrap(count: 1));
    final unread = t.getSemantics(find.text('Unread'));
    final read = t.getSemantics(find.text('Read'));
    expect(unread.label, 'Unread');
    expect(read.label, 'Read');
    expect(unread.flagsCollection.isSelected == Tristate.isTrue, isTrue);
    expect(read.flagsCollection.isSelected == Tristate.isFalse, isTrue);
    expect(read.flagsCollection.isSelected != Tristate.none, isTrue);
    expect(read.flagsCollection.isButton, isTrue);
    expect(find.bySemanticsLabel('Show unread or read news'), findsOneWidget);
    h.dispose();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('one row, no overflow at 360 px, scale $scale', (t) async {
      await t.pumpWidget(_wrap(count: 150, scale: scale));
      expect(t.takeException(), isNull);
      final head = t.getRect(find.textContaining('News ('));
      final u = t.getRect(find.text('Unread'));
      final r = t.getRect(find.text('Read'));
      expect((head.center.dy - u.center.dy).abs() < 12, isTrue);
      expect((u.center.dy - r.center.dy).abs() < 1, isTrue);
      expect(t.getSize(find.byType(NewsHeadingBar)).height < 60, isTrue);
    });
  }

  testWidgets('options at least 44 px high', (t) async {
    await t.pumpWidget(_wrap(count: 1));
    for (final l in ['Unread', 'Read']) {
      final box = find
          .ancestor(of: find.text(l), matching: find.byType(ConstrainedBox))
          .first;
      expect(t.getSize(box).height >= 44, isTrue);
    }
  });
}
