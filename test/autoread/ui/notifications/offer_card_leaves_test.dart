@Tags(['autoread'])
library;

// U-OFFER (0.2.2 item 2, B-1): the offer card leaves To do as soon as "Ask me first" or "Auto-record" is
// tapped and stays gone after a rebuild, even when the engine still lists the person (the fake engine never
// drops a confirmed offer, like a stale read). A store failure keeps the card with today's toast. The pill
// gets the plain name (no number) and the category name. Paybill (D2): Ask first + Not now only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/notifications/notifications_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications/suggestions_controller.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/news_fakes.dart';
import '../../../support/redesign_fakes.dart';

const _peter = Offer(type: ReceiverType.sendMoney, key: '0745000222', name: 'PETER MWANGI', categoryId: 5, run: 3);
const _grace = Offer(type: ReceiverType.sendMoney, key: '0756000333', name: 'GRACE AKINYI', categoryId: 7, run: 3);
const _kplc = Offer(type: ReceiverType.payBill, key: '888880', name: 'KPLC', categoryId: 5, run: 3);
const _cat5 = 'Groceries';
const _cat7 = 'Family & friends';
String? _name(int id) => switch (id) { 5 => _cat5, 7 => _cat7, _ => null };

final _digit = RegExp(r'\d');

Widget _host(Widget child) => MaterialApp(
      navigatorKey: appNavigatorKey,
      theme: AppTheme.theme,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

/// A store whose setLevel throws (a broken prefs write).
class _ThrowingStore extends FakeRuleStore {
  @override
  Future<bool> setLevel(ReceiverType type, String key,
          {required String name,
          required RuleLevel level,
          int? categoryId,
          int? ceilingCents,
          List<int> chosenCategoryIds = const <int>[],
          required DateTime at}) async =>
      throw StateError('disk');
}

/// A store whose setLevel waits for [gate] (a slow prefs write).
class _SlowStore extends FakeRuleStore {
  final Completer<void> gate = Completer<void>();
  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name,
      required RuleLevel level,
      int? categoryId,
      int? ceilingCents,
      List<int> chosenCategoryIds = const <int>[],
      required DateTime at}) async {
    await gate.future;
    return super.setLevel(type, key,
        name: name, level: level, categoryId: categoryId, ceilingCents: ceilingCents, chosenCategoryIds: chosenCategoryIds, at: at);
  }
}

/// An engine that answers from the store like the real one (only Suggested people are offered), so the
/// answered mark can be seen to drop once the store has caught up.
class _StoreEngine extends FakeRuleEngine {
  _StoreEngine(this.store, {super.offers});
  final FakeRuleStore store;
  @override
  Future<List<Offer>> pendingOffers() async {
    final out = <Offer>[];
    for (final o in offers) {
      final r = await store.get(o.type, o.key);
      if (r == null || r.level == RuleLevel.suggested) out.add(o);
    }
    return out;
  }
}

/// An engine whose reads can be held, to finish an old read after a newer one.
class _HeldEngine extends FakeRuleEngine {
  _HeldEngine({super.offers});
  final List<Completer<void>> held = [];
  bool hold = false;
  @override
  Future<List<Offer>> pendingOffers() async {
    final snapshot = List<Offer>.unmodifiable(offers);
    if (hold) {
      final c = Completer<void>();
      held.add(c);
      await c.future;
    }
    return snapshot;
  }
}

