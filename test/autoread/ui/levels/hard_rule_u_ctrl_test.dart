// Item 2 redesign, slice U-CTRL: the "Pause all Auto-record" switch row (hidden at 0, amber only when on,
// not colour-only, snaps back), the To do banner (hidden at 0, peopleCount), and the bottom bar (small red
// Reset link at the start, Set up at the end, SafeArea, wraps at 200%, Reset keeps rules and chosen
// Suggest lists). Light and dark, LTR and RTL. Invented data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_pause_card.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_paused_banner.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_reset_footer.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';

const _bar = Key('hardBottomBar');
const _reset = Key('hardResetButton');
const _setUp = Key('hardSetUpButton');
const _row = Key('hardPauseCard');
const _sw = Key('hardPauseSwitch');

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  double scale = 1,
  String mode = 'light',
  double width = 390,
  TextDirection dir = TextDirection.ltr,
  double bottomInset = 0,
  bool scroll = true,
}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Directionality(
            textDirection: dir,
            child: Scaffold(
              body: scroll
                  ? SingleChildScrollView(padding: const EdgeInsets.all(14), child: child)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Spacer(), child]),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Future<void> _clearToast(WidgetTester t) async {
  PillToast.dismissNow();
  await t.pump(const Duration(seconds: 10));
}

AppPalette _palette(WidgetTester t, Finder f) => AppPalette.of(t.element(f));

