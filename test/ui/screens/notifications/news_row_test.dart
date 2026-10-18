// F2b: the shared NewsRow (and the NotifRowShell it uses). No auto-read words.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/news_item.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';
import 'package:mmogo/ui/screens/notifications/news_row.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/notif_colors.dart';
import 'package:mmogo/ui/widgets/notif_shape_icon.dart';

final DateTime _now = DateTime(2026, 10, 18, 10, 0);

Widget host(Widget child, {String palette = 'ocean', String mode = 'light', double scale = 1.0}) {
  return AppPaletteScope(
    controller: AppPaletteController(palette, mode),
    child: MaterialApp(
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child)),
      ),
    ),
  );
}

void size360(WidgetTester t) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = const Size(360, 800);
  addTearDown(t.view.reset);
}

NewsItem item(NewsKind k, {bool read = false, String title = 'A title', Duration age = const Duration(hours: 3)}) =>
    NewsItem(id: 'n-${k.name}', kind: k, title: title, createdAt: _now.subtract(age), readAt: read ? _now : null);

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final kind in NewsKind.values) {
    for (final read in [false, true]) {
      final name = '${kind.name} ${read ? 'read' : 'unread'}';
      testWidgets('$name: icon, weight, dot, age line, action, semantics', (t) async {
        final h = t.ensureSemantics();
        var calls = <String>[];
        final it = item(kind, read: read, title: 'T $name');
        await t.pumpWidget(host(NewsRow(
          it,
          _now,
          onRead: () => calls.add('read'),
          onUpdate: () => calls.add('update'),
          onDismiss: () => calls.add('dismiss'),
          onRemove: () => calls.add('remove'),
          onOpen: () => calls.add('open'),
        )));

        final icon = t.widget<NotifShapeIcon>(find.byType(NotifShapeIcon));
        expect(icon.shape, kind == NewsKind.notice ? NotifShape.star : NotifShape.arrow);

        final title = t.widget<Text>(find.byWidgetPredicate((w) => w is Text && w.textSpan != null));
        expect(title.style!.fontWeight, read ? FontWeight.w500 : FontWeight.w800);
        expect(find.byKey(const Key('notifRowUnreadDot')), read ? findsNothing : findsOneWidget);
        expect(find.byKey(const Key('notifRowDimIcon')), read ? findsOneWidget : findsNothing);
        final p = AppPalette.light;
        expect(title.style!.color, read ? p.mutedInk : p.ink);

        expect(find.text(read ? '3 h ago$kNewsAgeReadSuffix' : '3 h ago'), findsOneWidget);

        // spoken label: the prefix from styleFor, then the title and the age
        final prefix = read
            ? {NewsKind.notice: kSpokenReadNotice, NewsKind.update: kSpokenReadUpdate, NewsKind.whatsNew: kSpokenReadWhatsNew}[kind]!
            : {NewsKind.notice: kSpokenNewNotice, NewsKind.update: kSpokenUpdateAvailable, NewsKind.whatsNew: kSpokenNewWhatsNew}[kind]!;
        expect(find.bySemanticsLabel('$prefix. T $name. 3 hours ago${read ? ' · Read' : ''}.'), findsOneWidget);

        if (read) {
          expect(find.text(kNewsActionRemove), findsOneWidget);
          expect(find.text(kNewsActionRead), findsNothing);
          expect(find.text(kNewsActionDismiss), findsNothing);
          expect(find.text(kNewsActionUpdate), findsNothing);
          await t.tap(find.text(kNewsActionRemove));
          expect(calls, ['remove']);
        } else {
          final main = kind == NewsKind.update ? kNewsActionUpdate : kNewsActionRead;
          expect(find.text(main), findsOneWidget);
          expect(find.text(kNewsActionDismiss), findsOneWidget);
          expect(find.text(kNewsActionRemove), findsNothing);
          expect(find.bySemanticsLabel('$main: T $name'), findsOneWidget);
          await t.tap(find.text(main));
          expect(calls, [kind == NewsKind.update ? 'update' : 'read']);
          await t.tap(find.text(kNewsActionDismiss));
          expect(calls.last, 'dismiss');
        }
        calls = [];
        await t.tap(find.textContaining('T $name', findRichText: true));
        expect(calls, ['open']);
        h.dispose();
      });
    }
  }

  testWidgets('a row with no callbacks does not throw', (t) async {
    await t.pumpWidget(host(NewsRow(item(NewsKind.notice), _now)));
    await t.tap(find.text(kNewsActionRead));
    expect(t.takeException(), isNull);
  });

  for (final scale in [1.0, 1.3]) {
    for (final kind in NewsKind.values) {
      testWidgets('360 px, text x$scale, long title: ${kind.name} no overflow, 44 px targets', (t) async {
        size360(t);
        final long = 'Mwangi Wanjiku Kiprotich Odhiambo Achieng Wambui Njoroge Cherono ' * 2;
        await t.pumpWidget(host(
          Column(children: [
            NewsRow(item(NewsKind.values[kind.index], title: long), _now, onRead: () {}, onUpdate: () {}, onDismiss: () {}),
            NewsRow(item(NewsKind.values[kind.index], read: true, title: long), _now, onRemove: () {}),
          ]),
          scale: scale,
        ));
        expect(t.takeException(), isNull);
        final wells = find.byType(InkWell);
        expect(wells, findsNWidgets(3));
        for (final e in wells.evaluate()) {
          final s = t.getSize(find.byElementPredicate((x) => x == e));
          expect(s.width, greaterThanOrEqualTo(44));
          expect(s.height, greaterThanOrEqualTo(44));
        }
      });
    }
  }

  group('contrast of row title and subtitle text on the row surface', () {
    final sets = <String, AppPalette>{
      'ocean light': AppPalette.light,
      'ocean dark': AppPalette.dark,
      'leaf light': AppPalette.leafLight,
      'leaf dark': AppPalette.leafDark,
      'indigo light': AppPalette.indigoLight,
      'indigo dark': AppPalette.indigoDark,
    };
    for (final e in sets.entries) {
      final p = e.value;
      test('${e.key}: title (ink) and age/subtitle (mutedInk) on surface >= 4.5:1', () {
        expect(_ratio(p.ink, p.surface), greaterThanOrEqualTo(4.5));
        expect(_ratio(p.mutedInk, p.surface), greaterThanOrEqualTo(4.5));
      });
      test('${e.key}: the faded icon of a read row stays >= 3:1 on surface', () {
        for (final s in [NotifShape.star, NotifShape.arrow]) {
          final faded = Color.alphaBlend(notifShapeColor(p, s).withValues(alpha: kReadIconOpacity), p.surface);
          final r = _ratio(faded, p.surface);
          expect(r, greaterThanOrEqualTo(3.0), reason: '$s ${r.toStringAsFixed(2)}:1');
        }
      });
      test('${e.key}: star and arrow icons on the row surface >= 4.5:1 (surface check)', () {
        for (final s in [NotifShape.star, NotifShape.arrow]) {
          final r = _ratio(notifShapeColor(p, s), p.surface);
          expect(r, greaterThanOrEqualTo(4.5), reason: '$s ${r.toStringAsFixed(2)}:1');
        }
      });
    }
  });

  test('the shared row file has no auto-read words and no autoread import', () {
    final src = File('lib/ui/screens/notifications/news_row.dart').readAsStringSync();
    expect(src, isNot(contains('autoread')));
    expect(RegExp('pars|waiting|sms', caseSensitive: false).hasMatch(src), isFalse);
  });
}
