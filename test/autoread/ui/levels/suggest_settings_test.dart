// Widget tests for the Suggest rows in Settings: the switch and the
// "Suggest after" picker (2 to 10, default 3). Fake port, invented values.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/settings/suggest_settings_section.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

class _Port implements SuggestSettingsPort {
  _Port({this.n = 3, this.ok = true});
  bool on = true;
  int n;
  bool ok;
  final List<int> sets = [];
  @override
  Future<bool> enabled() async => on;
  @override
  Future<int> after() async => n;
  @override
  Future<bool> setEnabled(bool v) async {
    if (!ok) return false;
    on = v;
    return true;
  }

  @override
  Future<bool> setAfter(int v) async {
    sets.add(v);
    if (!ok) return false;
    n = v;
    return true;
  }
}

Future<void> _pump(WidgetTester t, SuggestSettingsPort? port, {double scale = 1}) async {
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: SingleChildScrollView(child: SuggestSettingsSection(port: port)),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  test('clampSuggestAfter keeps 2..10', () {
    expect(clampSuggestAfter(-5), 2);
    expect(clampSuggestAfter(0), 2);
    expect(clampSuggestAfter(1), 2);
    expect(clampSuggestAfter(2), 2);
    expect(clampSuggestAfter(10), 10);
    expect(clampSuggestAfter(11), 10);
    expect(clampSuggestAfter(999), 10);
    expect(kSuggestAfterDefault, 3);
  });

  testWidgets('nothing drawn without a port', (t) async {
    LevelsDeps.instance = null;
    await _pump(t, null);
    expect(find.byKey(const Key('suggestSettings')), findsNothing);
  });

  testWidgets('shows both rows; value 3 by default; stored 50 shows 10', (t) async {
    await _pump(t, _Port());
    expect(find.text(kSuggestSwitchLabel), findsOneWidget);
    expect(find.textContaining(suggestAfterOption(3)), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await _pump(t, _Port(n: 50));
    expect(find.textContaining(suggestAfterOption(10)), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await _pump(t, _Port(n: 0));
    expect(find.textContaining(suggestAfterOption(2)), findsOneWidget);
  });

  testWidgets('renamed rows: Offer Ask first, Offer after N in a row; no Suggest wording left', (t) async {
    await _pump(t, _Port());
    expect(find.text('Offer Ask first'), findsOneWidget);
    expect(find.text('Offer after N in a row'), findsOneWidget);
    expect(find.text('Suggest asking first'), findsNothing);
    expect(find.text('Suggest after'), findsNothing);
  });

  testWidgets('showLabel false: no second SUGGESTIONS title', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: SuggestSettingsSection(port: _Port(), showLabel: false)),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('SUGGESTIONS'), findsNothing);
    expect(find.text('Suggestions'), findsNothing);
    expect(find.text(kSuggestSwitchLabel), findsOneWidget);
  });

  testWidgets('picker offers exactly 2..10 and stores the choice', (t) async {
    final p = _Port();
    await _pump(t, p);
    await t.tap(find.byKey(const Key('suggestAfterRow')));
    await t.pumpAndSettle();
    for (var n = 2; n <= 10; n++) {
      expect(find.byKey(Key('suggestAfter$n')), findsOneWidget);
    }
    expect(find.byKey(const Key('suggestAfter1')), findsNothing);
    expect(find.byKey(const Key('suggestAfter11')), findsNothing);
    await t.tap(find.byKey(const Key('suggestAfter7')));
    await t.pumpAndSettle();
    expect(p.sets, [7]);
    expect(find.textContaining(suggestAfterOption(7)), findsOneWidget);
  });

  testWidgets('switch off hides the picker and stores; on shows it again', (t) async {
    final p = _Port();
    await _pump(t, p);
    await t.tap(find.byKey(const Key('suggestSwitch')));
    await t.pumpAndSettle();
    expect(p.on, isFalse);
    expect(find.byKey(const Key('suggestAfterRow')), findsNothing);
    await t.tap(find.byKey(const Key('suggestSwitch')));
    await t.pumpAndSettle();
    expect(p.on, isTrue);
    expect(find.byKey(const Key('suggestAfterRow')), findsOneWidget);
  });

  testWidgets('a failed save keeps the old value and says so', (t) async {
    final p = _Port(ok: false);
    await _pump(t, p);
    await t.tap(find.byKey(const Key('suggestSwitch')));
    await t.pumpAndSettle();
    expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text(kSuggestSaveFailed), findsOneWidget);
  });

  testWidgets('large text 2.0: no overflow', (t) async {
    await _pump(t, _Port(), scale: 2.0);
    expect(t.takeException(), isNull);
  });
}
