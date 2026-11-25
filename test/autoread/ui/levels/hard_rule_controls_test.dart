// Slice U4 (0.2.2 item 2): the page controls of layout A. Pause card, paused banner, Settings row (one
// switch, three places, kept in sync), the red Reset footer with its counts-only confirm. Invented data.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_pause_card.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_paused_banner.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_reset_footer.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/settings/suggest_settings_section.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/hard_rule_fakes.dart';

Future<void> _pump(WidgetTester t, Widget child, {double scale = 1, String mode = 'light', double width = 390}) async {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(14), child: child)),
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

String? _toastText(WidgetTester t) {
  if (!PillToast.isShowing) return null;
  for (final s in [kHardPausedToast, kSuggestSaveFailed, kLevelSheetSaveFailed]) {
    if (find.text(s).evaluate().isNotEmpty) return s;
  }
  for (var n = 0; n < 20; n++) {
    for (final s in [hardResumedToast(n), hardResetToast(n)]) {
      if (find.text(s).evaluate().isNotEmpty) return s;
    }
  }
  return '?';
}

/// Three on Auto-record, one Ask first with a ceiling-free rule, one Ask first restored (pending), two Suggested.
Future<FakeRuleStore> _store() => hardTestStore([
      hardTestRule('0722000555', name: 'Tim Otieno', level: RuleLevel.autoRecord, categoryId: 1, ceilingCents: 150000),
      hardTestRule('0711000204', name: 'Amina Wanjiku', type: ReceiverType.pochi, level: RuleLevel.autoRecord, categoryId: 2),
      hardTestRule('5512', name: 'Mama Mboga', type: ReceiverType.buyGoods, level: RuleLevel.autoRecord, categoryId: 1),
      hardTestRule('888880', name: 'KPLC', type: ReceiverType.payBill, level: RuleLevel.askFirst, categoryId: 3),
      hardTestRule('0700000111', name: 'Juma', level: RuleLevel.askFirst, categoryId: 1, ceilingCents: 90000, autoPending: true),
      hardTestRule('0700000222', name: 'Wanjiru', categoryId: 1),
      hardTestRule('0700000333', name: 'Otieno B', categoryId: 2),
    ]);

/// A port whose reads wait until the test answers them, in any order (ordering guard test).
class _SlowPort extends ChangeNotifier implements HardRulePausePort {
  final List<Completer<bool>> reads = [];
  bool answerAtOnce = true;
  bool value = false;

  @override
  Future<bool> isPaused() {
    if (answerAtOnce) return Future.value(value);
    final c = Completer<bool>();
    reads.add(c);
    return c.future;
  }

  @override
  Future<bool> setPaused(bool p) async => true;

  void fire() => notifyListeners();

  @override
  Listenable get changes => this;
}

const _names = ['Tim Otieno', 'Amina Wanjiku', 'Mama Mboga', 'KPLC', 'Juma', 'Wanjiru', 'Otieno B'];

