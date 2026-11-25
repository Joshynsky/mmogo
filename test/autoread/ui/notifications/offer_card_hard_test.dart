@Tags(['autoread'])
library;

// U2 (0.2.2 item 2): the offer card with Auto-record (mock offer-a, offer-dlg). Paybill (D2), flag off or
// unknown category = today's card exactly. Controller: confirmAuto refuses Paybill and flag off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/notifications/notifications_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications/suggestion_card.dart';
import 'package:mmogo/autoread/ui/notifications/suggestions_controller.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/news_fakes.dart';

const _sm = Offer(type: ReceiverType.sendMoney, key: '0712', name: 'Tim', categoryId: 5, run: 3);
const _pb = Offer(type: ReceiverType.payBill, key: '888880', name: 'KPLC', categoryId: 5, run: 3);
const _till = Offer(type: ReceiverType.buyGoods, key: '5544', name: 'Mboga', categoryId: 5, run: 3);
const _who = 'Tim ***'; // nameWithMask('Tim', '0712')
const _cat = 'Family & friends';
String? _name(int id) => id == 5 ? _cat : null;

Widget _host(Widget child, {double scale = 1.0, TextDirection dir = TextDirection.ltr}) => MaterialApp(
      navigatorKey: appNavigatorKey,
      theme: AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
        child: Directionality(textDirection: dir, child: c!),
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 1400);
  addTearDown(t.view.reset);
}

/// A store whose setLevel throws (a broken prefs write).
class _ThrowingStore extends FakeRuleStore {
  int calls = 0;
  @override
  Future<bool> setLevel(ReceiverType type, String key,
      {required String name,
      required RuleLevel level,
      int? categoryId,
      int? ceilingCents,
      List<int> chosenCategoryIds = const <int>[],
      required DateTime at}) async {
    calls++;
    throw StateError('disk');
  }
}

/// An engine whose suggestAfter read can be made to throw.
class _FlakyAfterEngine extends FakeRuleEngine {
  _FlakyAfterEngine({super.offers, super.after});
  bool failAfter = false;
  @override
  Future<int> suggestAfter() async => failAfter ? throw StateError('prefs') : after;
}

