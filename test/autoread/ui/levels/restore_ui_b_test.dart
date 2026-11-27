@Tags(['autoread'])
library;

// 0.2.2 restore (slice B): the Settings Remembered row counts people, the Remembered page opens on the
// people tab when it holds people, and the "Auto-record was restored for N people. Keep it?" banner
// (Keep / Turn off) through a FAKE RestoredAutoRecordPort and the thin default over the rule store.
// Dormant flags: debugAutoRecordUiOverride per test. Invented names only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/levels/levels_people_count.dart';
import 'package:mmogo/autoread/ui/levels/restored_auto_record_port.dart';
import 'package:mmogo/autoread/ui/levels/restored_banner.dart';
import 'package:mmogo/autoread/ui/remembered_wiring.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/ui/copy/settings_copy.dart';
import 'package:mmogo/ui/screens/settings/remembered_hook_row.dart';
import 'package:mmogo/ui/shell/app_messenger.dart' show appNavigatorKey;
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';

class _FakePort implements RestoredAutoRecordPort {
  _FakePort(int n) : count = ValueNotifier<int>(n);
  @override
  final ValueNotifier<int> count;
  int kept = 0, off = 0;
  bool fail = false;
  @override
  Future<void> keepAll() async {
    if (fail) throw StateError('x');
    kept++;
    count.value = 0;
  }

  @override
  Future<void> turnOffAll() async {
    if (fail) throw StateError('x');
    off++;
    count.value = 0;
  }

  @override
  void dispose() {}
}

AirtimeAutoController _air() => AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {});

