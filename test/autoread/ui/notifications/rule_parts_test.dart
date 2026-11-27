@Tags(['autoread'])
library;

// S2d: the rule parts of the Notifications page, on fakes (no real rule store).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart' show debugAutoRecordUiOverride;
import 'package:mmogo/autoread/logic/airtime_auto.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_rule_engine.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_engine.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/auto_recorded_row.dart';
import 'package:mmogo/autoread/ui/notifications/notifications_rule_copy.dart';
import 'package:mmogo/autoread/ui/notifications/suggestion_card.dart';
import 'package:mmogo/autoread/ui/notifications/suggestions_controller.dart';
import 'package:mmogo/autoread/ui/todo_copy.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../../support/news_fakes.dart';
import '../../../support/waiting_fakes.dart';

Widget _host(Widget child, {double scale = 1.0}) => MaterialApp(
  theme: AppTheme.theme,
  builder: (context, c) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: c!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void _size(WidgetTester t, double w) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(w, 1400);
  addTearDown(t.view.reset);
}

const _offer = Offer(type: ReceiverType.sendMoney, key: '0712', name: 'Tim', categoryId: 5, run: 3);
String? _name(int id) => id == 5 ? 'Family & friends' : null;

WaitingItem _item(int n) {
  final at = kFakeNow.subtract(const Duration(minutes: 20));
  return WaitingItem(id: heldIdFor(n), kind: WaitingKind.waitingCategory, heldAt: at, parsed: sampleFields(0, at));
}

const _hint = RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: '0712', suggested: [5]);

AirtimeAutoController _air(List<AutoRecorded> trail) {
  final c = AirtimeAutoController(onSwitch: (_) async {}, onSwitchOther: (_) async {}, onUndo: (_) async {}, now: () => kFakeNow);
  c.setTrail(trail);
  return c;
}

Widget _section(List<WaitingItem> items, WaitingActions a, {double scale = 1.0}) => _host(
  WaitingSection(waiting: items, now: kFakeNow, actions: a),
  scale: scale,
);

List<String> _texts(WidgetTester t) => [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? ''];

int _buttons(Finder inside) => find.descendant(of: inside, matching: find.byType(InkWell)).evaluate().length;

