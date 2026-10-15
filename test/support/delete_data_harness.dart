// Shared harness for the Delete data UI tests (0.1.2 S9b-2). Everything is a
// fake: the service, the Back up now flow, the restart. Invented data only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/screens/settings/delete_data_row.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'fake_delete_data.dart';

/// A Database that only answers the Settings export count (0 rows).
class CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts restart calls; answers [answer].
class FakeRestart {
  FakeRestart({this.answer = true});
  bool answer;
  int calls = 0;
  Future<bool> call(BuildContext context) async {
    calls++;
    return answer;
  }
}

Future<void> pumpSettings(
  WidgetTester tester,
  FakeDeleteDataService fake, {
  FakeBackupFlow? flow,
  FakeRestart? restart,
  double scale = 1.0,
  bool dark = false,
  Size size = const Size(400, 4600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final c = AppPaletteController('ocean', dark ? 'dark' : 'light');
  // The scope sits ABOVE the MaterialApp, as in the real app, so sheets see it.
  await tester.pumpWidget(
    AppPaletteScope(
      controller: c,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: SettingsScreen(
          db: CountDb(),
          exportCsv: (_, _) async {},
          deleteData: fake,
          restart: restart?.call,
          backupFlow: flow ?? FakeBackupFlow(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get deleteRow => find.byType(DeleteDataRow);

Future<void> openDeleteSheet(WidgetTester tester) async {
  if (deleteRow.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      deleteRow,
      300,
      scrollable: find.descendant(of: find.byKey(const Key('settingsScroll')), matching: find.byType(Scrollable)).first,
    );
  }
  await tester.ensureVisible(deleteRow);
  await tester.pumpAndSettle();
  await tester.tap(deleteRow);
  await tester.pumpAndSettle();
}

Future<void> typeWord(WidgetTester tester, String word) async {
  await tester.enterText(find.byKey(const Key('deleteWordField')), word);
  await tester.pump();
}

bool goEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('deleteGo'))).onPressed != null;

Future<void> tapGo(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('deleteGo')));
  await tester.tap(find.byKey(const Key('deleteGo')));
}

/// True when the primary focus sits inside the widget with [key].
bool primaryFocusIsIn(Key key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  var found = false;
  ctx.visitAncestorElements((e) {
    if (e.widget.key == key) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
