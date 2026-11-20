// Wiring 3 (offers): three records in a row make the "Ask first next time?" offer appear on the Notifications
// page, and each offer adds one to the bell pill and to the To do chip. Own file so its static stores start
// clean. Real preferences stores, real in-memory ledger, invented data only.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/airtime_trail_store.dart';
import 'package:mmogo/autoread/data/all_category_choices.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/all_view_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/notifications/rules_page_state.dart';
import 'package:mmogo/autoread/ui/waiting_bell_numbers.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_trail_prefs.dart';
import '../../support/pending_store_stand_in.dart';
import 'wiring_db.dart';

final _t0 = DateTime(2026, 11, 19, 14, 5);

void main() {
  late Database db;
  late RealWaitingRepository repo;
  late List<int> sm;
  late RulesPageState state;

  /// Real I/O (the ledger, preferences) must run outside the widget test's fake clock.
  Future<void> init(WidgetTester t) async {
    await t.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      db = await openWiringDb();
      RulesWiring.database = () async => db;
      sm = await categoriesOf(db, 'SEND_MONEY');
      final bridge = FakeAutoReadBridge(now: () => _t0);
      final store = InMemoryPendingStore();
      repo = RealWaitingRepository(
        bridge: bridge,
        store: store,
        service: AutoReadService(bridge: bridge, store: store, savedCodes: TransactionCodeLookup(() async => db), now: () => _t0),
        database: () async => db,
        now: () => _t0,
        captureIdentity: () async => true,
        timer: (after, fire) => Timer(const Duration(days: 365), () {}),
        trailStore: AirtimeTrailStore(prefs: FakeTrailPrefs(), now: () => _t0),
      );
      RulesWiring.install();
      state = RulesPageState();
      await state.load(AllCategoryChoices(() async => db));
    });
    addTearDown(() {
      RulesWiring.uninstall();
      state.dispose();
      repo.dispose();
    });
  }

  /// The ledger hooks run on their own after each insert: wait (real time) until the offer shows.
  Future<void> addThreeAndWait() async {
    for (var i = 1; i <= 3; i++) {
      await addSendMoney(db, code: 'OFR000000$i', category: sm[0]);
    }
    final c = RulesWiring.suggestions!;
    for (var i = 0; i < 80 && c.offers.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await c.refresh();
    }
  }

  testWidgets('three records in a row make the "Ask first next time?" offer appear; Ask first saves the rule', (t) async {
    await init(t);
    await t.runAsync(addThreeAndWait);
    expect(RulesWiring.suggestions!.offers, hasLength(1));
    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Builder(
              builder: (ctx) => WaitingSection(
                  waiting: const <WaitingItem>[], now: _t0, actions: buildRealWaitingActions(ctx, repo, rules: state)),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('suggestion-confirm')), findsOneWidget);
    await t.tap(find.byKey(const Key('suggestion-confirm')));
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100));
    }
    final rule = (await t.runAsync(() => AutoReadRuntime.ruleStore.get(ReceiverType.sendMoney, '0712345678')))!;
    expect(rule.level, RuleLevel.askFirst);
    expect(rule.categoryId, sm[0]);
  });

  testWidgets('the bell pill and the To do chip count each offer as one more', (t) async {
    await init(t);
    final c = RulesWiring.suggestions!;
    final withOffer = (await t.runAsync(() async {
      await addThreeAndWait();
      return waitingBellNumbers(repo, () => _t0, offersChanged: c, offerCount: () => c.offers.length).first;
    }))!;
    expect(c.offers, hasLength(1));
    expect(withOffer.waiting, 1);
    expect(todoCount(const <WaitingItem>[], _t0, offers: 1), 1);
    expect(todoCount(const <WaitingItem>[], _t0), 0);
  });
}