void main() {
  // The Auto-record screens are live since the 0.2.2 flip; these tests cover the Ask first / Suggested screens.
  setUp(() => debugAutoRecordUiOverride = false);
  tearDown(() => debugAutoRecordUiOverride = null);

  late FakeRuleEngine engine;
  late FakeRuleStore store;

  setUp(() {
    engine = FakeRuleEngine(offers: [_offer]);
    store = FakeRuleStore();
  });

  WaitingActions actions({SuggestionsController? s, List<String>? log, AirtimeAutoController? air}) => WaitingActions(
    suggestions: s,
    airtime: air,
    onChangeInSettings: air == null ? null : () {},
    ruleHintFor: (w) => _hint,
    categoryNameOf: _name,
    onAskFirstYes: (w, h) async => log?.add('yes'),
    onAskFirstChange: (w, h) => log?.add('change'),
    onAskFirstLater: (w, h) => log?.add('later'),
  );

  group('sections hide when empty', () {
    testWidgets('no offers, no items: no Suggestions, no Ask first, no Recorded automatically', (t) async {
      _size(t, 360);
      engine.offers = [];
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c, air: _air([]))));
      await t.pump();
      final all = _texts(t).join('|');
      expect(all, isNot(contains(kHeadingSuggestions)));
      expect(all, isNot(contains(kHeadingToConfirm)));
      expect(all, isNot(contains('Recently recorded')));
    });

    testWidgets('each section shows with its item', (t) async {
      _size(t, 360);
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(
        _section(
          [_item(1)],
          actions(
            s: c,
            air: _air([AutoRecorded(rowId: 1, amountCents: 5000, at: kFakeNow)]),
          ),
        ),
      );
      await t.pump();
      final all = _texts(t);
      expect(all, contains('$kHeadingToConfirm (1)'));
      expect(all, contains('$kHeadingSuggestions (1)'));
      expect(all, contains('Recently recorded (1)'));
    });
  });

  group('N6 Recorded automatically count', () {
    testWidgets('counts only entries still recorded; undone rows stay listed but are not counted', (t) async {
      _size(t, 360);
      await t.pumpWidget(
        _section(
          [],
          actions(
            air: _air([
              AutoRecorded(rowId: 1, amountCents: 5000, at: kFakeNow),
              AutoRecorded(rowId: 2, amountCents: 6000, at: kFakeNow, inRecentlyDeleted: true),
              AutoRecorded(rowId: 3, amountCents: 7000, at: kFakeNow, inRecentlyDeleted: true),
            ]),
          ),
        ),
      );
      await t.pump();
      final all = _texts(t);
      expect(all, contains('Recently recorded (1)'));
      expect(find.byType(AutoRecordedRow), findsNWidgets(3));
    });
  });

  group('Nothing waiting placement', () {
    testWidgets('empty: bottom card, no top line', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section([], actions()));
      expect(find.byKey(const Key('todo-empty')), findsOneWidget);
      expect(find.text(kNothingWaiting), findsOneWidget);
      expect(find.byKey(const Key('nothing-waiting-top')), findsNothing);
      expect(find.text(kTodoEmptyTitle), findsOneWidget);
    });

    testWidgets('with a Recorded automatically item: one line at the top, above that section', (t) async {
      _size(t, 360);
      await t.pumpWidget(_section([], actions(air: _air([AutoRecorded(rowId: 1, amountCents: 5000, at: kFakeNow)]))));
      expect(find.byKey(const Key('todo-empty')), findsNothing);
      final top = t.getTopLeft(find.byKey(const Key('nothing-waiting-top'))).dy;
      final auto = t.getTopLeft(find.text('Recently recorded (1)')).dy;
      expect(top, lessThan(auto));
    });

    testWidgets('a waiting offer means something is waiting: no Nothing waiting', (t) async {
      _size(t, 360);
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c)));
      await t.pump();
      expect(find.text(kNothingWaiting), findsNothing);
      expect(find.byKey(const Key('todo-empty')), findsNothing);
    });
  });

  group('suggestion card', () {
    testWidgets('F2: a full number shows masked, never raw', (t) async {
      _size(t, 360);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SuggestionCard(
              offer: const Offer(type: ReceiverType.sendMoney, key: '0722000555', name: 'LUCY AKINYI', categoryId: 5, run: 3),
              categoryName: 'Food',
              onNotNow: () {},
              onConfirm: () {},
            ),
          ),
        ),
      );
      expect(find.textContaining('LUCY AKINYI 0722***555'), findsOneWidget);
      expect(find.textContaining('0722000555'), findsNothing);
    });
    testWidgets('layout: title, body, Not now far left, one confirm far right', (t) async {
      _size(t, 360);
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c)));
      await t.pump();
      expect(find.text(kSuggestionTitle), findsOneWidget);
      expect(find.text(suggestionBody('Tim ***', 'Family & friends', 3)), findsOneWidget);
      final title = t.getTopLeft(find.text(kSuggestionTitle)).dy;
      final notNow = t.getRect(find.byKey(const Key('suggestion-not-now')));
      final confirm = t.getRect(find.byKey(const Key('suggestion-confirm')));
      expect(title, lessThan(notNow.top));
      expect(notNow.top, lessThan(confirm.top));
      expect(notNow.left, lessThan(60));
      expect(360 - confirm.right, lessThan(30));
      expect(find.text('$kHeadingSuggestions (1)'), findsOneWidget);
    });

    testWidgets('Not now calls the engine and the card goes', (t) async {
      _size(t, 360);
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c)));
      await t.pump();
      await t.tap(find.byKey(const Key('suggestion-not-now')));
      await t.pump();
      await t.pump();
      expect(engine.calls, ['notNow:SM.0712']);
      expect(find.text(kSuggestionTitle), findsNothing);
    });

    testWidgets('confirm sets Ask first in the store with the offered category', (t) async {
      _size(t, 360);
      final c = SuggestionsController(engine: engine, store: store, clock: () => kFakeNow);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c)));
      await t.pump();
      await t.tap(find.byKey(const Key('suggestion-confirm')));
      await t.pump();
      final r = await store.get(ReceiverType.sendMoney, '0712');
      expect(r!.level, RuleLevel.askFirst);
      expect(r.categoryId, 5);
    });

    testWidgets('suggestions switched off: no card', (t) async {
      _size(t, 360);
      engine.enabled = false;
      final c = SuggestionsController(engine: engine, store: store);
      addTearDown(c.dispose);
      await t.pumpWidget(_section([], actions(s: c)));
      await t.pump();
      expect(find.text(kSuggestionTitle), findsNothing);
    });
  });

  group('Ask first row', () {
    testWidgets('three buttons, order Change category, Not now, Yes; Yes far right; taps wired', (t) async {
      _size(t, 360);
      final log = <String>[];
      await t.pumpWidget(_section([_item(1)], actions(log: log)));
      expect(find.text(askFirstTitle('Family & friends')), findsOneWidget);
      expect(_buttons(find.byKey(const Key('ask-first-actions'))), 3);
      final change = t.getRect(find.byKey(const Key('ask-first-change')));
      final later = t.getRect(find.byKey(const Key('ask-first-later')));
      final yes = t.getRect(find.byKey(const Key('ask-first-yes')));
      // Reading order (line, then left): Change category, Not now, Yes. The test font is wide, so the
      // buttons may wrap to several lines; Yes is always the last one, at the right edge of its line.
      int order(Rect a, Rect b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left);
      expect(order(change, later), lessThan(0));
      expect(order(later, yes), lessThan(0));
      expect(360 - yes.right, lessThan(30));
      await t.tap(find.byKey(const Key('ask-first-change')));
      await t.tap(find.byKey(const Key('ask-first-later')));
      await t.tap(find.byKey(const Key('ask-first-yes')));
      expect(log, ['change', 'later', 'yes']);
    });

    testWidgets('unknown category or no hint: a normal Categorize row', (t) async {
      _size(t, 360);
      final a = WaitingActions(
        ruleHintFor: (w) => null,
        categoryNameOf: _name,
        onAskFirstYes: (w, h) async {},
        onAskFirstChange: (w, h) {},
        onAskFirstLater: (w, h) {},
      );
      await t.pumpWidget(_section([_item(1)], a));
      expect(find.byKey(const Key('ask-first-yes')), findsNothing);
      expect(find.text('$kHeadingToConfirm (1)'), findsNothing);
    });

    testWidgets('To confirm sits above To categorize', (t) async {
      _size(t, 360);
      final a = WaitingActions(
        ruleHintFor: (w) => w.id == heldIdFor(1) ? _hint : null,
        categoryNameOf: _name,
        onAskFirstYes: (w, h) async {},
        onAskFirstChange: (w, h) {},
        onAskFirstLater: (w, h) {},
      );
      await t.pumpWidget(_section([_item(1), _item(2)], a));
      final confirm = t.getTopLeft(find.text('$kHeadingToConfirm (1)')).dy;
      final cat = t.getTopLeft(find.textContaining('To categorize')).dy;
      expect(confirm, lessThan(cat));
    });
  });

  group('sizes', () {
    for (final (w, scale) in [(360.0, 1.0), (360.0, 2.0), (500.0, 1.0), (500.0, 2.0), (320.0, 2.0)]) {
      testWidgets('no overflow and at most 3 buttons per card: width $w, text x$scale', (t) async {
        _size(t, w);
        final c = SuggestionsController(engine: engine, store: store);
        addTearDown(c.dispose);
        await t.pumpWidget(
          _section(
            [_item(1)],
            actions(
              s: c,
              air: scale == 1.0 ? _air([AutoRecorded(rowId: 1, amountCents: 5000, at: kFakeNow)]) : null,
            ),
            scale: scale,
          ),
        );
        await t.pump();
        expect(t.takeException(), isNull);
        final ask = find.byKey(const Key('ask-first-actions'));
        expect(_buttons(ask), lessThanOrEqualTo(3));
        final card = find.byKey(const Key('suggestion-SM-0712'));
        expect(_buttons(card), lessThanOrEqualTo(3));
        expect(t.getRect(card).right, lessThanOrEqualTo(w));
        expect(t.getRect(ask).right, lessThanOrEqualTo(w));
      });
    }
  });
}
