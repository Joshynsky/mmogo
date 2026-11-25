// Settings row and Remembered page (both tabs) run
// off ONE controller. These tests mount the same wiring the app uses
// (remembered_wiring.dart) over mock preferences and invented names.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/ui/remembered_wiring.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/screens/remembered/remembered_screen.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
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

const _sub2 = 'Auto-record airtime: 2 of 2 on · 1 name, kept on this phone';
const _sub0 = 'Auto-record airtime: 0 of 2 on · 1 name, kept on this phone';
const _row = 'Remembered, suggestions and auto-record';

Future<void> _put(String k, bool v) async => (await SharedPreferences.getInstance()).setBool(k, v);

/// A controller wired like the repository's: a flip writes its own key, then moves.
AirtimeAutoController _controller() {
  late AirtimeAutoController c;
  c = AirtimeAutoController(
    onSwitch: (v) async {
      await _put(kAirtimeAutoPrefKey, v);
      c.setOn(v);
    },
    onSwitchOther: (v) async {
      await _put(kAirtimeAutoOtherPrefKey, v);
      c.setOnOther(v);
    },
    onUndo: (_) async {},
  );
  return c;
}

/// Like a restart: a NEW controller primed from the saved keys.
Future<AirtimeAutoController> _rebuilt() async {
  final c = _controller();
  final p = await SharedPreferences.getInstance();
  c.setOn(p.getBool(kAirtimeAutoPrefKey) ?? false);
  c.setOnOther(p.getBool(kAirtimeAutoOtherPrefKey) ?? false);
  return c;
}

/// One invented name kept (the Settings sub counts it).
Future<RecipientMemory> _seeded() async {
  SharedPreferences.setMockInitialValues({});
  final m = RecipientMemory(nowMs: () => 1000);
  await m.remember('MAMA TEST', SmsSourceType.pochi, recordDetailsOn: true);
  return m;
}

final _nav = GlobalKey<NavigatorState>();

/// [c] null = the standard build's wiring (no hook, plain page).
Future<void> _pump(WidgetTester t, AirtimeAutoController? c, RecipientMemory mem) async {
  t.view.physicalSize = const Size(400, 4600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        navigatorKey: _nav,
        routes: {
          Routes.rememberedRecipients: (ctx) => c == null
              ? RememberedScreen(memory: mem)
              : rememberedPageFor(c, args: ModalRoute.of(ctx)?.settings.arguments, memory: mem),
        },
        home: SettingsScreen(
          db: _CountDb(),
          exportCsv: (_, _) async {},
          rememberedHook: c == null ? null : rememberedRowHookFor(c, memory: mem),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

bool _sw(WidgetTester t, String key) => t.widget<Switch>(find.byKey(Key(key))).value;

Future<void> _openTab2(WidgetTester t) async {
  await t.tap(find.text(_row));
  await t.pumpAndSettle();
  await t.tap(find.text('Suggest and auto-record'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => useFakeDeleteData());

  testWidgets('one controller: flip on the tab, the Settings sub follows; flip back, they follow again', (t) async {
    final mem = await _seeded();
    final c = _controller();
    await _pump(t, c, mem);
    await _openTab2(t);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.pumpAndSettle();
    expect(c.on, isTrue);
    expect(c.onOther, isFalse);
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    expect(c.onOther, isTrue);
    expect(_sw(t, 'autoRecordOtherSwitch'), isTrue);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text(_sub2), findsOneWidget);
    // The controller flipped from outside (the repository), the page re-reads it.
    c.setOn(false);
    await t.pumpAndSettle();
    expect(find.text('Auto-record airtime: 1 of 2 on · 1 name, kept on this phone'), findsOneWidget);
    await _openTab2(t);
    expect(_sw(t, 'autoRecordMyselfSwitch'), isFalse);
    expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
  });

  testWidgets('the Settings row sub shows the count and names, and updates after Back', (t) async {
    final mem = await _seeded();
    final c = _controller();
    await _pump(t, c, mem);
    expect(find.text(_sub0), findsOneWidget);
    await _openTab2(t);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text(_sub2), findsOneWidget);
  });

  testWidgets('prefs gain only the two existing keys, and both switches survive a rebuild', (t) async {
    final mem = await _seeded();
    final before = (await SharedPreferences.getInstance()).getKeys().toSet();
    final c = _controller();
    await _pump(t, c, mem);
    await _openTab2(t);
    await t.tap(find.byKey(const Key('autoRecordMyself')));
    await t.tap(find.byKey(const Key('autoRecordOther')));
    await t.pumpAndSettle();
    final p = await SharedPreferences.getInstance();
    expect(p.getKeys().difference(before), {kAirtimeAutoPrefKey, kAirtimeAutoOtherPrefKey});
    // Rebuild everything with a new controller read back from prefs.
    await t.pumpWidget(const SizedBox());
    final c2 = await _rebuilt();
    await _pump(t, c2, mem);
    expect(find.text(_sub2), findsOneWidget);
    await _openTab2(t);
    expect(_sw(t, 'autoRecordMyselfSwitch'), isTrue);
    expect(_sw(t, 'autoRecordOtherSwitch'), isTrue);
  });

  testWidgets('deep link: openAutoRecord opens on the second tab', (t) async {
    final mem = await _seeded();
    final c = _controller();
    await _pump(t, c, mem);
    _nav.currentState!.pushNamed(
      Routes.rememberedRecipients,
      arguments: const RememberedRouteArgs(openAutoRecord: true),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('autoRecordMyself')).hitTestable(), findsOneWidget);
  });

  testWidgets('standard build wiring: the 0.1.3 row and page, no tabs', (t) async {
    final mem = await _seeded();
    await _pump(t, null, mem);
    expect(find.text(_row), findsNothing);
    expect(find.text('Remembered recipients'), findsOneWidget);
    expect(find.text('Name and type, kept on this phone'), findsOneWidget);
    await t.tap(find.text('Remembered recipients'));
    await t.pumpAndSettle();
    expect(find.text('Remembered recipients'), findsOneWidget); // the page title
    expect(find.text('Suggest and auto-record'), findsNothing);
    expect(find.text('Forget all'), findsOneWidget);
  });
}