void main() {
  late FakeRuleEngine engine;
  late FakeRuleStore store;
  late FakeCategoryRuleChangeNotice notice;

  setUp(() {
    engine = FakeRuleEngine(offers: [_peter, _grace], after: 3);
    store = FakeRuleStore();
    notice = FakeCategoryRuleChangeNotice();
    PillToast.dismissNow();
  });
  tearDown(() => debugAutoRecordUiOverride = null);

  SuggestionsController ctl({FakeRuleStore? s, RuleEngine? e}) {
    final c = SuggestionsController(engine: e ?? engine, store: s ?? store, clock: () => kFakeNow, notice: notice);
    addTearDown(c.dispose);
    return c;
  }

  Widget section(SuggestionsController c) =>
      _host(WaitingSection(waiting: const [], now: kFakeNow, actions: WaitingActions(suggestions: c, categoryNameOf: _name)));

  Future<void> pump(WidgetTester t, SuggestionsController c) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(360, 1400);
    addTearDown(t.view.reset);
    await t.pumpWidget(section(c));
    await t.pump();
  }

  Finder card(Offer o) => find.byKey(Key('suggestion-${o.type.code}-${o.key}'));

  Future<void> clearToast(WidgetTester t) async {
    PillToast.dismissNow();
    await t.pump(const Duration(seconds: 10));
  }

  for (final flag in [true, false]) {
    group('flag ${flag ? 'on' : 'off'}', () {
      setUp(() => debugAutoRecordUiOverride = flag);

      testWidgets('Ask me first: the card leaves, the next offer shows, and it stays gone after a rebuild', (t) async {
        final c = ctl();
        await pump(t, c);
        expect(card(_peter), findsOneWidget);
        expect(find.text('$kHeadingSuggestions (2)'), findsOneWidget);
        await t.tap(find.byKey(const Key('suggestion-confirm')));
        await t.pump();
        await t.pump();
        expect((await store.get(_peter.type, _peter.key))!.level, RuleLevel.askFirst);
        expect(card(_peter), findsNothing);
        expect(card(_grace), findsOneWidget);
        expect(find.text('$kHeadingSuggestions (1)'), findsOneWidget);
        // The fake engine still lists Peter (a stale read): a refresh and a fresh widget tree keep him gone.
        await c.refresh();
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(section(c));
        await t.pump();
        expect(card(_peter), findsNothing);
        expect(c.offers, [_grace]);
      });
    });
  }

  group('flag on', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('Auto-record (after Turn on): the card leaves and stays gone after a rebuild', (t) async {
      final c = ctl();
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      expect((await store.get(_peter.type, _peter.key))!.level, RuleLevel.autoRecord);
      expect(card(_peter), findsNothing);
      expect(card(_grace), findsOneWidget);
      await c.refresh();
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(section(c));
      await t.pump();
      expect(card(_peter), findsNothing);
    });

    testWidgets('Auto-record dialog cancelled: the card stays', (t) async {
      final c = ctl();
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmCancel')));
      await t.pumpAndSettle();
      expect(card(_peter), findsOneWidget);
      expect(c.offers, [_peter, _grace]);
    });

    testWidgets('the card leaves as soon as Ask me first is tapped, before the store write ends', (t) async {
      final s = _SlowStore();
      final c = ctl(s: s);
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      expect(card(_peter), findsNothing); // write still running
      s.gate.complete();
      await t.pump();
      await t.pump();
      expect(card(_peter), findsNothing);
      expect((await s.get(_peter.type, _peter.key))!.level, RuleLevel.askFirst);
    });

    testWidgets('store refuses Ask me first: the card comes back with the "not saved" toast, no pill', (t) async {
      store.detailsOn = false;
      final c = ctl();
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      await t.pump();
      expect(card(_peter), findsOneWidget);
      expect(find.text(kSuggestionNotSaved), findsOneWidget);
      expect(notice.calls, isEmpty);
      await clearToast(t);
    });

    testWidgets('store throws on Ask me first: the card comes back with the "not saved" toast', (t) async {
      final c = ctl(s: _ThrowingStore());
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(card(_peter), findsOneWidget);
      expect(find.text(kSuggestionNotSaved), findsOneWidget);
      expect(notice.calls, isEmpty);
      await clearToast(t);
    });

    testWidgets('store fails on Auto-record: the card comes back with the "not saved" toast', (t) async {
      final c = ctl(s: _ThrowingStore());
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pump();
      await t.pump();
      expect(card(_peter), findsOneWidget);
      expect(find.text(kSuggestionNotSaved), findsOneWidget);
      expect(notice.calls, isEmpty);
      await clearToast(t);
    });

    testWidgets('pill after Ask me first: plain name with no digits, and the category name', (t) async {
      final c = ctl();
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      final call = notice.calls.single;
      expect(call.name, 'PETER MWANGI');
      expect(call.name.contains(_digit), isFalse);
      expect(call.level, RuleLevel.askFirst);
      expect(call.categoryName, _cat5);
    });

    testWidgets('pill after Auto-record: plain name with no digits, and the category name', (t) async {
      final c = ctl();
      await pump(t, c);
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      final call = notice.calls.single;
      expect(call.name, 'PETER MWANGI');
      expect(call.name.contains(_digit), isFalse);
      expect(call.level, RuleLevel.autoRecord);
      expect(call.categoryName, _cat5);
    });

    testWidgets('Paybill (D2): Ask first + Not now only; Ask first makes the card leave, pill has the category', (t) async {
      engine.offers = [_kplc];
      final c = ctl();
      await pump(t, c);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
      expect(find.byKey(const Key('suggestion-confirm')), findsOneWidget);
      expect(find.byKey(const Key('suggestion-not-now')), findsOneWidget);
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      await t.pump();
      expect(card(_kplc), findsNothing);
      expect(notice.calls.single.categoryName, _cat5);
      expect(notice.calls.single.name, 'KPLC');
    });
  });

  group('controller', () {
    setUp(() => debugAutoRecordUiOverride = true);

    test('the mark drops once the store has caught up, so a later real offer shows again', () async {
      final e = _StoreEngine(store, offers: [_peter]);
      final c = ctl(e: e);
      await c.refresh();
      expect(c.offers, [_peter]);
      expect(await c.confirm(_peter, categoryName: _cat5), isTrue);
      expect(c.offers, isEmpty);
      // Peter goes back to Suggested (page) and is offered again: the card returns.
      await store.setLevel(_peter.type, _peter.key, name: _peter.name, level: RuleLevel.suggested, at: kFakeNow);
      await c.refresh();
      expect(c.offers, [_peter]);
    });

    test('an old read that ends after a newer one never brings the answered card back', () async {
      final e = _HeldEngine(offers: [_peter, _grace]);
      final c = ctl(e: e);
      await c.refresh();
      e.hold = true;
      final old = c.refresh(); // starts with Peter still listed, then waits
      await Future<void>.delayed(Duration.zero);
      e.hold = false;
      e.offers = [_grace]; // the store dropped Peter
      expect(await c.confirm(_peter), isTrue);
      expect(c.offers, [_grace]);
      for (final h in e.held) {
        h.complete();
      }
      await old;
      expect(c.offers, [_grace]);
    });

    test('a refused confirmAuto (flag off) never hides the card', () async {
      debugAutoRecordUiOverride = false;
      final c = ctl();
      await c.refresh();
      expect(await c.confirmAuto(_peter, categoryName: _cat5), isFalse);
      expect(c.offers, [_peter, _grace]);
    });

    test('hardTestDeps notice still works with the category argument (no crash, name kept)', () async {
      final old = FakeRuleChangeNotice();
      final c = SuggestionsController(engine: engine, store: store, clock: () => kFakeNow, notice: old);
      addTearDown(c.dispose);
      expect(await c.confirm(_peter, categoryName: _cat5), isTrue);
      expect(old.calls.single.name, 'PETER MWANGI');
    });
  });
}
