// Wiring 3: the Notifications page's rule rows are connected. An Ask first item shows "Record as ...?" with
// Yes, Change category and Categorize later; Yes records through the real save (and the ledger hook counts
// it); the "Ask first next time?" offers come from the real engine and add to the bell and To do numbers.
// Real preferences stores, real in-memory ledger, invented data only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/labelling_pending_store.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/data/all_category_choices.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart' show kCategorizeChoosePrompt;
import 'package:mmogo/autoread/ui/notifications/rules_page_state.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/fake_trail_prefs.dart';
import '../../support/waiting_fakes.dart' show heldIdFor;
import 'wiring_db.dart';

final _t0 = DateTime(2026, 11, 19, 14, 5);

void main() {
  late Database db;
  late FakeAutoReadBridge bridge;
  late RealWaitingRepository repo;
  late SharedPrefsPendingItemsStore store;
  late List<int> sm;
  late List<int> pb;
  late RulesPageState state;

  /// Real I/O (the ledger, preferences) must run outside the widget test's fake clock.
  Future<void> init(WidgetTester t) async {
    await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      db = await openWiringDb();
      RulesWiring.database = () async => db;
      sm = await categoriesOf(db, 'SEND_MONEY');
      pb = await categoriesOf(db, 'PAYBILL');
      store = SharedPrefsPendingItemsStore();
      bridge = FakeAutoReadBridge(now: () => _t0, generation: await store.readGeneration());
      final labelled = LabellingPendingStore(store, RuleLabeler(rules: AutoReadRuntime.ruleStore, history: FakeHistoryReader()));
      repo = RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(bridge: bridge, store: labelled, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
        database: () async => db,
        now: () => _t0,
        captureIdentity: () async => true,
        timer: (after, fire) => Timer(const Duration(days: 365), () {}),
        trailStore: AirtimeTrailStore(prefs: FakeTrailPrefs(), now: () => _t0),
      );
      RulesWiring.install(); // the ledger hooks that count a record
      state = RulesPageState();
      await state.load(AllCategoryChoices(() async => db));
    });
    addTearDown(() {
      RulesWiring.uninstall();
      state.dispose();
      repo.dispose();
    });
  }

  /// Lets the real I/O of a tap (the save, the hook) finish.
  Future<void> settle(WidgetTester t) async {
    // Each database step finishes in real time, its continuation runs on the next pump: alternate.
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100)); // not pumpAndSettle: a sheet may keep a spinner going
    }
  }

  Future<void> askFirstFor(WidgetTester t, int category) async {
    await t.runAsync(() => AutoReadRuntime.ruleStore.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane Doe', level: RuleLevel.askFirst, categoryId: category, at: DateTime.utc(2026, 11, 1)));
  }

  Widget page(List<WaitingItem> items) => AppPaletteScope(
        controller: AppPaletteController('ocean', 'light'),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (ctx) => WaitingSection(waiting: items, now: _t0, actions: buildRealWaitingActions(ctx, repo, rules: state)),
              ),
            ),
          ),
        ),
      );

  Future<void> pumpWithParsedItem(WidgetTester t) async {
    final items = (await t.runAsync(() async {
      bridge.hold(heldIdFor(1), kSampleSendMoney, _t0.subtract(const Duration(minutes: 5)));
      await repo.ingest();
      await repo.parse(heldIdFor(1));
      return repo.watch().first;
    }))!;
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(page(items));
    await t.pumpAndSettle();
  }

  Future<List<Map<String, Object?>>> rowsOf(WidgetTester t) async => (await t.runAsync(() => db.query('transactions')))!;

  testWidgets('the label made at Parse survives into the page: an Ask first row with its three buttons', (t) async {
    await init(t);
    await askFirstFor(t, sm[0]);
    await pumpWithParsedItem(t);
    expect(find.byKey(const Key('ask-first-yes')), findsOneWidget);
    expect(find.byKey(const Key('ask-first-change')), findsOneWidget);
    expect(find.byKey(const Key('ask-first-later')), findsOneWidget);
  });

  testWidgets('Yes records the item in the person category, and the ledger hook counts it for the rule', (t) async {
    await init(t);
    await askFirstFor(t, sm[0]);
    await pumpWithParsedItem(t);
    await t.tap(find.byKey(const Key('ask-first-yes')));
    await settle(t);
    final rows = await rowsOf(t);
    expect(rows.single['classification_id'], sm[0]);
    expect(rows.single['raw_parse_source'], 'SMS_PARSE');
    expect((await t.runAsync(() => store.list()))!, isEmpty);
    final rule = (await t.runAsync(() => AutoReadRuntime.ruleStore.get(ReceiverType.sendMoney, '0712345678')))!;
    expect(rule.level, RuleLevel.askFirst);
    expect(rule.lastRecorded, isNotNull);
  });

  testWidgets('Categorize later turns the row into a normal row and records nothing', (t) async {
    await init(t);
    await askFirstFor(t, sm[0]);
    await pumpWithParsedItem(t);
    await t.tap(find.byKey(const Key('ask-first-later')));
    await settle(t);
    expect(find.byKey(const Key('ask-first-yes')), findsNothing);
    expect(await rowsOf(t), isEmpty);
    expect((await t.runAsync(() => store.list()))!, hasLength(1));
  });

  testWidgets('Change category opens the Categorize sheet and records nothing', (t) async {
    await init(t);
    await askFirstFor(t, sm[0]);
    await pumpWithParsedItem(t);
    await t.tap(find.byKey(const Key('ask-first-change')));
    await settle(t);
    expect(find.text(kCategorizeChoosePrompt), findsOneWidget);
    expect(await rowsOf(t), isEmpty);
  });

  testWidgets('a category that does not belong to this type falls back to the sheet; nothing is half-saved', (t) async {
    await init(t);
    await askFirstFor(t, pb[0]); // a Paybill category on a Send Money person
    await pumpWithParsedItem(t);
    await t.tap(find.byKey(const Key('ask-first-yes')));
    await settle(t);
    expect(find.text(kCategorizeChoosePrompt), findsOneWidget);
    expect(await rowsOf(t), isEmpty);
    expect((await t.runAsync(() => store.list()))!, hasLength(1));
  });
}