void main() {
  late FakeRuleEngine engine;
  late FakeRuleStore store;
  late FakeRuleChangeNotice notice;

  setUp(() {
    engine = FakeRuleEngine(offers: [_sm], after: 4);
    store = FakeRuleStore();
    notice = FakeRuleChangeNotice();
    PillToast.dismissNow();
  });
  tearDown(() => debugAutoRecordUiOverride = null);

  SuggestionsController ctl({RuleChangeNotice? n, void Function(Offer)? change, FakeRuleStore? s}) {
    final c = SuggestionsController(engine: engine, store: s ?? store, clock: () => kFakeNow, notice: n ?? notice, onChangeCeiling: change);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> pumpSection(WidgetTester t, SuggestionsController c, {double scale = 1.0, TextDirection dir = TextDirection.ltr}) async {
    await t.pumpWidget(_host(
      WaitingSection(waiting: const [], now: kFakeNow, actions: WaitingActions(suggestions: c, categoryNameOf: _name)),
      scale: scale,
      dir: dir,
    ));
    await t.pump();
  }

  Future<void> clearToast(WidgetTester t) async {
    PillToast.dismissNow();
    await t.pump(const Duration(seconds: 10));
  }

  group("today's card stays exactly", () {
    testWidgets('flag off: Ask first saves as today and shows no notice', (t) async {
      _size(t, 360);
      debugAutoRecordUiOverride = false;
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      expect((await store.get(ReceiverType.sendMoney, '0712'))!.level, RuleLevel.askFirst);
      expect(notice.calls, isEmpty);
      expect(PillToast.isShowing, isFalse);
    });

    testWidgets('flag off: today title, body, one Ask first, no Auto-record', (t) async {
      _size(t, 360);
      debugAutoRecordUiOverride = false;
      await pumpSection(t, ctl());
      expect(find.text(kSuggestionTitle), findsOneWidget);
      expect(find.text(suggestionBody(_who, _cat, 3)), findsOneWidget);
      expect(find.text(kSuggestionConfirm), findsOneWidget);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
      expect(find.text(hardOfferTitle(_who)), findsNothing);
    });

    testWidgets('flag on, Paybill (D2): today card, no Auto-record button', (t) async {
      _size(t, 360);
      debugAutoRecordUiOverride = true;
      engine.offers = [_pb];
      await pumpSection(t, ctl());
      expect(find.text(kSuggestionTitle), findsOneWidget);
      expect(find.text(suggestionBody('KPLC', _cat, 3)), findsOneWidget);
      expect(find.text(kSuggestionConfirm), findsOneWidget);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
      expect(find.text(kHardOfferAutoRecord), findsNothing);
      expect(find.textContaining('yet'), findsNothing);
    });

    testWidgets('flag on, unknown category: today card (no category to confirm)', (t) async {
      _size(t, 360);
      debugAutoRecordUiOverride = true;
      engine.offers = [const Offer(type: ReceiverType.sendMoney, key: '0712', name: 'Tim', categoryId: 99, run: 3)];
      await pumpSection(t, ctl());
      expect(find.text(kSuggestionTitle), findsOneWidget);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
    });

    testWidgets('card alone without onAutoRecord: today card even with the flag on', (t) async {
      _size(t, 360);
      debugAutoRecordUiOverride = true;
      await t.pumpWidget(_host(SuggestionCard(offer: _sm, categoryName: _cat, onNotNow: () {}, onConfirm: () {})));
      expect(find.text(kSuggestionTitle), findsOneWidget);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
    });
  });

  group('Auto-record offer (flag on)', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('title, body with the Settings number, Ask me first then Auto-record, Not now alone at the right', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      expect(find.text(hardOfferTitle(_who)), findsOneWidget);
      expect(find.text(hardOfferBody(_who, _cat, 4)), findsOneWidget); // engine.after = 4, the run is 3
      expect(find.text(kSuggestionTitle), findsNothing);
      final ask = t.getRect(find.byKey(const Key('suggestion-confirm')));
      final auto = t.getRect(find.byKey(const Key('suggestion-auto')));
      final not = t.getRect(find.byKey(const Key('suggestion-not-now')));
      expect(find.descendant(of: find.byKey(const Key('suggestion-confirm')), matching: find.text(kHardOfferAskFirst)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('suggestion-auto')), matching: find.text(kHardOfferAutoRecord)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('suggestion-not-now')), matching: find.text(kHardOfferNotNow)), findsOneWidget);
      expect(ask.top, auto.top); // one row
      expect(ask.right, lessThan(auto.left)); // Ask me first first
      expect((ask.width - auto.width).abs(), lessThan(1)); // two equal big buttons
      expect(not.top, greaterThanOrEqualTo(auto.bottom)); // own line, below
      expect(360 - not.right, lessThan(30)); // end edge (right in LTR)
      for (final r in [ask, auto, not]) {
        expect(r.height, greaterThanOrEqualTo(44));
        expect(r.width, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('RTL: Not now sits at the end edge (left)', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl(), dir: TextDirection.rtl);
      final not = t.getRect(find.byKey(const Key('suggestion-not-now')));
      expect(not.left, lessThan(30));
      final ask = t.getRect(find.byKey(const Key('suggestion-confirm')));
      final auto = t.getRect(find.byKey(const Key('suggestion-auto')));
      expect(auto.right, lessThan(ask.left)); // reading order kept: Ask me first starts the row
    });

    testWidgets('Till can hold Auto-record: the button shows; name not masked for a non Send Money kind', (t) async {
      _size(t, 360);
      engine.offers = [_till];
      await pumpSection(t, ctl());
      expect(find.text(hardOfferTitle('Mboga')), findsOneWidget);
      expect(find.byKey(const Key('suggestion-auto')), findsOneWidget);
    });

    testWidgets('screen reader: card label is the title and body; buttons say who', (t) async {
      _size(t, 360);
      final h = t.ensureSemantics();
      await pumpSection(t, ctl());
      expect(find.bySemanticsLabel('${hardOfferTitle(_who)} ${hardOfferBody(_who, _cat, 4)}'), findsOneWidget);
      expect(find.bySemanticsLabel('$kHardOfferAskFirst: $_who'), findsOneWidget);
      expect(find.bySemanticsLabel('$kHardOfferAutoRecord: $_who'), findsOneWidget);
      h.dispose();
    });

    for (final (w, scale) in [(360.0, 1.0), (360.0, 2.0), (320.0, 2.0), (500.0, 2.0)]) {
      testWidgets('no overflow, buttons inside the card: width $w, text x$scale', (t) async {
        _size(t, w);
        await pumpSection(t, ctl(), scale: scale);
        expect(t.takeException(), isNull);
        final card = t.getRect(find.byKey(const Key('suggestion-SM-0712')));
        for (final k in ['suggestion-confirm', 'suggestion-auto', 'suggestion-not-now']) {
          final r = t.getRect(find.byKey(Key(k)));
          expect(r.right, lessThanOrEqualTo(card.right));
          expect(r.left, greaterThanOrEqualTo(card.left));
          expect(r.height, greaterThanOrEqualTo(44));
        }
        expect(find.text(kHardOfferAutoRecord), findsOneWidget);
      });
    }

    for (final b in Brightness.values) {
      testWidgets('theme $b: Auto-record filled in the palette primary, Ask me first outlined; both carry words', (t) async {
        _size(t, 360);
        await t.pumpWidget(MaterialApp(
          theme: AppTheme.theme,
          builder: (context, c) => MediaQuery(data: MediaQuery.of(context).copyWith(platformBrightness: b), child: c!),
          home: Scaffold(
            body: SuggestionCard(offer: _sm, categoryName: _cat, onNotNow: () {}, onConfirm: () {}, onAutoRecord: () {}),
          ),
        ));
        expect(t.takeException(), isNull);
        final ctx = t.element(find.byKey(const Key('suggestion-auto')));
        final p = AppPalette.of(ctx);
        Material mat(String k) => t.widget<Material>(find.descendant(of: find.byKey(Key(k)), matching: find.byType(Material)).first);
        expect(mat('suggestion-auto').color, p.primary);
        expect(mat('suggestion-confirm').color, p.surface);
        expect(find.text(kHardOfferAutoRecord), findsOneWidget);
        expect(find.text(kHardOfferAskFirst), findsOneWidget);
      });
    }

    testWidgets('Auto-record opens the confirm dialog with no ceiling; Cancel changes nothing', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      // The dialog title reads like the card title (both "Auto-record {name}?"): find it by its key.
      expect((t.widget<Text>(find.byKey(const Key('hardConfirmTitle')))).data, hardConfirmTitle(_who));
      expect(find.text(hardConfirmBodyNoCeiling(_who, _cat)), findsOneWidget);
      await t.tap(find.byKey(const Key('hardConfirmCancel')));
      await t.pumpAndSettle();
      expect(await store.get(ReceiverType.sendMoney, '0712'), isNull);
      expect(notice.calls, isEmpty);
      expect(find.byKey(const Key('suggestion-auto')), findsOneWidget);
    });

    testWidgets('Turn on: Auto-record saved with the offered category, no ceiling; the notice shows', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pumpAndSettle();
      final r = await store.get(ReceiverType.sendMoney, '0712');
      expect(r!.level, RuleLevel.autoRecord);
      expect(r.categoryId, 5);
      expect(r.ceilingCents, isNull);
      expect(notice.calls, hasLength(1));
      expect(notice.calls.single.name, 'Tim');
      expect(notice.calls.single.level, RuleLevel.autoRecord);
      expect(notice.calls.single.ceilingCents, isNull);
      expect(notice.calls.single.onChangeCeiling, isNull); // nothing wired: no Change ceiling
      expect(PillToast.isShowing, isFalse); // no "not saved"
    });

    testWidgets('Ask me first: Ask first with the offered category, then the notice once (stage 1)', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      final r = await store.get(ReceiverType.sendMoney, '0712');
      expect(r!.level, RuleLevel.askFirst);
      expect(r.categoryId, 5);
      expect(notice.calls, hasLength(1));
      expect(notice.calls.single.name, 'Tim');
      expect(notice.calls.single.level, RuleLevel.askFirst);
      expect(notice.calls.single.ceilingCents, isNull);
      expect(notice.calls.single.onChangeCeiling, isNull);
    });

    testWidgets('Ask me first refused by the store: "not saved" toast, no notice', (t) async {
      _size(t, 360);
      store.detailsOn = false;
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      await t.pump();
      expect(find.text(kSuggestionNotSaved), findsOneWidget);
      expect(notice.calls, isEmpty);
      await clearToast(t);
    });

    testWidgets('Paybill (D2) card: Ask first shows the notice too', (t) async {
      _size(t, 360);
      engine.offers = [_pb];
      await pumpSection(t, ctl());
      expect(find.text(kSuggestionTitle), findsOneWidget); // today's card
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      expect((await store.get(ReceiverType.payBill, '888880'))!.level, RuleLevel.askFirst);
      expect(notice.calls, hasLength(1));
      expect(notice.calls.single.name, 'KPLC');
      expect(notice.calls.single.level, RuleLevel.askFirst);
    });

    testWidgets('section re-check: flag turned off after drawing, Auto-record tap opens no dialog, saves nothing', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      debugAutoRecordUiOverride = false; // the button is still on screen (no rebuild yet)
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hardConfirmTitle')), findsNothing);
      expect(await store.get(ReceiverType.sendMoney, '0712'), isNull);
      expect(notice.calls, isEmpty);
    });

    testWidgets('Not now is today notNow', (t) async {
      _size(t, 360);
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-not-now')));
      await t.pump();
      await t.pump();
      expect(engine.calls, ['notNow:SM.0712']);
      expect(find.byKey(const Key('suggestion-auto')), findsNothing);
    });

    testWidgets('store refuses: the existing "not saved" toast, no notice', (t) async {
      _size(t, 360);
      store.detailsOn = false;
      await pumpSection(t, ctl());
      await t.tap(find.byKey(const Key('suggestion-auto')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardConfirmOk')));
      await t.pump();
      await t.pump();
      expect(find.text(kSuggestionNotSaved), findsOneWidget);
      expect(notice.calls, isEmpty);
      await clearToast(t);
    });
  });

  group('controller confirmAuto', () {
    test('refuses Paybill without touching the store', () async {
      debugAutoRecordUiOverride = true;
      final s = _ThrowingStore();
      final c = SuggestionsController(engine: engine, store: s, notice: notice);
      expect(await c.confirmAuto(_pb), isFalse);
      expect(s.calls, 0);
      expect(notice.calls, isEmpty);
      c.dispose();
    });

    test('refuses while the UI flag is off', () async {
      debugAutoRecordUiOverride = false;
      final c = SuggestionsController(engine: engine, store: store, notice: notice);
      expect(await c.confirmAuto(_sm), isFalse);
      expect(await store.get(ReceiverType.sendMoney, '0712'), isNull);
      expect(notice.calls, isEmpty);
      c.dispose();
    });

    test('a throwing store gives false, no notice', () async {
      debugAutoRecordUiOverride = true;
      final s = _ThrowingStore();
      final c = SuggestionsController(engine: engine, store: s, notice: notice);
      expect(await c.confirmAuto(_sm), isFalse);
      expect(s.calls, 1);
      expect(notice.calls, isEmpty);
      c.dispose();
    });

    test('success: the notice carries Change ceiling when wired, for this offer', () async {
      debugAutoRecordUiOverride = true;
      final opened = <Offer>[];
      final c = SuggestionsController(engine: engine, store: store, notice: notice, onChangeCeiling: opened.add, clock: () => kFakeNow);
      expect(await c.confirmAuto(_till), isTrue);
      expect(notice.calls.single.onChangeCeiling, isNotNull);
      notice.calls.single.onChangeCeiling!();
      expect(opened, [_till]);
      final r = await store.get(ReceiverType.buyGoods, '5544');
      expect(r!.level, RuleLevel.autoRecord);
      expect(r.categoryId, 5);
      c.dispose();
    });

    test('suggestAfter is read from the engine (the Settings number)', () async {
      final c = SuggestionsController(engine: engine, store: store);
      await c.refresh();
      expect(c.suggestAfter, 4);
      c.dispose();
    });

    test('a failed suggestAfter read keeps the old number; offers still refresh', () async {
      final e = _FlakyAfterEngine(offers: [_sm], after: 4);
      final c = SuggestionsController(engine: e, store: store);
      await c.refresh();
      expect(c.suggestAfter, 4);
      e.failAfter = true;
      e.offers = [_sm, _till];
      await c.refresh();
      expect(c.suggestAfter, 4);
      expect(c.offers, [_sm, _till]);
      c.dispose();
    });

    test('default notice is the C0 stand-in', () {
      final c = SuggestionsController(engine: engine, store: store);
      expect(c.notice, isA<PillToastRuleChangeNotice>());
      c.dispose();
    });
  });
}
