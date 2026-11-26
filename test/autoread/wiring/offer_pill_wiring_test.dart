// 0.2.2 item 2 redesign, slice I2a (U-OFFER / U-PILL MUST): the offer's Ask first through the REAL wiring
// (buildRealWaitingActions: suggestions = RulesWiring.suggestions, categoryNameOf = RulesPageState.nameOf,
// real_waiting_actions.dart) reaches the one pill (RuleChangePill) with the plain name and the category's name:
// the pill SHOWS the category, and no phone number (masked or not) is in it. Own file so its static stores start
// clean. Real preferences stores, real in-memory ledger, invented data only. Dormant: debugAutoRecordUiOverride
// set per test and reset in tearDown.
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
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill.dart';
import 'package:mmogo/autoread/ui/notifications/rules_page_state.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
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

  setUp(() => debugAutoRecordUiOverride = true);
  tearDown(() => debugAutoRecordUiOverride = null);

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

  testWidgets('offer Ask first: the real pill shows the plain name and the category name, no number', (t) async {
    await init(t);
    await t.runAsync(() async {
      for (var i = 1; i <= 3; i++) {
        await addSendMoney(db, code: 'OPW000000$i', category: sm[0]);
      }
      final c = RulesWiring.suggestions!;
      for (var i = 0; i < 80 && c.offers.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await c.refresh();
      }
    });
    final c = RulesWiring.suggestions!;
    expect(c.offers, hasLength(1));
    expect(c.notice, isA<RuleChangePill>()); // the real pill, as installed
    final catName = state.nameOf(sm[0]);
    expect(catName, isNotNull);

    t.view.physicalSize = const Size(400, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
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
    await t.tap(find.byKey(const Key('suggestion-confirm')));
    for (var i = 0; i < 12; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 100));
    }
    final rule = (await t.runAsync(() => AutoReadRuntime.ruleStore.get(ReceiverType.sendMoney, '0712345678')))!;
    expect(rule.level, RuleLevel.askFirst);
    expect(find.text(hardPillAskFirst('Jane Doe', catName!)), findsOneWidget);
    expect(find.textContaining('0712'), findsNothing);
    expect(find.textContaining('***'), findsNothing);
    expect(find.textContaining('[PM to write'), findsNothing);
    // Let the pill finish (its timers) before the test ends.
    await t.pump(const Duration(seconds: 15));
    await t.pumpAndSettle();
  });
}
