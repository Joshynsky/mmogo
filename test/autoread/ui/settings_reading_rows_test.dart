// The Settings screen in BOTH flavors. Not tagged: the default run proves the
// standard build shows nothing about reading messages; the autoread run proves
// the rows sit between Your data and About.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/ui/settings_autoread_copy.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_delete_data.dart';
import '../logic/reading_fakes.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
        {'cnt': 0},
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(400, 5200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: AppPaletteScope(
      controller: AppPaletteController(),
      child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => useFakeDeleteData());
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ReadingControllerHolder.instance = null);

  testWidgets('the standard Settings screen names nothing about reading messages', (t) async {
    if (kAutoReadCompiled) {
      // The autoread build has the rows; the standard check is the other run.
      return;
    }
    ReadingControllerHolder.instance = ReadingController(
      bridge: FakeReadingBridge(enabled: true),
      store: FakeGenerationStore(),
      prefs: FakeReadingPrefs(),
    );
    await _pump(t);
    expect(find.byKey(const Key('readingSection')), findsNothing);
    for (final s in allSettingsAutoReadCopy()) {
      expect(find.text(s), findsNothing, reason: s);
    }
    expect(find.textContaining('M-Pesa messages'), findsNothing);
    expect(find.textContaining('held'), findsNothing);
    expect(find.text('YOUR DATA'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
  });

  testWidgets('the autoread Settings screen shows the rows between Your data and About', (t) async {
    if (!kAutoReadCompiled) return; // see the standard test above
    ReadingControllerHolder.instance = ReadingController(
      bridge: FakeReadingBridge(),
      store: FakeGenerationStore(),
      prefs: FakeReadingPrefs(),
    );
    await _pump(t);
    double y(Finder f) => t.getTopLeft(f).dy;
    expect(find.text(kReadLabel), findsOneWidget);
    expect(find.text(kDeleteHeldLabel), findsOneWidget);
    expect(find.text(kHelpRowLabel), findsOneWidget);
    expect(y(find.text('Delete data')) < y(find.text(kReadingSectionLabel.toUpperCase())), isTrue);
    expect(y(find.text(kReadingSectionLabel.toUpperCase())) < y(find.text('ABOUT')), isTrue);
  });

  testWidgets('autoread build with no controller wired shows no rows (fails quiet)', (t) async {
    ReadingControllerHolder.instance = null;
    await _pump(t);
    expect(find.byKey(const Key('readingSection')), findsNothing);
  });
}
