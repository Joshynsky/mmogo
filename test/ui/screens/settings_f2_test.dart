// F2 (0.1.2 corrections), Settings: R37 palette card names wrap instead of
// being cut at large text, with no clipping on a 320 dp wide screen.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_delete_data.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(320, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AppPaletteScope(
        controller: AppPaletteController(),
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    useFakeDeleteData();
    SharedPreferences.setMockInitialValues({});
  });

  group('R37 palette card names', () {
    for (final scale in [1.0, 1.3, 1.6]) {
      testWidgets('x$scale on 320 dp: every name is shown whole (wrapped, not cut), tiles one height, no overflow', (tester) async {
        await _pump(tester, scale);
        expect(tester.takeException(), isNull, reason: 'no overflow stripe / layout error');
        final heights = <double>[];
        for (final id in ['ocean', 'leaf', 'indigo']) {
          final tile = find.byKey(Key('paletteTile-$id'));
          expect(tile, findsOneWidget);
          heights.add(tester.getSize(tile).height);
        }
        expect(heights.toSet(), hasLength(1), reason: 'the three tiles share one height: $heights');
        for (final name in ['Ocean & Sun', 'Leaf & Gold', 'Indigo & Peach']) {
          final f = find.text(name);
          expect(f, findsOneWidget);
          final p = tester.renderObject<RenderParagraph>(f);
          expect(p.didExceedMaxLines, isFalse, reason: '$name is not cut at x$scale');
          // The text sits inside its tile.
          final tileRect = tester.getRect(find.ancestor(of: f, matching: find.byType(InkWell)).first);
          expect(tileRect.contains(tester.getRect(f).bottomRight), isTrue, reason: '$name is inside its tile');
          if (scale >= 1.6) {
            expect(tester.getSize(f).height, greaterThan(11 * scale * 1.5), reason: '$name wraps onto a second line');
          }
        }
      });
    }
  });
}
