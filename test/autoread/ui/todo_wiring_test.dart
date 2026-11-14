// §AUTOREAD.TODO_WIRING: the To do view over the REAL waiting repository (real
// in-memory sqlite, fake bridge), through NotificationsRoute. Parse in place, a
// pick through the row vs the same pick through the Categorize sheet (same
// ledger row), Later then pick, airtime ON (trail, Undo, Change in Settings)
// and OFF, and no switch card on Notifications. Autoread flavor.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/data/real_waiting_actions.dart';
import 'package:mmogo/autoread/data/real_waiting_repository.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';
import 'package:mmogo/autoread/ui/choose_category_copy.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/todo_copy.dart';
import 'package:mmogo/autoread/ui/waiting_bell_numbers.dart';
import 'package:mmogo/data/db/schema.dart';
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

class _NoTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => false;
  @override
  int get tick => 0;
}

/// Records every route pushed, with its name and arguments.
class _Pushes extends NavigatorObserver {
  final List<RouteSettings> pushed = [];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route.settings);
}

class _Env {
  late Database db;
  late FakeAutoReadBridge bridge;
  late RealWaitingRepository repo;
  late BellCountsTracker bell;
  final DateTime now = DateTime.now();
  final _Pushes pushes = _Pushes();
  bool airtimeOn = false;
  bool airtimeOtherOn = false;

  Future<void> open(WidgetTester t) async {
    await t.runAsync(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
          onCreate: (d, v) async {
            await AppSchema.createSchema(d);
            await AppSchema.seed(d);
          },
        ),
      );
    });
    bridge = FakeAutoReadBridge(now: () => now);
    final store = InMemoryPendingStore();
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
      readAirtimeAuto: () async => airtimeOn,
      writeAirtimeAuto: (v) async => airtimeOn = v,
    );
    final news = FakeNotificationsRepository([]);
    bell = BellCountsTracker(
      news: news.watchNews(),
      waiting: waitingBellNumbers(repo, () => now),
    );
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 1400);
    addTearDown(() async {
      t.view.reset();
      bell.dispose();
      repo.dispose();
      await db.close();
    });
    await t.pumpWidget(
      NotificationsScope(
        news: news,
        waiting: repo,
        counts: bell.value,
        child: MaterialApp(
          theme: AppTheme.theme,
          initialRoute: Routes.notifications,
          navigatorObservers: [pushes],
          routes: {
            Routes.notifications: (_) => const NotificationsRoute(),
            Routes.rememberedRecipients: (_) =>
                const Scaffold(body: Text('REMEMBERED SCREEN')),
          },
        ),
      ),
    );
    await settle(t);
  }

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 350));
    }
  }

  Future<void> hold(WidgetTester t, int n, String body, Duration ago) async {
    bridge.hold(heldIdFor(n), body, now.subtract(ago));
    await t.runAsync(() => repo.ingest());
    await settle(t);
  }

  Finder row(int n) => find.byKey(Key('waiting-row-${heldIdFor(n)}'));

  /// The compact row's Categorize button (PM 14-11-2026: no chip wall per row).
  Finder get categorizeButtons => find.byKey(const Key('choose-categorize'));

  Finder get sheetChips => find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('categorizeChip_');
  });

  /// Taps Categorize on the first row, picks the sheet's first category and saves. Returns its id.
  Future<String> pickViaSheet(WidgetTester t) async {
    await t.ensureVisible(categorizeButtons.first);
    await t.tap(categorizeButtons.first);
    await settle(t);
    final chipKey = sheetChips.first.evaluate().first.widget.key! as ValueKey<String>;
    await t.ensureVisible(sheetChips.first);
    await t.tap(sheetChips.first);
    await t.pump();
    await t.ensureVisible(find.byKey(const Key('categorizeSave')));
    await t.tap(find.byKey(const Key('categorizeSave')));
    await settle(t);
    return chipKey.value.replaceFirst('categorizeChip_', '');
  }

  Future<List<Map<String, Object?>>> live(WidgetTester t) async => (await t
      .runAsync(() => db.query('transactions', where: 'deleted_at IS NULL')))!;

  /// A ledger row without its own id and its timestamps, for comparing two paths.
  Map<String, Object?> comparable(Map<String, Object?> r) => {
    for (final e in r.entries)
      if (e.key != 'id' && !e.key.endsWith('_at')) e.key: e.value,
  };
}