void main() {
  setUp(() {
    debugAutoRecordUiOverride = true;
    PillToast.dismissNow();
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugAutoRecordUiOverride = null);

  group('dormant (autoRecordUi false)', () {
    testWidgets('card, banner, footer and the Settings row draw nothing', (t) async {
      debugAutoRecordUiOverride = false;
      final pause = FakeHardRulePausePort(paused: true);
      final bulk = RuleBulkOps(await _store());
      await _pump(
          t,
          Column(children: [
            HardRulePauseCard(port: pause, bulk: bulk),
            HardRulePausedBanner(port: pause, bulk: bulk),
            HardRuleResetFooter(bulk: bulk),
            SuggestSettingsSection(port: FakeSuggestSettings(), pause: pause, bulk: bulk),
          ]));
      expect(find.byKey(const Key('hardPauseCard')), findsNothing);
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
      expect(find.byKey(const Key('hardResetButton')), findsNothing);
      expect(find.byKey(const Key('hardPauseSettingsRow')), findsNothing);
      expect(find.byKey(const Key('suggestSwitch')), findsOneWidget); // today's rows unchanged
      expect(find.text(kHardPauseTitle), findsNothing);
    });
  });

  group('pause card', () {
    testWidgets('off: title, sub and an off switch; tap pauses, toast, the store has it', (t) async {
      final pause = FakeHardRulePausePort();
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      expect(find.text(kHardPauseTitle), findsOneWidget);
      expect(find.text(kHardPauseSub), findsOneWidget);
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isFalse);
      await t.tap(find.byKey(const Key('hardPauseCard')));
      await t.pumpAndSettle();
      expect(pause.paused, isTrue);
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isTrue);
      expect(_toastText(t), kHardPausedToast);
      await _clearToast(t);
    });

    testWidgets('on: tap resumes, toast counts the people on Auto-record (3)', (t) async {
      final pause = FakeHardRulePausePort(paused: true);
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isTrue);
      await t.tap(find.byKey(const Key('hardPauseSwitch')));
      await t.pumpAndSettle();
      expect(pause.paused, isFalse);
      expect(_toastText(t), hardResumedToast(3));
      await _clearToast(t);
    });

    testWidgets('a failed write snaps back (stays paused) and shows the save-failed toast', (t) async {
      final pause = FakeHardRulePausePort(paused: true)..failWrites = true;
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      await t.tap(find.byKey(const Key('hardPauseCard')));
      await t.pumpAndSettle();
      expect(pause.setCalls, 1);
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isTrue);
      expect(_toastText(t), kSuggestSaveFailed);
      await _clearToast(t);
    });

    testWidgets('a failed write while not paused snaps back to off', (t) async {
      final pause = FakeHardRulePausePort()..failWrites = true;
      await _pump(t, HardRulePauseCard(port: pause, bulk: RuleBulkOps(await _store())));
      await t.tap(find.byKey(const Key('hardPauseCard')));
      await t.pumpAndSettle();
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isFalse);
      expect(_toastText(t), kSuggestSaveFailed);
      await _clearToast(t);
    });

    testWidgets('two quick changes, the first read answers last: the newer read wins', (t) async {
      final port = _SlowPort();
      await _pump(t, HardRulePauseCard(port: port));
      bool sw() => t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value;
      expect(sw(), isFalse);
      port.answerAtOnce = false;
      port.fire(); // read 1 (older)
      port.fire(); // read 2 (newer)
      expect(port.reads.length, 2);
      port.reads[1].complete(true); // the newer read: paused
      await t.pump();
      await t.pump(); // the read's setState lands after the first frame
      expect(sw(), isTrue);
      port.reads[0].complete(false); // the older read arrives late: must be dropped
      await t.pump();
      await t.pump();
      expect(sw(), isTrue);
    });

    testWidgets('an unreadable switch reads as paused (fail closed)', (t) async {
      final pause = FakeHardRulePausePort()..failReads = true;
      await _pump(t, HardRulePauseCard(port: pause));
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isTrue);
    });

    testWidgets('a screen reader hears one switch with its name, state and the line', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(paused: true)));
      final s = find.bySemanticsLabel(kHardPauseTitle);
      expect(s, findsOneWidget);
      expect(t.getSemantics(s), containsSemantics(label: kHardPauseTitle, hint: kHardPauseSub, hasToggledState: true, isToggled: true, hasTapAction: true));
      h.dispose();
    });

    testWidgets('pause survives a rebuild: a NEW real port over the same prefs reads paused', (t) async {
      final first = PrefsHardRulePausePort();
      await _pump(t, HardRulePauseCard(key: const ValueKey(1), port: first));
      await t.tap(find.byKey(const Key('hardPauseCard')));
      await t.pumpAndSettle();
      expect((await SharedPreferences.getInstance()).getBool(kHardPausedPrefsKey), isTrue);
      await _clearToast(t);
      // a fresh tree and a fresh port, as after an app restart
      await t.pumpWidget(const SizedBox());
      await _pump(t, HardRulePauseCard(key: const ValueKey(2), port: PrefsHardRulePausePort()));
      expect(t.widget<Switch>(find.byKey(const Key('hardPauseSwitch'))).value, isTrue);
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('text at 200% in $mode: no overflow, switch and card 44 px tall at least', (t) async {
        await _pump(t, HardRulePauseCard(port: FakeHardRulePausePort(paused: true)), scale: 2, mode: mode);
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(const Key('hardPauseCard'))).height, greaterThanOrEqualTo(44));
        expect(t.getSize(find.byKey(const Key('hardPauseSwitch'))).height, greaterThanOrEqualTo(44));
      });
    }
  });

  group('paused banner', () {
    testWidgets('not paused: nothing', (t) async {
      await _pump(t, HardRulePausedBanner(port: FakeHardRulePausePort(), bulk: RuleBulkOps(await _store())));
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
    });

    testWidgets('paused: the count line and Resume; Resume un-pauses, the banner goes, toast counts', (t) async {
      final pause = FakeHardRulePausePort(paused: true);
      await _pump(t, HardRulePausedBanner(port: pause, bulk: RuleBulkOps(await _store())));
      expect(find.text(hardPausedBanner(3)), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('hardResume'))).height, greaterThanOrEqualTo(44));
      await t.tap(find.byKey(const Key('hardResume')));
      await t.pumpAndSettle();
      expect(pause.paused, isFalse);
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);
      expect(_toastText(t), hardResumedToast(3));
      await _clearToast(t);
    });

    testWidgets('Resume that fails keeps the banner (still paused)', (t) async {
      final pause = FakeHardRulePausePort(paused: true)..failWrites = true;
      await _pump(t, HardRulePausedBanner(port: pause, bulk: RuleBulkOps(await _store())));
      await t.tap(find.byKey(const Key('hardResume')));
      await t.pumpAndSettle();
      expect(find.text(hardPausedBanner(3)), findsOneWidget);
      expect(_toastText(t), kSuggestSaveFailed);
      await _clearToast(t);
    });

    testWidgets('the banner is a live region', (t) async {
      final h = t.ensureSemantics();
      await _pump(t, HardRulePausedBanner(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(await _store())));
      final w = t.widget<Semantics>(find.byKey(const Key('hardPausedBanner')));
      expect(w.properties.liveRegion, isTrue);
      h.dispose();
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('200% text in $mode, narrow phone, RTL: no overflow', (t) async {
        t.view.physicalSize = const Size(320, 900);
        await _pump(
            t,
            Directionality(
              textDirection: TextDirection.rtl,
              child: HardRulePausedBanner(port: FakeHardRulePausePort(paused: true), bulk: RuleBulkOps(await _store())),
            ),
            scale: 2,
            mode: mode,
            width: 320);
        expect(t.takeException(), isNull);
        expect(find.text(kHardResume), findsOneWidget);
      });
    }
  });

  group('one switch in three places', () {
    testWidgets('card, banner and Settings row follow each other', (t) async {
      final pause = FakeHardRulePausePort();
      final bulk = RuleBulkOps(await _store());
      await _pump(
          t,
          Column(children: [
            HardRulePausedBanner(port: pause, bulk: bulk),
            HardRulePauseCard(port: pause, bulk: bulk),
            SuggestSettingsSection(port: FakeSuggestSettings(), pause: pause, bulk: bulk),
          ]));
      bool sw(String k) => t.widget<Switch>(find.byKey(Key(k))).value;
      expect(sw('hardPauseSwitch'), isFalse);
      expect(sw('hardPauseSettingsSwitch'), isFalse);
      expect(find.byKey(const Key('hardPausedBanner')), findsNothing);

      // pause from Settings
      await t.tap(find.byKey(const Key('hardPauseSettingsRow')));
      await t.pumpAndSettle();
      expect(sw('hardPauseSwitch'), isTrue);
      expect(sw('hardPauseSettingsSwitch'), isTrue);
      expect(find.text(hardPausedBanner(3)), findsOneWidget);
      await _clearToast(t);

      // resume from the banner
      await t.tap(find.byKey(const Key('hardResume')));
      await t.pumpAndSettle();
      expect(sw('hardPauseSwitch'), isFalse);
      expect(sw('hardPauseSettingsSwitch'), isFalse);
      await _clearToast(t);
    });

    testWidgets('Settings row: words, shown with Suggest off too, 200% text no overflow', (t) async {
      await _pump(t, SuggestSettingsSection(port: FakeSuggestSettings(on: false), pause: FakeHardRulePausePort(paused: true)),
          scale: 2, mode: 'dark');
      expect(t.takeException(), isNull);
      expect(find.text(kHardPauseSettingsTitle), findsOneWidget);
      expect(find.text(kHardPauseSettingsSub), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('hardPauseSettingsRow'))).height, greaterThanOrEqualTo(44));
    });

    testWidgets('Settings: no pause port = no row (today)', (t) async {
      await _pump(t, SuggestSettingsSection(port: FakeSuggestSettings()));
      expect(find.byKey(const Key('hardPauseSettingsRow')), findsNothing);
      expect(find.byKey(const Key('suggestAfterRow')), findsOneWidget);
    });
  });

  group('reset footer', () {
    testWidgets('red button, 44 px; the dialog counts only and names nobody', (t) async {
      final store = await _store();
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store)));
      expect(find.text(kHardResetButton), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('hardResetButton'))).height, greaterThanOrEqualTo(44));
      await t.tap(find.byKey(const Key('hardResetButton')));
      await t.pumpAndSettle();
      expect(find.text(hardResetTitle(5)), findsOneWidget); // 3 Auto-record + KPLC + Juma (pending)
      expect(find.text(kHardResetBody), findsOneWidget);
      final dialog = find.byType(AlertDialog);
      for (final n in _names) {
        expect(find.descendant(of: dialog, matching: find.textContaining(n)), findsNothing, reason: n);
      }
      await t.tap(find.byKey(const Key('hardResetCancel')));
      await t.pumpAndSettle();
    });

    testWidgets('Cancel changes nothing', (t) async {
      final store = await _store();
      final before = await store.all();
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store)));
      await t.tap(find.byKey(const Key('hardResetButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardResetCancel')));
      await t.pumpAndSettle();
      expect(await store.all(), before);
      expect(PillToast.isShowing, isFalse);
    });

    testWidgets('Reset keeps every rule: level Suggested, ceiling and mark cleared; toast', (t) async {
      final store = await _store();
      final done = <int>[];
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store, now: () => kHardTestNow), onDone: done.add));
      await t.tap(find.byKey(const Key('hardResetButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardResetOk')));
      await t.pumpAndSettle();
      final all = await store.all();
      expect(all.length, 7);
      for (final r in all) {
        expect(r.level, RuleLevel.suggested, reason: r.name);
        expect(r.ceilingCents, isNull, reason: r.name);
        expect(r.autoPending, isFalse, reason: r.name);
      }
      expect(done, [5]);
      expect(_toastText(t), hardResetToast(5));
      await _clearToast(t);
    });

    for (final pausedBefore in [true, false]) {
      testWidgets('real stores, one prefs: Reset leaves the pause key as it was (paused: $pausedBefore)', (t) async {
        final pausePort = PrefsHardRulePausePort();
        final rules = PrefsRuleStore();
        final prefs = await SharedPreferences.getInstance();
        expect(await pausePort.setPaused(pausedBefore), isTrue);
        for (final r in await (await _store()).all()) {
          expect(await rules.saveRule(r), isTrue, reason: r.name);
        }
        final keyBefore = prefs.get(kHardPausedPrefsKey);
        expect(keyBefore, pausedBefore ? isTrue : isNull);
        final done = <int>[];
        await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(rules, now: () => kHardTestNow), onDone: done.add));
        await t.tap(find.byKey(const Key('hardResetButton')));
        await t.pumpAndSettle();
        expect(find.text(hardResetTitle(5)), findsOneWidget);
        await t.tap(find.byKey(const Key('hardResetOk')));
        await t.pumpAndSettle();
        expect(done, [5]);
        await prefs.reload();
        expect(prefs.get(kHardPausedPrefsKey), keyBefore);
        expect(await pausePort.isPaused(), pausedBefore);
        final all = await rules.all();
        expect(all.length, 7);
        for (final r in all) {
          expect(r.level, RuleLevel.suggested, reason: r.name);
          expect(r.ceilingCents, isNull, reason: r.name);
          expect(r.autoPending, isFalse, reason: r.name);
        }
        await _clearToast(t);
      });
    }

    testWidgets('nobody above Suggested: no dialog, the 0 count line', (t) async {
      final store = await hardTestStore([hardTestRule('0700000222', name: 'Wanjiru')]);
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store)));
      await t.tap(find.byKey(const Key('hardResetButton')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(_toastText(t), hardResetToast(0));
      await _clearToast(t);
    });

    testWidgets('a store that refuses every write: save-failed toast, no onDone', (t) async {
      final store = await _store();
      store.detailsOn = false;
      final done = <int>[];
      await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(store), onDone: done.add));
      await t.tap(find.byKey(const Key('hardResetButton')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('hardResetOk')));
      await t.pumpAndSettle();
      expect(done, isEmpty);
      expect(_toastText(t), kLevelSheetSaveFailed);
      await _clearToast(t);
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('200% text in $mode: button and dialog do not overflow', (t) async {
        await _pump(t, HardRuleResetFooter(bulk: RuleBulkOps(await _store())), scale: 2, mode: mode, width: 320);
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const Key('hardResetButton')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byKey(const Key('hardResetOk'))).height, greaterThanOrEqualTo(44));
        expect(t.getSize(find.byKey(const Key('hardResetCancel'))).height, greaterThanOrEqualTo(44));
      });
    }
  });

  test('FakeRuleStore sanity for these tests: 7 rules, 3 on Auto-record', () async {
    final m = await RuleBulkOps(await _store()).countByLevel();
    expect(m[RuleLevel.autoRecord], 3);
    expect(await RuleBulkOps(FakeRuleStore()).resetCount(), 0);
  });
}
