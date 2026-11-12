// Settings > Adding entries: the one Remembered row appears only when the
// auto-read build passes a hook; the standard row stays as it was.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/settings/remembered_hook_row.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/fake_delete_data.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Fake {
  int on = 1;
  int names = 3;
  int loads = 0;
  final changes = ValueNotifier<int>(0);
  RememberedRowHook get hook => RememberedRowHook(
    changes: changes,
    load: () async {
      loads++;
      return RememberedRowInfo(autoOn: on, names: names);
    },
  );
}

Future<void> _pump(WidgetTester tester, {RememberedRowHook? hook, double scale = 1.0, String appearance = 'light'}) async {
  tester.view.physicalSize = const Size(400, 4600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = AppPaletteController('ocean', appearance);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        Routes.rememberedRecipients: (ctx) => Scaffold(
          body: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('REMEMBERED PAGE')),
        ),
      },
      builder: (context, child) =>
          MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: AppPaletteScope(
        controller: c,
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}, rememberedHook: hook),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => useFakeDeleteData());
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('standard build: no hook keeps today\'s row and sub-line', (tester) async {
    await _pump(tester);
    expect(find.text('Remembered recipients'), findsOneWidget);
    expect(find.text('Name and type, kept on this phone'), findsOneWidget);
    expect(find.text('Remembered: recipients and auto-record'), findsNothing);
    expect(find.byKey(const Key('settingsRemembered')), findsOneWidget);
    await tester.tap(find.text('Remembered recipients'));
    await tester.pumpAndSettle();
    expect(find.text('REMEMBERED PAGE'), findsOneWidget);
  });

  testWidgets('with the hook: one row replaces the old one, with names count and auto state', (tester) async {
    final f = _Fake();
    await _pump(tester, hook: f.hook);
    expect(find.text('Remembered recipients'), findsNothing);
    expect(find.text('Remembered: recipients and auto-record'), findsOneWidget);
    expect(find.text('Auto-record airtime: 1 of 2 on · 3 names, kept on this phone'), findsOneWidget);
    expect(find.byKey(const Key('settingsRemembered')), findsOneWidget);
  });

  testWidgets('opens the Remembered page and the sub-line refreshes after Back', (tester) async {
    final f = _Fake();
    await _pump(tester, hook: f.hook);
    await tester.tap(find.text('Remembered: recipients and auto-record'));
    await tester.pumpAndSettle();
    expect(find.text('REMEMBERED PAGE'), findsOneWidget);
    f.on = 2;
    f.names = 1;
    await tester.tap(find.text('REMEMBERED PAGE'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-record airtime: 2 of 2 on · 1 name, kept on this phone'), findsOneWidget);
  });

  testWidgets('the sub-line follows the controller while Settings is showing', (tester) async {
    final f = _Fake();
    await _pump(tester, hook: f.hook);
    f.on = 0;
    f.changes.value++;
    await tester.pumpAndSettle();
    expect(find.text('Auto-record airtime: 0 of 2 on · 3 names, kept on this phone'), findsOneWidget);
  });

  testWidgets('a hook with nothing to say falls back to today\'s sub-line', (tester) async {
    await _pump(tester, hook: RememberedRowHook(load: () async => const RememberedRowInfo()));
    expect(find.text('Name and type, kept on this phone'), findsOneWidget);
    expect(find.text('Remembered: recipients and auto-record'), findsOneWidget);
  });

  testWidgets('spoken label joins the row name and its sub-line, as a button', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, hook: _Fake().hook);
    expect(
      find.bySemanticsLabel('Remembered: recipients and auto-record. Auto-record airtime: 1 of 2 on · 3 names, kept on this phone'),
      findsOneWidget,
    );
    handle.dispose();
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('no overflow at text $scale', (tester) async {
      await _pump(tester, hook: _Fake().hook, scale: scale);
      expect(tester.takeException(), isNull);
      expect(find.text('Remembered: recipients and auto-record'), findsOneWidget);
    });
  }

  testWidgets('dark appearance: row shows, no overflow at 1.3', (tester) async {
    await _pump(tester, hook: _Fake().hook, scale: 1.3, appearance: 'dark');
    expect(tester.takeException(), isNull);
    expect(find.text('Remembered: recipients and auto-record'), findsOneWidget);
  });
}
