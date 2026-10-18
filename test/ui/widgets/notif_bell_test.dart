import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/notif_bell.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';

Widget _host(Widget child, {double scale = 1.0}) => AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: c!,
        ),
        theme: ThemeData(fontFamily: 'Roboto'),
        home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
      ),
    );

NotifBell _bell({
  VoidCallback? onTap,
  bool arrow = false,
  bool star = false,
  int? pill,
  int? diamond,
  String label = 'Notifications',
}) =>
    NotifBell(onTap: onTap ?? () {}, spokenLabel: label, arrow: arrow, star: star, pillCount: pill, diamondCount: diamond);

Finder _shape(NotifShape s) => find.byWidgetPredicate((w) => w is NotifShapeIcon && w.shape == s);

/// The test font (Ahem) makes every glyph a full square, three times the real
/// width of "99+". Load the SDK's Roboto so the number widths are realistic.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/roboto-bold.ttf');
  if (!f.existsSync()) return;
  final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);
  void size360(WidgetTester t, {double w = 360}) {
    t.view.physicalSize = Size(w, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  group('each badge alone and all four', () {
    testWidgets('no badges', (t) async {
      await t.pumpWidget(_host(_bell()));
      expect(t.takeException(), isNull);
      expect(find.byType(NotifShapeIcon), findsNothing);
    });
    testWidgets('arrow alone', (t) async {
      await t.pumpWidget(_host(_bell(arrow: true)));
      expect(t.takeException(), isNull);
      expect(_shape(NotifShape.arrow), findsOneWidget);
      expect(find.byType(NotifShapeIcon), findsOneWidget);
    });
    testWidgets('star alone', (t) async {
      await t.pumpWidget(_host(_bell(star: true)));
      expect(t.takeException(), isNull);
      expect(_shape(NotifShape.star), findsOneWidget);
      expect(find.byType(NotifShapeIcon), findsOneWidget);
    });
    testWidgets('pill alone', (t) async {
      await t.pumpWidget(_host(_bell(pill: 3)));
      expect(t.takeException(), isNull);
      expect(_shape(NotifShape.pill), findsOneWidget);
      expect(find.byType(NotifShapeIcon), findsOneWidget);
    });
    testWidgets('diamond alone', (t) async {
      await t.pumpWidget(_host(_bell(diamond: 3)));
      expect(t.takeException(), isNull);
      expect(_shape(NotifShape.diamond), findsOneWidget);
      expect(find.byType(NotifShapeIcon), findsOneWidget);
    });
    testWidgets('all four together', (t) async {
      await t.pumpWidget(_host(_bell(arrow: true, star: true, pill: 5, diamond: 2)));
      expect(t.takeException(), isNull);
      expect(find.byType(NotifShapeIcon), findsNWidgets(4));
    });
    testWidgets('zero counts show nothing', (t) async {
      await t.pumpWidget(_host(_bell(pill: 0, diamond: 0)));
      expect(find.byType(NotifShapeIcon), findsNothing);
    });
  });

  group('numbers', () {
    for (final c in [(1, '1'), (9, '9'), (10, '10'), (99, '99'), (100, '99+'), (250, '99+')]) {
      testWidgets('pill and diamond show ${c.$2} for ${c.$1}', (t) async {
        await t.pumpWidget(_host(_bell(pill: c.$1, diamond: c.$1)));
        expect(t.takeException(), isNull);
        final pill = t.widget<NotifShapeIcon>(_shape(NotifShape.pill));
        expect(pill.label, c.$2);
        expect(find.byKey(const ValueKey('bell-diamond-number')), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const ValueKey('bell-diamond-number'))).data, c.$2);
      });
    }
  });

  group('geometry', () {
    testWidgets('diamond number sits left of the diamond and clears bell, star and pill', (t) async {
      await t.pumpWidget(_host(_bell(arrow: true, star: true, pill: 99, diamond: 99)));
      final num = t.getRect(find.byKey(const ValueKey('bell-diamond-number')));
      final dia = t.getRect(find.byKey(const ValueKey('bell-diamond')));
      final bell = t.getRect(find.byKey(const ValueKey('bell-circle')));
      final star = t.getRect(_shape(NotifShape.star));
      final pill = t.getRect(_shape(NotifShape.pill));
      expect(num.right, lessThanOrEqualTo(dia.left));
      expect(num.overlaps(bell), isFalse);
      expect(num.overlaps(star), isFalse);
      expect(num.overlaps(pill), isFalse);
    });

    for (final c in [(1, 18.0), (9, 18.0), (10, 24.0), (99, 24.0), (100, 30.0)]) {
      testWidgets('left margin for ${c.$1} is ${c.$2}', (t) async {
        await t.pumpWidget(_host(_bell(diamond: c.$1)));
        final left = t.getRect(find.byKey(const ValueKey('bell-button'))).left;
        expect(left, c.$2);
      });
    }

    testWidgets('left margin grows with the digit count', (t) async {
      final lefts = <double>[];
      for (final n in [null, 5, 50, 500]) {
        await t.pumpWidget(_host(_bell(diamond: n)));
        lefts.add(t.getRect(find.byKey(const ValueKey('bell-button'))).left);
      }
      expect(lefts, [0, 18, 24, 30]);
    });

    testWidgets('margin follows text scale, capped at 1.15', (t) async {
      await t.pumpWidget(_host(_bell(diamond: 500), scale: 1.3));
      expect(t.getRect(find.byKey(const ValueKey('bell-button'))).left, closeTo(30 * 1.15, 0.001));
    });

    testWidgets('number is not clipped by the margin at 99+', (t) async {
      await t.pumpWidget(_host(_bell(diamond: 500), scale: 1.15));
      final num = t.getRect(find.byKey(const ValueKey('bell-diamond-number')));
      expect(num.left, greaterThanOrEqualTo(0));
    });
  });

  group('crowding frame', () {
    testWidgets('360 px, text scale 1.3, both counts 99+: no overflow, number clears the title', (t) async {
      size360(t);
      await t.pumpWidget(_host(
        Row(
          children: [
            const SizedBox(width: 16),
            const Expanded(
              child: Text('Good afternoon, Wanjiru,', key: ValueKey('title'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8), // the header's own gap
            _bell(arrow: true, star: true, pill: 120, diamond: 120),
            const SizedBox(width: 8),
          ],
        ),
        scale: 1.3,
      ));
      expect(t.takeException(), isNull);
      final title = t.getRect(find.byKey(const ValueKey('title')));
      final num = t.getRect(find.byKey(const ValueKey('bell-diamond-number')));
      final star = t.getRect(_shape(NotifShape.star));
      expect(title.right, lessThanOrEqualTo(num.left));
      expect(title.right, lessThanOrEqualTo(star.left));
    });
  });

  group('interaction and semantics', () {
    testWidgets('tap calls onTap', (t) async {
      var n = 0;
      await t.pumpWidget(_host(_bell(onTap: () => n++, pill: 2)));
      await t.tap(find.byKey(const ValueKey('bell-button')));
      expect(n, 1);
    });

    testWidgets('semantics label equals spokenLabel and badges add nothing', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(_host(_bell(label: 'Notifications, 1 update available', arrow: true, star: true, pill: 7, diamond: 3)));
      final node = t.getSemantics(find.byKey(const ValueKey('bell-button')));
      expect(node.label, 'Notifications, 1 update available');
      expect(node.flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel(RegExp(r'^[0-9]+\+?$')), findsNothing);
      handle.dispose();
    });

    testWidgets('tap target is at least 44 px', (t) async {
      await t.pumpWidget(_host(_bell(pill: 1)));
      final r = t.getRect(find.byKey(const ValueKey('bell-button')));
      expect(r.width, greaterThanOrEqualTo(44));
      expect(r.height, greaterThanOrEqualTo(44));
    });
  });

  test('source has no auto-read words and no autoread import', () {
    for (final f in ['lib/ui/widgets/notif_bell.dart', 'lib/ui/copy/bell_copy.dart']) {
      final src = File(f).readAsStringSync().toLowerCase();
      for (final w in ['parse', 'waiting', 'categor', 'sms', 'autoread']) {
        expect(src.contains(w), isFalse, reason: '$f contains "$w"');
      }
    }
  });
}