/// Two Auto-record, one Ask first, one Suggested with a chosen list and a stray limit (needs a reset),
/// one plain Suggested with a chosen list (untouched by a reset).
Future<FakeRuleStore> _store() => hardTestStore([
      hardTestRule('0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 150000),
      hardTestRule('5512', name: 'Mama Mboga', type: ReceiverType.buyGoods, level: RuleLevel.autoRecord, categoryId: 1),
      hardTestRule('888880', name: 'KPLC', type: ReceiverType.payBill, level: RuleLevel.askFirst, categoryId: 3),
      hardTestRule('0700000222', name: 'Wanjiru', ceilingCents: 50000).copyWith(chosenCategoryIds: [1, 2]),
      hardTestRule('0700000333', name: 'Otieno B').copyWith(chosenCategoryIds: [3]),
    ]);

Future<FakeRuleStore> _noAuto() => hardTestStore([
      hardTestRule('888880', name: 'KPLC', type: ReceiverType.payBill, level: RuleLevel.askFirst, categoryId: 3),
      hardTestRule('0700000222', name: 'Wanjiru'),
    ]);

/// A store whose reads throw (count failures).
class _BrokenStore extends FakeRuleStore {
  @override
  Future<List<ReceiverRule>> all() async => throw StateError('read');
}

void main() {
  setUp(() {
    debugAutoRecordUiOverride = true;
    PillToast.dismissNow();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugAutoRecordUiOverride = null);

  group('pause switch row: hidden at 0 (B-6)', () {
    for (final paused in [false, true]) {
      testWidgets('nobody on Auto-record: no row (paused: $paused)', (t) async {
        await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(paused: paused), bulk: RuleBulkOps(await _noAuto())));
        expect(find.byKey(_row), findsNothing);
        expect(find.text(kHardPauseTitle), findsNothing);
      });
    }

    testWidgets('empty store: no row', (t) async {
      await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(), bulk: RuleBulkOps(FakeRuleStore())));
      expect(find.byKey(_row), findsNothing);
    });

    testWidgets('the row follows the store: someone joins Auto-record, then leaves', (t) async {
      final store = await _noAuto();
      await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(), bulk: RuleBulkOps(store)));
      expect(find.byKey(_row), findsNothing);
      await store.setLevel(ReceiverType.sendMoney, '0700000222',
          name: 'Wanjiru', level: RuleLevel.autoRecord, categoryId: 1, at: kHardTestNow);
      await t.pumpAndSettle();
      expect(find.byKey(_row), findsOneWidget);
      await store.setLevel(ReceiverType.sendMoney, '0700000222',
          name: 'Wanjiru', level: RuleLevel.suggested, at: kHardTestNow);
      await t.pumpAndSettle();
      expect(find.byKey(_row), findsNothing);
    });

    testWidgets('details OFF (the store hides every rule): no row', (t) async {
      final store = await _store();
      store.detailsOn = false;
      await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(store)));
      expect(find.byKey(_row), findsNothing);
    });

    testWidgets('a count that cannot be read: the row is shown (a missing switch is worse)', (t) async {
      await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(), bulk: RuleBulkOps(_BrokenStore())));
      expect(find.byKey(_row), findsOneWidget);
    });
  });

  group('pause switch row: look and state', () {
    for (final mode in ['light', 'dark']) {
      testWidgets('$mode: amber only when on; off is neutral; on carries a pause mark (not colour only)', (t) async {
        final pause = FakeHardRulePausePort();
        await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())), mode: mode);
        final p = _palette(t, find.byKey(_sw));
        var s = t.widget<Switch>(find.byKey(_sw));
        expect(s.value, isFalse);
        expect(s.inactiveTrackColor, p.track);
        expect(s.inactiveTrackColor, isNot(p.sun));
        expect(s.trackOutlineColor!.resolve(<WidgetState>{}), p.mutedInk);
        expect(s.thumbIcon!.resolve(<WidgetState>{}), isNull);

        await t.tap(find.byKey(_row));
        await t.pumpAndSettle();
        s = t.widget<Switch>(find.byKey(_sw));
        expect(s.value, isTrue);
        expect(s.activeTrackColor, p.sun);
        expect(s.trackOutlineColor!.resolve({WidgetState.selected}), p.sun);
        // the visible non-colour cue: a pause mark on the thumb (painted by the Switch, not a child widget)
        expect(s.thumbIcon!.resolve({WidgetState.selected})!.icon, Icons.pause);
        // the row's frame stays neutral (mock: "only the switch turns amber")
        final m = t.widget<Material>(find.ancestor(of: find.byKey(_row), matching: find.byType(Material)).first);
        expect((m.shape! as RoundedRectangleBorder).side.color, p.line);
        await _clearToast(t);
      });
    }

    testWidgets('a screen reader hears the name, the line and the paused (toggled) state', (t) async {
      final h = t.ensureSemantics();
      final pause = FakeHardRulePausePort();
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      final s = find.bySemanticsLabel(kHardPauseTitle);
      expect(t.getSemantics(s),
          containsSemantics(label: kHardPauseTitle, hint: kHardPauseSub, hasToggledState: true, isToggled: false, hasTapAction: true));
      await t.tap(find.byKey(_row));
      await t.pumpAndSettle();
      expect(t.getSemantics(s), containsSemantics(label: kHardPauseTitle, hasToggledState: true, isToggled: true));
      // the pill says it in words too
      expect(find.text(kHardPausedToast), findsOneWidget);
      await _clearToast(t);
      h.dispose();
    });

    testWidgets('snap-back: a failed write leaves the switch off and says so', (t) async {
      final pause = FakeHardRulePausePort()..failWrites = true;
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      await t.tap(find.byKey(_sw));
      await t.pumpAndSettle();
      expect(pause.setCalls, 1);
      expect(t.widget<Switch>(find.byKey(_sw)).value, isFalse);
      expect(find.text(kSuggestSaveFailed), findsOneWidget);
      await _clearToast(t);
    });

    testWidgets('resume toast counts through peopleCount (2 people)', (t) async {
      final pause = FakeHardRulePausePort(paused: true);
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      await t.tap(find.byKey(_sw));
      await t.pumpAndSettle();
      expect(find.text(hardResumedToast(2)), findsOneWidget);
      await _clearToast(t);
    });

    for (final mode in ['light', 'dark']) {
      for (final dir in TextDirection.values) {
        testWidgets('200% $mode ${dir.name}: no overflow, 44 px row and switch, switch at the end', (t) async {
          await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(await _store())),
              scale: 2, mode: mode, dir: dir, width: 320);
          expect(t.takeException(), isNull);
          expect(t.getSize(find.byKey(_row)).height, greaterThanOrEqualTo(44));
          expect(t.getSize(find.byKey(_sw)).height, greaterThanOrEqualTo(44));
          final row = t.getRect(find.byKey(_row));
          final sw = t.getRect(find.byKey(_sw));
          final title = t.getRect(find.text(kHardPauseTitle));
          if (dir == TextDirection.ltr) {
            expect(sw.left, greaterThan(title.left));
            expect(row.right - sw.right, lessThan(20));
          } else {
            expect(sw.right, lessThan(title.right));
            expect(sw.left - row.left, lessThan(20));
          }
        });
      }
    }
  });

  group('To do banner (hard_rule_paused_banner)', () {
    testWidgets('paused but nobody on Auto-record: nothing (never "0 people")', (t) async {
      await _pump(t, HardRulePausedBanner(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(await _noAuto())));
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
      expect(find.textContaining('0 people'), findsNothing);
    });

    testWidgets('no bulk: nothing', (t) async {
      await _pump(t, HardRulePausedBanner(port: FakeHardRulePausePort(paused: true)));
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
    });

    testWidgets('1 person: the singular line; a second joins while paused: the count follows', (t) async {
      final store = await hardTestStore([
        hardTestRule('0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1),
        hardTestRule('0700000222', name: 'Wanjiru'),
      ]);
      await _pump(t, HardRulePausedBanner(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(store)));
      expect(find.text(hardPausedBanner(1)), findsOneWidget);
      expect(hardPausedBanner(1), contains(peopleCount(1)));
      await store.setLevel(ReceiverType.sendMoney, '0700000222',
          name: 'Wanjiru', level: RuleLevel.autoRecord, categoryId: 1, at: kHardTestNow);
      await t.pumpAndSettle();
      expect(find.text(hardPausedBanner(2)), findsOneWidget);
      // and the last two leave: the banner goes
      for (final k in ['0700000222', '0722000555']) {
        await store.setLevel(ReceiverType.sendMoney, k, name: k, level: RuleLevel.suggested, at: kHardTestNow);
      }
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
    });
  });

  group('bottom bar', () {
    testWidgets('dormant: nothing, even with Set up', (t) async {
      debugAutoRecordUiOverride = false;
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () {}));
      expect(find.byKey(_bar), findsNothing);
      expect(find.byKey(_setUp), findsNothing);
    });

    testWidgets('empty page, no Set up: nothing drawn at all', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(FakeRuleStore())));
      expect(find.byKey(_bar), findsNothing);
    });

    testWidgets('empty page with Set up: Set up only, no Reset', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(FakeRuleStore()), onSetUp: () {}));
      expect(find.byKey(_bar), findsOneWidget);
      expect(find.byKey(_reset), findsNothing);
      expect(find.byKey(_setUp), findsOneWidget);
    });

    testWidgets('onSetUp null: no Set up button; the link stays', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store())));
      expect(find.byKey(_setUp), findsNothing);
      expect(find.byKey(_reset), findsOneWidget);
    });

    testWidgets('nobody on Auto-record but someone on Ask first: the link shows (mock page-noauto)', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _noAuto()), onSetUp: () {}));
      expect(find.byKey(_reset), findsOneWidget);
    });

    testWidgets('the link follows the store: appears when someone is raised', (t) async {
      final store = await hardTestStore([hardTestRule('0700000222', name: 'Wanjiru')]);
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store), onSetUp: () {}));
      expect(find.byKey(_reset), findsNothing);
      await store.setLevel(ReceiverType.sendMoney, '0700000222',
          name: 'Wanjiru', level: RuleLevel.askFirst, categoryId: 1, at: kHardTestNow);
      await t.pumpAndSettle();
      expect(find.byKey(_reset), findsOneWidget);
    });

    testWidgets('a count that cannot be read: the link shows; the tap says the save failed', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(_BrokenStore())));
      expect(find.byKey(_reset), findsOneWidget);
      await t.tap(find.byKey(_reset));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(kLevelSheetSaveFailed), findsOneWidget);
      await _clearToast(t);
    });

    testWidgets('Set up: tap calls onSetUp; spoken "Set up a recipient" as a button', (t) async {
      final h = t.ensureSemantics();
      var n = 0;
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () => n++));
      expect(find.text(kHardSetUpButton), findsOneWidget);
      await t.tap(find.byKey(_setUp));
      await t.pumpAndSettle();
      expect(n, 1);
      expect(t.getSemantics(find.bySemanticsLabel(kHardSetUpTitle)),
          containsSemantics(label: kHardSetUpTitle, isButton: true, hasTapAction: true));
      h.dispose();
    });

    testWidgets('the link is red, small and underlined (text says what it does, not the colour)', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () {}));
      final p = _palette(t, find.byKey(_reset));
      final b = t.widget<TextButton>(find.byKey(_reset));
      expect(b.style!.foregroundColor!.resolve(<WidgetState>{}), p.error);
      expect(b.style!.textStyle!.resolve(<WidgetState>{})!.decoration, TextDecoration.underline);
      expect(find.text(kHardResetButton), findsOneWidget);
    });

    for (final mode in ['light', 'dark']) {
      for (final dir in TextDirection.values) {
        // The test font draws every letter as a full square, so the link is ~360 px here; 600 px leaves
        // room for one line (a real phone font fits at 390 px: device-only check).
        testWidgets('1.0 $mode ${dir.name}: one line, Reset at the start, Set up at the end, 44 px', (t) async {
          await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () {}),
              mode: mode, dir: dir, scroll: false, width: 600);
          expect(t.takeException(), isNull);
          final bar = t.getRect(find.byKey(_bar));
          final r = t.getRect(find.byKey(_reset));
          final s = t.getRect(find.byKey(_setUp));
          expect(r.height, greaterThanOrEqualTo(44));
          expect(s.height, greaterThanOrEqualTo(44));
          expect(s.top, lessThan(r.bottom)); // same line
          expect(r.top, lessThan(s.bottom));
          if (dir == TextDirection.ltr) {
            expect(r.right, lessThan(s.left));
            expect(r.left - bar.left, closeTo(14, 1));
            expect(bar.right - s.right, closeTo(14, 1));
          } else {
            expect(s.right, lessThan(r.left));
            expect(bar.right - r.right, closeTo(14, 1));
            expect(s.left - bar.left, closeTo(14, 1));
          }
          // stuck to the bottom of the screen
          expect(bar.bottom, closeTo(900, 0.5));
        });

        testWidgets('200% $mode ${dir.name}: wraps to two lines, Reset first at the start, Set up below at the end',
            (t) async {
          await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () {}),
              scale: 2, mode: mode, dir: dir, width: 320, scroll: false);
          expect(t.takeException(), isNull);
          final bar = t.getRect(find.byKey(_bar));
          final r = t.getRect(find.byKey(_reset));
          final s = t.getRect(find.byKey(_setUp));
          expect(s.top, greaterThanOrEqualTo(r.bottom)); // two lines
          expect(r.height, greaterThanOrEqualTo(44));
          expect(s.height, greaterThanOrEqualTo(44));
          if (dir == TextDirection.ltr) {
            expect(r.left - bar.left, closeTo(14, 1));
            expect(bar.right - s.right, closeTo(14, 1));
          } else {
            expect(bar.right - r.right, closeTo(14, 1));
            expect(s.left - bar.left, closeTo(14, 1));
          }
          expect(r.right, lessThanOrEqualTo(bar.right));
          expect(r.left, greaterThanOrEqualTo(bar.left));
          // the dialog at 200% too
          await t.tap(find.byKey(_reset));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text(hardResetTitle(4)), findsOneWidget);
          await t.tap(find.byKey(const Key('hardResetCancel')));
          await t.pumpAndSettle();
        });
      }
    }

    testWidgets('SafeArea: the buttons sit above the system bar inset', (t) async {
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store()), onSetUp: () {}),
          bottomInset: 30, scroll: false);
      final bar = t.getRect(find.byKey(_bar));
      final s = t.getRect(find.byKey(_setUp));
      expect(bar.bottom, closeTo(900, 0.5));
      expect(s.bottom, lessThanOrEqualTo(900 - 30 - 14 + 0.5));
    });

    testWidgets('the layout alone: a zero-width side takes no room and keeps one line', (t) async {
      await _pump(
          t,
          const HardBottomBarLayout(children: [SizedBox.shrink(), SizedBox(key: Key('b'), width: 300, height: 48)]),
          width: 320);
      expect(t.getRect(find.byKey(const Key('b'))).height, 48);
      expect(t.getSize(find.byType(HardBottomBarLayout)).height, 48);
    });
  });

  group('Reset keeps rules and chosen Suggest lists (PM Q2)', () {
    testWidgets('fake store: 4 reset, every rule kept, chosen lists unchanged', (t) async {
      final store = await _store();
      final before = {for (final r in await store.all()) r.key: r.chosenCategoryIds};
      final done = <int>[];
      await _pump(t,
          HardRuleResetFooter(bulk: RuleBulkOps(store, now: () => kHardTestNow), onDone: done.add, onSetUp: () {}));
      await t.tap(find.byKey(_reset));
      await t.pumpAndSettle();
      expect(find.text(hardResetTitle(4)), findsOneWidget);
      await t.tap(find.byKey(const Key('hardResetOk')));
      await t.pumpAndSettle();
      expect(done, [4]);
      final all = await store.all();
      expect(all.length, 5);
      for (final r in all) {
        expect(r.level, RuleLevel.suggested, reason: r.name);
        expect(r.ceilingCents, isNull, reason: r.name);
        expect(r.chosenCategoryIds, before[r.key], reason: r.name);
      }
      expect(before['0700000222'], [1, 2]);
      expect(before['0700000333'], [3]);
      // nothing left to reset: the link goes
      expect(find.byKey(_reset), findsNothing);
      expect(find.byKey(_setUp), findsOneWidget);
      await _clearToast(t);
    });

    testWidgets('real prefs store: the chosen list survives a reset', (t) async {
      final rules = PrefsRuleStore();
      for (final r in await (await _store()).all()) {
        expect(await rules.saveRule(r), isTrue, reason: r.name);
      }
      expect((await rules.get(ReceiverType.sendMoney, '0700000222'))!.chosenCategoryIds, [1, 2]);
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(rules, now: () => kHardTestNow)));
      await t.tap(find.byKey(_reset));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardResetOk')));
      await t.pumpAndSettle();
      final w = (await rules.get(ReceiverType.sendMoney, '0700000222'))!;
      expect(w.level, RuleLevel.suggested);
      expect(w.ceilingCents, isNull);
      expect(w.chosenCategoryIds, [1, 2]);
      expect((await rules.get(ReceiverType.sendMoney, '0700000333'))!.chosenCategoryIds, [3]);
      expect((await rules.all()).length, 5);
      await _clearToast(t);
    });
  });
}
