import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  for (final shape in NotifShape.values) {
    for (final size in [16.0, 20.0, 24.0]) {
      testWidgets('$shape paints at $size', (tester) async {
        await tester.pumpWidget(_host(NotifShapeIcon(shape: shape, color: Colors.teal, size: size)));
        expect(tester.takeException(), isNull);
        final box = tester.getSize(find.byType(NotifShapeIcon));
        expect(box.height, size);
        expect(box.width, size);
      });
    }
  }

  for (final c in [1, 9, 10, 99]) {
    testWidgets('pill with count $c', (tester) async {
      await tester.pumpWidget(_host(NotifShapeIcon(shape: NotifShape.pill, color: Colors.orange, count: c)));
      expect(tester.takeException(), isNull);
      final box = tester.getSize(find.byType(NotifShapeIcon));
      expect(box.height, 20);
      expect(box.width, greaterThanOrEqualTo(20));
    });
  }

  testWidgets('pill with caller-supplied 99+ is wider than a single digit', (tester) async {
    await tester.pumpWidget(_host(const NotifShapeIcon(shape: NotifShape.pill, color: Colors.orange, count: 1)));
    final one = tester.getSize(find.byType(NotifShapeIcon)).width;
    await tester.pumpWidget(_host(const NotifShapeIcon(shape: NotifShape.pill, color: Colors.orange, label: '99+')));
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(NotifShapeIcon)).width, greaterThan(one));
  });

  testWidgets('size follows text scale up to the cap', (tester) async {
    await tester.pumpWidget(_host(const NotifShapeIcon(shape: NotifShape.arrow, color: Colors.teal), textScale: 1.3));
    expect(tester.getSize(find.byType(NotifShapeIcon)).height, closeTo(20 * 1.15, 0.001));
    await tester.pumpWidget(_host(
      const NotifShapeIcon(shape: NotifShape.arrow, color: Colors.teal, scaleWithText: false),
      textScale: 1.3,
    ));
    expect(tester.getSize(find.byType(NotifShapeIcon)).height, 20);
  });

  testWidgets('semantics excluded by default, kept when asked', (tester) async {
    await tester.pumpWidget(_host(const NotifShapeIcon(shape: NotifShape.star, color: Colors.teal)));
    expect(find.descendant(of: find.byType(NotifShapeIcon), matching: find.byType(ExcludeSemantics)), findsOneWidget);
    await tester.pumpWidget(
      _host(const NotifShapeIcon(shape: NotifShape.star, color: Colors.teal, excludeSemantics: false)),
    );
    expect(find.descendant(of: find.byType(NotifShapeIcon), matching: find.byType(ExcludeSemantics)), findsNothing);
  });

  test('shouldRepaint reacts to every input', () {
    const base = NotifShapePainter(shape: NotifShape.pill, color: Colors.red, ink: Colors.white, text: '1');
    bool re(NotifShapePainter p) => base.shouldRepaint(p);
    expect(re(const NotifShapePainter(shape: NotifShape.pill, color: Colors.red, ink: Colors.white, text: '1')), isFalse);
    expect(re(const NotifShapePainter(shape: NotifShape.star, color: Colors.red, ink: Colors.white, text: '1')), isTrue);
    expect(re(const NotifShapePainter(shape: NotifShape.pill, color: Colors.blue, ink: Colors.white, text: '1')), isTrue);
    expect(re(const NotifShapePainter(shape: NotifShape.pill, color: Colors.red, ink: Colors.black, text: '1')), isTrue);
    expect(re(const NotifShapePainter(shape: NotifShape.pill, color: Colors.red, ink: Colors.white, text: '2')), isTrue);
  });

  test('icon file carries no auto-read words', () {
    final src = File('lib/ui/widgets/notif_shape_icon.dart').readAsStringSync();
    expect(RegExp('pars|waiting|sms', caseSensitive: false).hasMatch(src), isFalse);
  });
}
