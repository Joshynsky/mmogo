// §AUTOREAD.REAL_WAITING_PAGE (I1): the Notifications page over the REAL waiting
// repository (real in-memory sqlite, fake bridge): a row appears, Parse moves it,
// Categorize saves, and the transaction shows up through the same query Home
// uses. Also the real actions: remove, paste (opens Add), parse all, and the
// launch source that ingests before the router looks. Autoread flavor only for
// the page tests; the rest is pure.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/ingesting_launch_source.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/launch_router.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/waiting_bell_numbers.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';
import 'package:mmogo/ui/screens/notifications/notifications_page.dart';
import 'package:mmogo/ui/shell/bell_counts.dart';
import 'package:mmogo/ui/shell/notifications_route.dart';
import 'package:mmogo/ui/shell/notifications_scope.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/news_fakes.dart';
import '../../support/pending_store_stand_in.dart';
import '../../support/waiting_fakes.dart';

/// A timer that never fires and keeps nothing pending in the test binding.
class _NoTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

class _FakeSource implements AutoReadLaunchSource {
  final StreamController<String> c = StreamController<String>.broadcast();
  @override
  Future<String?> takeLaunchId() async => null;
  @override
  Stream<String> get tapped => c.stream;
}

void main() {
  final skip = !kAutoReadCompiled;
  late Database db;
  late FakeAutoReadBridge bridge;
  late InMemoryPendingStore store;
  late RealWaitingRepository repo;
  var now = kFakeNow;

  Future<void> setup(WidgetTester t) async {
    await t.runAsync(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(
              version: 3,
              singleInstance: false,
              onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
              onCreate: (d, v) async {
                await AppSchema.createSchema(d);
                await AppSchema.seed(d);
              }));
    });
    bridge = FakeAutoReadBridge(now: () => now);
    store = InMemoryPendingStore();
    repo = RealWaitingRepository(
      bridge: bridge,
      store: store,
      service: AutoReadService(
        bridge: bridge,
        store: store,
        savedCodes: TransactionCodeLookup(() async => db),
        now: () => now,
      ),
      database: () async => db,
      now: () => now,
      captureIdentity: () async => true,
      onSaved: () {},
      timer: (_, _) => _NoTimer(),
    );
    addTearDown(() async {
      repo.dispose();
      await db.close();
    });
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> openPage(WidgetTester t, {NotifChip chip = NotifChip.all}) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.theme,
      routes: {Routes.add: (_) => const Scaffold(body: Text('ADD SCREEN'))},
      home: Builder(
        builder: (ctx) => NotificationsPage(
          news: FakeNotificationsRepository([]),
          waiting: repo,
          initialChip: chip,
          clock: () => now,
          waitingActions: buildRealWaitingActions(ctx, repo),
        ),
      ),
    ));
    await settle(t);
  }

  Finder row(int n) => find.byKey(Key('waiting-row-${heldIdFor(n)}'));

  testWidgets('a held message shows as a row; Parse moves it; Categorize saves a real transaction', (t) async {
    await setup(t);
    bridge.hold(heldIdFor(1), kSampleSendMoney, now.subtract(const Duration(hours: 1)));
    await openPage(t);
    expect(row(1), findsOneWidget);
    expect(find.text(kActionParse), findsWidgets);

    await t.tap(find.descendant(of: row(1), matching: find.text(kActionParse)));
    await settle(t);
    expect(find.text(kToastParsed), findsOneWidget);
    expect(find.descendant(of: row(1), matching: find.text(kActionCategorize)), findsOneWidget);
    expect(await t.runAsync(() => db.query('transactions')), isEmpty); // nothing saved by Parse

    await t.tap(find.descendant(of: row(1), matching: find.text(kActionCategorize)));
    await settle(t);
    final chips = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('categorizeChip_'));
    expect(chips, findsWidgets);
    await t.ensureVisible(chips.first);
    await t.tap(chips.first);
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('categorizeSave')));
    await t.tap(find.byKey(const Key('categorizeSave')));
    await settle(t);

    final rows = (await t.runAsync(() => HomeDashboardDao.recentTransactions(db)))!;
    expect(rows, hasLength(1));
    expect(rows.single.amountCents, 50000);
    expect(row(1), findsNothing);
    expect(bridge.isHeld(heldIdFor(1)), isFalse);
  }, skip: skip);

  testWidgets('Categorize on a not yet parsed row parses it first and opens the sheet', (t) async {
    await setup(t);
    bridge.hold(heldIdFor(1), kSampleBuyGoods, now);
    await openPage(t);
    final item = repo.itemById(heldIdFor(1))!;
    final actions = buildRealWaitingActions(t.element(find.byType(NotificationsPage)), repo);
    actions.onCategorize!(item);
    await settle(t);
    expect(find.byKey(const Key('categorizeSave')), findsOneWidget);
    expect(repo.itemById(heldIdFor(1))!.parsed!.code, 'ASD1F2G3H4');
  }, skip: skip);

  testWidgets('Remove on an unreadable row asks, removes and says so; the held copy is deleted', (t) async {
    await setup(t);
    bridge.hold(heldIdFor(1), 'nothing to read here', now.subtract(const Duration(hours: 2)));
    await openPage(t, chip: NotifChip.parse);
    expect(row(1), findsOneWidget);
    await t.tap(find.descendant(of: row(1), matching: find.text(kActionRemove)));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(kRemoveConfirm)));
    await settle(t);
    expect(row(1), findsNothing);
    expect(find.text(kToastRemoved), findsOneWidget);
    expect(bridge.isHeld(heldIdFor(1)), isFalse);
  }, skip: skip);

  testWidgets('Paste opens Add after the sheet closes', (t) async {
    await setup(t);
    bridge.hold(heldIdFor(1), 'nothing to read here', now.subtract(const Duration(hours: 2)));
    await openPage(t, chip: NotifChip.parse);
    await t.tap(find.descendant(of: row(1), matching: find.text(kActionPaste)));
    await settle(t);
    await t.tap(find.byKey(const Key('pasteContinue')));
    await settle(t);
    expect(find.text('ADD SCREEN'), findsOneWidget);
  }, skip: skip);

  testWidgets('Parse all parses every readable item, toasts once, and the rows move to Categorize', (t) async {
    await setup(t);
    bridge.hold(heldIdFor(1), kSampleSendMoney, now.subtract(const Duration(minutes: 1)));
    bridge.hold(heldIdFor(2), kSampleBuyGoods, now.subtract(const Duration(minutes: 2)));
    bridge.hold(heldIdFor(3), kSamplePaybill, now.subtract(const Duration(minutes: 3)));
    bridge.hold(heldIdFor(4), 'nothing to read', now.subtract(const Duration(minutes: 4)));
    await openPage(t, chip: NotifChip.parse);
    await t.tap(find.byKey(const Key('parseAllBar')));
    await settle(t);
    expect(find.text(kToastParsed), findsOneWidget);
    expect(await t.runAsync(() => store.count()), 3);
    expect(bridge.isHeld(heldIdFor(4)), isTrue); // the unreadable one is not lost
    expect(row(4), findsOneWidget);
    expect(row(1), findsNothing); // moved out of Parse
  }, skip: skip);

  testWidgets('NotificationsRoute wires the real actions and the bell numbers follow the repository', (t) async {
    now = DateTime.now(); // the route reads the real clock
    addTearDown(() => now = kFakeNow);
    await setup(t);
    bridge.hold(heldIdFor(1), kSampleSendMoney, now.subtract(const Duration(hours: 1)));
    bridge.hold(heldIdFor(2), 'not a payment', now.subtract(const Duration(hours: 1)));
    final news = FakeNotificationsRepository([]);
    final bell = BellCountsTracker(news: news.watchNews(), waiting: waitingBellNumbers(repo, () => now));
    addTearDown(bell.dispose);
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 900);
    addTearDown(t.view.reset);
    await t.pumpWidget(NotificationsScope(
      news: news,
      waiting: repo,
      counts: bell.value,
      child: MaterialApp(
        theme: AppTheme.theme,
        initialRoute: Routes.notifications,
        routes: {Routes.notifications: (_) => const NotificationsRoute()},
      ),
    ));
    await settle(t);
    // Bell: one ready to parse (the unreadable one is not counted).
    expect(bell.value.value.readyToParse, 1);
    expect(bell.value.value.waiting, 0);
    await t.tap(find.descendant(of: row(1), matching: find.text(kActionParse)));
    await settle(t);
    expect(find.text(kToastParsed), findsOneWidget);
    expect(bell.value.value.readyToParse, 0);
    expect(bell.value.value.waiting, 1);
  }, skip: skip);

  test('the launch source ingests before the router sees the tapped id', () async {
    final b = FakeAutoReadBridge(now: () => now);
    final s = InMemoryPendingStore();
    final r = RealWaitingRepository(
      bridge: b,
      store: s,
      service: AutoReadService(bridge: b, store: s, savedCodes: _NoCodes(), now: () => now),
      database: () async => throw StateError('unused'),
      now: () => now,
      timer: (_, _) => _NoTimer(),
    );
    addTearDown(r.dispose);
    final inner = _FakeSource();
    final src = IngestingLaunchSource(inner, r);
    final got = Completer<String>();
    final sub = src.tapped.listen(got.complete);
    b.hold(heldIdFor(7), kSampleSendMoney, now);
    inner.c.add(heldIdFor(7));
    expect(await got.future, heldIdFor(7));
    expect(r.itemById(heldIdFor(7)), isNotNull); // already known when the tap arrives
    await sub.cancel();
  });
}

class _NoCodes implements CodeLookup {
  @override
  Future<bool> contains(String displayCode) async => false;
}