void main() {
  final skip = !kAutoReadCompiled;

  testWidgets(
    'Parse in place: no toast, the row becomes a choose row with Later, nothing saved',
    (t) async {
      final e = _Env();
      await e.open(t);
      await e.hold(t, 1, kSampleSendMoney, const Duration(hours: 1));
      await t.tap(
        find.descendant(of: e.row(1), matching: find.text(kActionParse)),
      );
      await e.settle(t);
      expect(find.text(kToastParsed), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(kChooseCategoryTitle), findsOneWidget);
      expect(find.byKey(const Key('choose-later')), findsOneWidget);
      expect(find.byKey(const Key('choose-categorize')), findsOneWidget);
      expect(
        find.byKey(const Key('waiting-row-focused')),
        findsNothing,
      ); // no highlight
      expect(await e.live(t), isEmpty);
    },
    skip: skip,
  );

  testWidgets(
    'a pick through the row writes the same ledger row as the Categorize sheet; a second tap writes none',
    (t) async {
      // Path 1: the row.
      final a = _Env();
      await a.open(t);
      await a.hold(t, 1, kSampleSendMoney, const Duration(hours: 1));
      await t.tap(
        find.descendant(of: a.row(1), matching: find.text(kActionParse)),
      );
      await a.settle(t);
      expect(a.categorizeButtons, findsWidgets);
      final categoryId = await a.pickViaSheet(t);
      final viaRow = await a.live(t);
      expect(viaRow, hasLength(1));
      expect(
        find.text(noteRecorded('Sent Ksh 500 to JANE DOE')),
        findsOneWidget,
      ); // the quiet note
      expect(find.byType(SnackBar), findsNothing);
      expect(a.row(1), findsNothing);
      // The same pick called again (a stale tap) writes nothing more.
      final stale = WaitingItem(
        id: heldIdFor(1),
        kind: WaitingKind.waitingCategory,
        heldAt: a.now,
        parsed: sampleFields(1, a.now),
      );
      final ctx = t.element(find.byType(NotificationsPage));
      final acts = buildRealWaitingActions(ctx, a.repo);
      await t.runAsync(() => acts.onPickCategory!(stale, categoryId));
      expect(await a.live(t), hasLength(1));
      final rowMap = a.comparable(viaRow.single);
      expect(rowMap['display_code'], 'QWE1R2T3Y4');

      // Path 2: the Categorize sheet, the same message, a fresh database.
      await t.pumpWidget(const SizedBox());
      final b = _Env();
      await b.open(t);
      await b.hold(t, 1, kSampleSendMoney, const Duration(hours: 1));
      await t.runAsync(() => b.repo.parse(heldIdFor(1)));
      await b.settle(t);
      final ctxB = t.element(find.byType(NotificationsPage));
      final actsB = buildRealWaitingActions(ctxB, b.repo);
      actsB.onCategorize!(b.repo.itemById(heldIdFor(1))!);
      await b.settle(t);
      final sheetChip = find.byKey(ValueKey('categorizeChip_$categoryId'));
      await t.ensureVisible(sheetChip);
      await t.tap(sheetChip);
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('categorizeSave')));
      await t.tap(find.byKey(const Key('categorizeSave')));
      await b.settle(t);
      final viaSheet = await b.live(t);
      expect(viaSheet, hasLength(1));
      expect(
        b.comparable(viaSheet.single),
        rowMap,
      ); // amount, type, counterparty, category, code: identical
    },
    skip: skip,
  );

  testWidgets(
    'Later moves the row to To categorize (no Later there); a pick there records it',
    (t) async {
      final e = _Env();
      await e.open(t);
      await e.hold(t, 1, kSampleBuyGoods, const Duration(hours: 1));
      await t.tap(
        find.descendant(of: e.row(1), matching: find.text(kActionParse)),
      );
      await e.settle(t);
      await t.tap(find.byKey(const Key('choose-later')));
      await e.settle(t);
      expect(find.text(kNoteMovedToCategorize), findsOneWidget);
      expect(find.byKey(const Key('choose-later')), findsNothing);
      expect(find.text('$kHeadingToCategorize (1)'), findsOneWidget);
      expect(e.categorizeButtons, findsWidgets); // the same Categorize button
      expect(await e.live(t), isEmpty);
      await e.pickViaSheet(t);
      final rows = await e.live(t);
      expect(rows, hasLength(1));
      expect(rows.single['amount_cents'], 35000);
      expect(e.row(1), findsNothing);
    },
    skip: skip,
  );

  testWidgets(
    'airtime ON: no choose row, trail row with the kind text, snackbar stays and no switch card, Change in Settings opens '
    'Remembered with openAutoRecord, Undo goes to Recently deleted',
    (t) async {
      final e = _Env();
      e.airtimeOn = true;
      await e.open(t);
      await e.hold(t, 1, kSampleAirtime, const Duration(minutes: 5));
      await t.tap(
        find.descendant(of: e.row(1), matching: find.text(kActionParse)),
      );
      await e.settle(t);
      expect(find.text(kChooseCategoryTitle), findsNothing);
      expect(
        find.byType(SnackBar),
        findsOneWidget,
      ); // the auto-recorded snackbar stays
      expect(
        find.text(autoRecordedTitle('Ksh 200', other: false)),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('autoAirtimeCard')),
        findsNothing,
      ); // the switch card is gone (the switches live in Settings)
      expect(find.byKey(const Key('autoAirtimeSwitch')), findsNothing);
      expect(find.byKey(const Key('autoAirtimeSwitchOther')), findsNothing);
      expect(await e.live(t), hasLength(1));

      await t.ensureVisible(find.text(kAutoRecordedChangeInSettings));
      await t.tap(find.text(kAutoRecordedChangeInSettings));
      await e.settle(t);
      final pushed = e.pushes.pushed.last;
      expect(pushed.name, Routes.rememberedRecipients);
      expect((pushed.arguments as RememberedRouteArgs).openAutoRecord, isTrue);
      expect(find.text('REMEMBERED SCREEN'), findsOneWidget);
      Navigator.of(t.element(find.text('REMEMBERED SCREEN'))).pop();
      await e.settle(t);

      final undo = find.descendant(
        of: find.byKey(const Key('notif-list')),
        matching: find.text(kAutoRecordedUndo),
      );
      await t.ensureVisible(undo);
      await t.tap(undo);
      await e.settle(t);
      expect(await e.live(t), isEmpty);
      final all = (await t.runAsync(() => e.db.query('transactions')))!;
      expect(
        all.single['deleted_at'],
        isNotNull,
      ); // Recently deleted, restorable
    },
    skip: skip,
  );

  for (final on in [true, false]) {
    testWidgets(
      'Notifications shows no switch card and no switch, airtime ${on ? 'ON' : 'OFF'}, trail empty',
      (t) async {
        final e = _Env();
        e.airtimeOn = on;
        await e.open(t);
        expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
        expect(find.byKey(const Key('autoAirtimeSwitch')), findsNothing);
        expect(find.byKey(const Key('autoAirtimeSwitchOther')), findsNothing);
        expect(find.text('Auto-record airtime'), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.text(kAutoRecordedChangeInSettings), findsNothing);
      },
      skip: skip,
    );
  }

  testWidgets(
    'Notifications shows no switch card with a non-empty trail, switch ON then OFF; the link stays on the trail',
    (t) async {
      final e = _Env();
      e.airtimeOn = true;
      await e.open(t);
      await e.hold(t, 1, kSampleAirtime, const Duration(minutes: 5));
      await t.tap(find.descendant(of: e.row(1), matching: find.text(kActionParse)));
      await e.settle(t);
      expect(find.text(autoRecordedTitle('Ksh 200', other: false)), findsOneWidget);
      expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
      expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
      expect(find.byType(Switch), findsNothing);
      e.repo.airtime.setOn(false);
      await e.settle(t);
      expect(find.text(autoRecordedTitle('Ksh 200', other: false)), findsOneWidget);
      expect(find.text(kAutoRecordedChangeInSettings), findsOneWidget);
      expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
      expect(find.byType(Switch), findsNothing);
    },
    skip: skip,
  );

  testWidgets(
    'airtime OFF behaves as another row: choose row, Categorize opens the sheet with its one fixed category, no Later, no switch card',
    (t) async {
      final e = _Env();
      await e.open(t);
      await e.hold(t, 1, kSampleAirtime, const Duration(minutes: 5));
      await t.tap(
        find.descendant(of: e.row(1), matching: find.text(kActionParse)),
      );
      await e.settle(t);
      expect(find.text(kChooseCategoryTitle), findsOneWidget);
      expect(find.byKey(const Key('choose-later')), findsNothing);
      expect(find.byKey(const Key('autoAirtimeCard')), findsNothing);
      expect(find.byKey(const Key('autoAirtimeSwitch')), findsNothing);
      expect(e.categorizeButtons, findsOneWidget);
      await e.pickViaSheet(t);
      final rows = await e.live(t);
      expect(rows, hasLength(1));
      expect(rows.single['source_type'], 'AIRTIME');
    },
    skip: skip,
  );

  testWidgets(
    'Parse all turns every readable row into a choose row; the quiet note, no toast',
    (t) async {
      final e = _Env();
      await e.open(t);
      await e.hold(t, 1, kSampleSendMoney, const Duration(minutes: 1));
      await e.hold(t, 2, kSampleBuyGoods, const Duration(minutes: 2));
      await t.tap(find.byKey(const Key('parseAllBar')));
      await e.settle(t);
      expect(find.text(kChooseCategoryTitle), findsNWidgets(2));
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(noteReadMany(2)), findsOneWidget);
    },
    skip: skip,
  );
}