Future<void> _host(WidgetTester t, Widget child, {double scale = 1, String mode = 'light'}) async {
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', mode),
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<FakeRuleStore> _pendingStore() => hardTestStore([
  hardTestRule('0711000001', name: 'Tim', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 100000, autoPending: true),
  hardTestRule('0711000002', name: 'Grace', level: RuleLevel.autoRecord, categoryId: 2, autoPending: true),
  hardTestRule('0711000003', name: 'Gary', level: RuleLevel.askFirst, categoryId: 3), // own choice: never counted
]);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugAutoRecordUiOverride = null);

  group('B1 Settings row counts people', () {
    test('12 people with rules and 0 names: "12 people", no names part', () {
      final s = rememberedRowSub(const RememberedRowInfo(autoOn: 1, names: 0, people: 12));
      expect(s, 'Auto-record airtime: 1 of 2 on · 12 people$kRememberedRowTail');
      expect(s, isNot(contains('names')));
    });
    test('names shown only above 0; one person is singular', () {
      expect(
        rememberedRowSub(const RememberedRowInfo(autoOn: 0, names: 3, people: 1)),
        'Auto-record airtime: 0 of 2 on · 1 person · 3 names$kRememberedRowTail',
      );
      expect(
        rememberedRowSub(const RememberedRowInfo(autoOn: 0, names: 0, people: 0)),
        'Auto-record airtime: 0 of 2 on · 0 people$kRememberedRowTail',
      );
    });
    test('without people (no deps) the old line stays, a 0 names part is dropped', () {
      expect(rememberedRowSub(null), kRememberedRowSubtitle);
      expect(rememberedRowSub(const RememberedRowInfo(autoOn: 2, names: 4)), 'Auto-record airtime: 2 of 2 on · 4 names$kRememberedRowTail');
    });
    test('levelsPeopleCount: rules + remembered without rule, each once; Pochi rule needs a remembered name', () async {
      final store = await hardTestStore([
        hardTestRule('0711000001', level: RuleLevel.askFirst, categoryId: 1),
        hardTestRule('0711000002', level: RuleLevel.autoRecord, categoryId: 1),
        hardTestRule('LONE POCHI', type: ReceiverType.pochi, level: RuleLevel.askFirst, categoryId: 1),
      ]);
      final base = hardTestDeps(store: store);
      final d = LevelsDeps(
        store: store,
        history: base.history,
        categories: base.categories,
        suggest: base.suggest,
        known: () async => [
          const KnownPerson(type: ReceiverType.sendMoney, key: '0711000001', name: 'Tim'), // has a rule: once
          for (var i = 0; i < 9; i++) KnownPerson(type: ReceiverType.sendMoney, key: '07220000$i', name: 'P$i'),
        ],
      );
      expect(await levelsPeopleCount(d), 11); // 2 rules + 9 suggested; the lone Pochi is not listed
    });
    test('the app hook reads the people count from the deps', () async {
      final store = await hardTestStore([hardTestRule('0711000001', level: RuleLevel.askFirst, categoryId: 1)]);
      final info = await rememberedRowHookFor(
        _air(),
        memory: RecipientMemory(),
        levels: hardTestDeps(store: store),
      ).load();
      expect(info.people, 1);
      expect(info.names, 0);
    });
  });

  group('B2 Remembered opens on the people tab', () {
    Future<void> page(WidgetTester t, FakeRuleStore store, {Object? args}) async {
      debugAutoRecordUiOverride = true;
      await _host(
        t,
        rememberedPageFor(
          _air(),
          args: args,
          memory: RecipientMemory(),
          levels: hardTestDeps(store: store),
        ),
      );
    }

    testWidgets('people hold rules: the people tab shows first', (t) async {
      await page(t, await _pendingStore());
      expect(find.byKey(const Key('rememberedEmpty')), findsNothing);
      expect(find.byKey(const Key('levelsTab')).hitTestable(), findsOneWidget);
    });

    testWidgets('nobody anywhere: the recipients tab, as today', (t) async {
      await page(t, FakeRuleStore());
      expect(find.byKey(const Key('rememberedEmpty')).hitTestable(), findsOneWidget);
    });

    testWidgets('a tab the person already tapped is not overridden', (t) async {
      await page(t, await _pendingStore());
      await t.tap(find.byKey(const Key('rememberedTab0')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rememberedEmpty')).hitTestable(), findsOneWidget);
    });
  });

  group('B3 restored banner', () {
    Future<void> banner(WidgetTester t, RestoredAutoRecordPort p, {bool details = true, double scale = 1, String mode = 'light'}) => _host(
      t,
      RestoredBanner(bulk: RuleBulkOps(FakeRuleStore()), port: p, detailsOn: details),
      scale: scale,
      mode: mode,
    );

    testWidgets('draws the draft words with Keep and Turn off, 44 px targets', (t) async {
      debugAutoRecordUiOverride = true;
      await banner(t, _FakePort(3));
      expect(find.text('Auto-record was restored for 3 people. Keep it?'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Turn off'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('restoredKeep'))).height, greaterThanOrEqualTo(44));
      expect(find.text('Auto-record was restored for 1 person. Keep it?'), findsNothing);
    });

    testWidgets('one person is singular', (t) async {
      debugAutoRecordUiOverride = true;
      await banner(t, _FakePort(1));
      expect(find.text(hardRestoredBanner(1)), findsOneWidget);
      expect(hardRestoredBanner(1), contains('1 person'));
    });

    testWidgets('count 0, flag off or details off: nothing drawn', (t) async {
      debugAutoRecordUiOverride = true;
      await banner(t, _FakePort(0));
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
      await banner(t, _FakePort(2), details: false);
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
      debugAutoRecordUiOverride = false;
      await banner(t, _FakePort(2));
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
    });

    testWidgets('Keep calls keepAll once and the banner hides', (t) async {
      debugAutoRecordUiOverride = true;
      final p = _FakePort(2);
      await banner(t, p);
      await t.tap(find.byKey(const Key('restoredKeep')));
      await t.pumpAndSettle();
      expect([p.kept, p.off], [1, 0]);
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
    });

    testWidgets('Turn off calls turnOffAll once and the banner hides', (t) async {
      debugAutoRecordUiOverride = true;
      final p = _FakePort(2);
      await banner(t, p);
      await t.tap(find.byKey(const Key('restoredTurnOff')));
      await t.pumpAndSettle();
      expect([p.kept, p.off], [0, 1]);
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
    });

    testWidgets('a failed write keeps the banner and says so', (t) async {
      debugAutoRecordUiOverride = true;
      final p = _FakePort(2)..fail = true;
      await banner(t, p);
      await t.tap(find.byKey(const Key('restoredKeep')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('restoredBanner')), findsOneWidget);
      expect(find.text('Could not save. Try again.'), findsOneWidget);
      await t.pump(const Duration(seconds: 15));
      await t.pumpAndSettle();
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('200% text, $mode: no overflow', (t) async {
        debugAutoRecordUiOverride = true;
        await banner(t, _FakePort(12), scale: 2, mode: mode);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('restoredKeep')), findsOneWidget);
      });
    }

    testWidgets('thin default over the store: Keep makes Auto-record, Gary untouched, banner hides', (t) async {
      debugAutoRecordUiOverride = true;
      final store = await _pendingStore();
      await _host(t, RestoredBanner(bulk: RuleBulkOps(store, now: () => kHardTestNow)));
      expect(find.text(hardRestoredBanner(2)), findsOneWidget);
      await t.tap(find.byKey(const Key('restoredKeep')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
      expect((await store.get(ReceiverType.sendMoney, '0711000001'))!.level, RuleLevel.autoRecord);
      expect((await store.get(ReceiverType.sendMoney, '0711000001'))!.autoPending, isFalse);
      expect((await store.get(ReceiverType.sendMoney, '0711000003'))!.level, RuleLevel.askFirst);
    });

    testWidgets('thin default over the store: Turn off puts everyone on Ask first, mark cleared', (t) async {
      debugAutoRecordUiOverride = true;
      final store = await _pendingStore();
      await _host(t, RestoredBanner(bulk: RuleBulkOps(store, now: () => kHardTestNow)));
      await t.tap(find.byKey(const Key('restoredTurnOff')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('restoredBanner')), findsNothing);
      for (final k in ['0711000001', '0711000002']) {
        final r = (await store.get(ReceiverType.sendMoney, k))!;
        expect([r.level, r.autoPending], [RuleLevel.askFirst, false]);
      }
    });

    testWidgets('on the Remembered page the old review line is gone (one banner only)', (t) async {
      debugAutoRecordUiOverride = true;
      final store = await _pendingStore();
      await _host(
        t,
        rememberedPageFor(
          _air(),
          memory: RecipientMemory(),
          levels: hardTestDeps(store: store),
        ),
      );
      expect(find.byKey(const Key('restoredBanner')), findsOneWidget);
      expect(find.byKey(const Key('reviewLine')), findsNothing);
      expect(find.textContaining('were on Auto-record in your backup'), findsNothing);
    });
  });
}
