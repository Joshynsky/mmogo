// The whole Settings screen for the item 3 tests (order, search jump, 200% text), in the standard build and (with
// --dart-define=MMOGO_AUTOREAD=true) the auto-read build. Fake database, fake delete data, fake auto-read ports.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/ui/screens/settings/settings_row_target.dart';
import 'package:mmogo/ui/screens/settings/remembered_hook_row.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../autoread/logic/reading_fakes.dart';
import 'fake_delete_data.dart';
import 'hard_rule_fakes.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
        {'cnt': 0},
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [CategoryChoice(id: '1', name: 'Food')];
  @override
  Future<CategoryChoice> create(String name) => throw UnimplementedError();
}

/// Call from `setUp`: fakes in place, clean prefs.
void settingsHarnessSetUp() {
  useFakeDeleteData();
  SharedPreferences.setMockInitialValues({});
  if (kAutoReadCompiled) {
    debugAutoRecordUiOverride = true;
    ReadingControllerHolder.instance = ReadingController(
      bridge: FakeReadingBridge(),
      store: FakeGenerationStore(),
      prefs: FakeReadingPrefs(),
    );
    LevelsDeps.instance = LevelsDeps(
      store: FakeRuleStore(),
      history: FakeHistoryReader(),
      categories: _Cats(),
      suggest: FakeSuggestSettings(),
      pause: FakeHardRulePausePort(),
    );
  }
}

/// Call from `tearDown`.
void settingsHarnessTearDown() {
  debugAutoRecordUiOverride = null;
  ReadingControllerHolder.instance = null;
  LevelsDeps.instance = null;
}

final _hook = RememberedRowHook(load: () async => const RememberedRowInfo(autoOn: 1, names: 2, people: 3));

/// Pumps Settings on a [size] screen. The People hook is passed only in the auto-read build.
Future<void> pumpSettings(WidgetTester t, {Size size = const Size(400, 800), double scale = 1, String appearance = 'light'}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
      home: AppPaletteScope(
        controller: AppPaletteController('ocean', appearance),
        child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {}, rememberedHook: kAutoReadCompiled ? _hook : null),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// The ids of every findable row the Settings screen shows (each is a [SettingsRowTarget]), with the ids that
/// land on a row (`alsoFor`) for rows the page does not show now.
Set<String> settingsRowIdsFromScreen(WidgetTester t, {bool withAliases = false}) {
  final ids = <String>{};
  for (final w in t.widgetList<SettingsRowTarget>(find.byType(SettingsRowTarget, skipOffstage: false))) {
    ids.add(w.id);
    if (withAliases) ids.addAll(w.alsoFor);
  }
  return ids;
}
