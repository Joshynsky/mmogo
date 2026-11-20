// Wiring 6 and 7: on the Remembered page Forget, Change to Send Money and Forget all also remove the
// person's Pochi rule; Change to Pochi keeps rules; tab 2 lists people who have history but no rule.
// Real rule store over mock preferences, real page, invented names only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_cleanup.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/remembered_wiring.dart';
import 'package:mmogo/autoread/rules/prefs_suggest_settings.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Cats implements CategoryChoices {
  @override
  Future<List<CategoryChoice>> categories() async => const [CategoryChoice(id: '1', name: 'Fuel')];
  @override
  Future<CategoryChoice> create(String name) async => throw UnimplementedError();
}

void main() {
  late PrefsRuleStore store;
  late RecipientMemory memory;

  AirtimeAutoController controller() => AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});

  Future<void> pump(WidgetTester t, {LevelsDeps? deps}) async {
    t.view.physicalSize = const Size(400, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        home: rememberedPageFor(controller(), memory: memory, levels: deps, cleanup: RuleCleanup(store)),
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> seed() async {
    SharedPreferences.setMockInitialValues({});
    store = PrefsRuleStore();
    var clock = 1000;
    memory = RecipientMemory(nowMs: () => clock++);
    await memory.remember('MAMA TEST', SmsSourceType.pochi, recordDetailsOn: true);
    await memory.remember('BABA TEST', SmsSourceType.pochi, recordDetailsOn: true);
    for (final k in ['MAMA TEST', 'BABA TEST']) {
      await store.setLevel(ReceiverType.pochi, k, name: k, level: RuleLevel.askFirst, categoryId: 1, at: DateTime.utc(2026, 11, 1));
    }
    await store.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 1, at: DateTime.utc(2026, 11, 1));
  }

  testWidgets('Forget one name removes that name\'s Pochi rule and no other', (t) async {
    await seed();
    await pump(t);
    await t.tap(find.byKey(const Key('rememberedForget')).first);
    await t.pumpAndSettle();
    final left = (await store.all()).map((r) => '${r.type.code}.${r.key}').toSet();
    expect(left.length, 2);
    expect(left, contains('SM.0712345678'));
    expect(left.where((k) => k.startsWith('PO.')), hasLength(1));
    expect((await memory.list()), hasLength(1));
  });

  testWidgets('Change to Send Money removes the Pochi rule; the name stays remembered', (t) async {
    await seed();
    await pump(t);
    // the newest remembered name is listed first: BABA TEST
    await t.tap(find.byKey(const Key('rememberedChange')).first);
    await t.pumpAndSettle();
    final pochi = (await store.all()).where((r) => r.type == ReceiverType.pochi).map((r) => r.key);
    expect(pochi, ['MAMA TEST']);
    expect(await memory.list(), hasLength(2));
  });

  testWidgets('Change to Pochi (from Send Money) keeps every rule', (t) async {
    await seed();
    await memory.retype('MAMA TEST', SmsSourceType.sendMoney);
    await memory.retype('BABA TEST', SmsSourceType.sendMoney);
    await pump(t);
    await t.tap(find.byKey(const Key('rememberedChange')).first); // Send Money -> Pochi
    await t.pumpAndSettle();
    expect((await store.all()), hasLength(3));
  });

  testWidgets('Forget all removes every Pochi rule and keeps the phone and shop rules', (t) async {
    await seed();
    await pump(t);
    await t.tap(find.byKey(const Key('rememberedForgetAll')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('forgetAllConfirm')));
    await t.pumpAndSettle();
    final left = await store.all();
    expect(left.map((r) => r.type), [ReceiverType.sendMoney]);
    expect(await memory.list(), isEmpty);
  });

  testWidgets('tab 2 lists a person who has history but no rule (the known source)', (t) async {
    await seed();
    final deps = LevelsDeps(
      store: store,
      history: FakeHistoryReader(history: {'SM.0733000111': [1]}),
      categories: _Cats(),
      suggest: PrefsSuggestSettings(),
      known: () async => const [KnownPerson(type: ReceiverType.sendMoney, key: '0733000111', name: 'Joseph Kamau')],
    );
    await pump(t, deps: deps);
    await t.tap(find.byKey(const Key('rememberedTab1')));
    await t.pumpAndSettle();
    expect(find.textContaining('Joseph Kamau'), findsWidgets);
  });
}
