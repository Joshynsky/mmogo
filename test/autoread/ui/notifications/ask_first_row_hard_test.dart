// Slice U4 (0.2.2 item 2): the To confirm card for Auto-record people. (1) B2 handoff: an item whose hint
// is Auto-record but was not recorded (an `auto` hint left waiting, or an Ask first hint made from
// Auto-record) shows the Ask first row. (2) The amber "Auto-record paused: asking first" tag, only while
// paused AND the hint was made from Auto-record, only while autoRecordUi. Invented data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_deps.dart';
import 'package:mmogo/autoread/ui/notifications/ask_first_row.dart';
import 'package:mmogo/autoread/ui/waiting_section.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../../support/hard_rule_fakes.dart';
import '../../../support/news_fakes.dart';
import '../../../support/waiting_fakes.dart';

String? _name(int id) => id == 5 ? 'Family & friends' : null;

WaitingItem _item(int n) {
  final at = kFakeNow.subtract(const Duration(minutes: 20));
  return WaitingItem(id: heldIdFor(n), kind: WaitingKind.waitingCategory, heldAt: at, parsed: sampleFields(0, at));
}

RuleHint _hint(RuleLevel level, {bool fa = false, List<int> sg = const [5]}) =>
    RuleHint(level: level, type: ReceiverType.sendMoney, key: '0722000555', suggested: sg, fromAutoRecord: fa);

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, String mode = 'light'}) async {
  t.view.physicalSize = const Size(390, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Widget _row(RuleHint? hint, {HardRulePausePort? pause}) => AskFirstRow(
      item: _item(1),
      now: kFakeNow,
      categoryName: 'Family & friends',
      onChange: () {},
      onLater: () {},
      onYes: () {},
      hint: hint,
      pause: pause,
    );

const _tag = Key('ask-first-paused-tag');

void main() {
  tearDown(() {
    debugAutoRecordUiOverride = null;
    LevelsDeps.instance = null;
  });

  group('askFirstCategory (B2 handoff)', () {
    final w = _item(1);
    String? cat(RuleHint? h) => askFirstCategory(w, h, kFakeNow, _name);

    test('Ask first: asks', () => expect(cat(_hint(RuleLevel.askFirst)), 'Family & friends'));
    test('Ask first made from Auto-record: asks', () => expect(cat(_hint(RuleLevel.askFirst, fa: true)), 'Family & friends'));
    test('an `auto` hint still waiting (not recorded): asks', () => expect(cat(_hint(RuleLevel.autoRecord)), 'Family & friends'));
    test('the same with the UI flag off (the item already exists; never a plain row)', () {
      debugAutoRecordUiOverride = false;
      expect(cat(_hint(RuleLevel.autoRecord)), 'Family & friends');
    });
    test('Suggested: no question', () => expect(cat(_hint(RuleLevel.suggested)), isNull));
    test('no hint / nothing offered / unknown category: no question', () {
      expect(cat(null), isNull);
      expect(cat(_hint(RuleLevel.autoRecord, sg: const [])), isNull);
      expect(cat(_hint(RuleLevel.autoRecord, sg: const [9])), isNull);
    });
    test('hintAsksFirst table', () {
      expect(hintAsksFirst(_hint(RuleLevel.suggested)), isFalse);
      expect(hintAsksFirst(_hint(RuleLevel.askFirst)), isTrue);
      expect(hintAsksFirst(_hint(RuleLevel.autoRecord)), isTrue);
      expect(hintAsksFirst(_hint(RuleLevel.askFirst, fa: true)), isTrue);
    });

    testWidgets('To do shows the Ask first row for an `auto` hint, Yes wired', (t) async {
      final log = <String>[];
      await _pump(
          t,
          WaitingSection(
            waiting: [_item(1)],
            now: kFakeNow,
            actions: WaitingActions(
              ruleHintFor: (_) => _hint(RuleLevel.autoRecord),
              categoryNameOf: _name,
              onAskFirstYes: (w, h) async => log.add('yes ${h.level.name}'),
              onAskFirstChange: (w, h) => log.add('change'),
              onAskFirstLater: (w, h) => log.add('later'),
            ),
          ));
      expect(find.byType(AskFirstRow), findsOneWidget);
      expect(find.text('Record as Family & friends?'), findsOneWidget);
      await t.tap(find.byKey(const Key('ask-first-yes')));
      await t.pump();
      expect(log, ['yes autoRecord']);
    });
  });

  group('paused tag', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('paused + made from Auto-record: the tag', (t) async {
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(_tag), findsOneWidget);
      expect(find.text(kHardPausedTag), findsOneWidget);
    });

    testWidgets('not paused: no tag', (t) async {
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort()));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('paused but a plain Ask first person: no tag', (t) async {
      await _pump(t, _row(_hint(RuleLevel.askFirst), pause: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('paused, an `auto` hint (not made from a refused Auto-record): no tag', (t) async {
      await _pump(t, _row(_hint(RuleLevel.autoRecord), pause: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('no hint passed (today\'s caller): no tag', (t) async {
      await _pump(t, _row(null, pause: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('flag off: no tag even when paused', (t) async {
      debugAutoRecordUiOverride = false;
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('follows the switch: appears on pause, goes on resume', (t) async {
      final pause = FakeHardRulePausePort();
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: pause));
      expect(find.byKey(_tag), findsNothing);
      await pause.setPaused(true);
      await t.pumpAndSettle();
      expect(find.byKey(_tag), findsOneWidget);
      await pause.setPaused(false);
      await t.pumpAndSettle();
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('no port given: uses the app\'s one (LevelsDeps.instance)', (t) async {
      LevelsDeps.instance = hardTestDeps(pause: FakeHardRulePausePort(paused: true));
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true)));
      expect(find.byKey(_tag), findsOneWidget);
    });

    testWidgets('no port anywhere: no tag', (t) async {
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true)));
      expect(find.byKey(_tag), findsNothing);
    });

    testWidgets('unreadable switch reads paused: the tag (fail closed)', (t) async {
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort()..failReads = true));
      expect(find.byKey(_tag), findsOneWidget);
    });

    testWidgets('the tag is read out (live region); the buttons stay three', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort(paused: true)));
      expect(find.bySemanticsLabel(kHardPausedTag), findsOneWidget);
      final w = t.widget<Semantics>(find.ancestor(of: find.byKey(_tag), matching: find.byType(Semantics)).first);
      expect(w.properties.liveRegion, isTrue);
      expect(find.descendant(of: find.byKey(const Key('ask-first-actions')), matching: find.byType(InkWell)).evaluate().length, 3);
      h.dispose();
    });

    for (final mode in ['light', 'dark']) {
      for (final dir in TextDirection.values) {
        testWidgets('200% text, $mode, ${dir.name}: no overflow', (t) async {
          await _pump(
              t,
              Directionality(
                  textDirection: dir, child: _row(_hint(RuleLevel.askFirst, fa: true), pause: FakeHardRulePausePort(paused: true))),
              scale: 2,
              mode: mode);
          expect(t.takeException(), isNull);
          expect(find.byKey(_tag), findsOneWidget);
        });
      }
    }
  });
}
