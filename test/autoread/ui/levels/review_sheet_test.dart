@Tags(['autoread'])
library;

// 0.2.2 item 2, slice U6: the restore review (mock rst-line, rst-review). Applying a choice (Confirm
// brings back the backup's category and ceiling, PM D4; Keep all and unpicked people go to Ask first;
// nobody reaches Auto-record without an explicit pick; a person no longer pending is left alone), on
// the fake store AND the real PrefsRuleStore; the sheet (defaults, mixed picks, Keep all, close, the
// toasts, disabled Auto-record without a category, 200% text, dark); the review line (count from the
// autoPending mark only, n = 0 / flag off / details off draw nothing, gone after Confirm).
// Invented names and numbers only.
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/review_line.dart';
import 'package:mmogo/autoread/ui/levels/review_sheet.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

final t0 = DateTime.utc(2026, 11, 25, 9);
final t1 = DateTime.utc(2026, 11, 25, 10);

ReceiverRule _r(ReceiverType type, String key, String name,
        {RuleLevel level = RuleLevel.askFirst, int? cat, int? ceil, bool ap = true}) =>
    ReceiverRule(
        type: type, key: key, name: name, level: level, categoryId: cat, ceilingCents: ceil, autoPending: ap, created: t0, changed: t0);

// As a restore leaves them: on Ask first with the mark, the backup's category and ceiling kept.
final tim = _r(ReceiverType.sendMoney, '0722000555', 'Tim Otieno', cat: 1, ceil: 200000);
final amina = _r(ReceiverType.pochi, 'Amina', 'Amina Wanjiku', cat: 1);
final mboga = _r(ReceiverType.buyGoods, '5512000', 'Mama Mboga', cat: 2, ceil: 50000);
// On Ask first by his own choice: never in the review.
final gary = _r(ReceiverType.sendMoney, '0711000204', 'Gary Kamau', cat: 3, ap: false);

Future<FakeRuleStore> _fake([List<ReceiverRule>? rules]) async {
  final s = FakeRuleStore();
  for (final r in rules ?? [tim, amina, mboga, gary]) {
    await s.saveRule(r);
  }
  return s;
}

Future<ReceiverRule> _get(RuleStore s, ReceiverRule r) async => (await s.get(r.type, r.key))!;

Future<List<ReceiverRule>> _pending(RuleStore s) => RuleBulkOps(s).pendingAutoPeople();

Future<void> _host(WidgetTester t, Widget child, {double scale = 1, String mode = 'light', double height = 800}) async {
  t.view.physicalSize = Size(390, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(AppPaletteScope(
    controller: AppPaletteController('ocean', mode),
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: w!),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ));
  await t.pumpAndSettle();
}

/// A button that runs the whole review for the store's pending people; [last] keeps the answer.
class _Opener extends StatelessWidget {
  const _Opener(this.store, this.out);
  final RuleStore store;
  final List<ReviewApplied?> out;
  @override
  Widget build(BuildContext context) => TextButton(
        key: const Key('open'),
        onPressed: () async =>
            out.add(await reviewRestoredPeople(context, store: store, people: await _pending(store), now: () => t1)),
        child: const Text('open'),
      );
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder _pick(ReceiverRule r, String which) =>
    find.descendant(of: find.byKey(Key('reviewRow${reviewId(r)}')), matching: find.byKey(Key(which)));

String? _toast() {
  final f = find.descendant(of: find.byType(Overlay).first, matching: find.textContaining(RegExp('back on Auto-record|Everyone stays on Ask first|Could not save')));
  return f.evaluate().isEmpty ? null : (f.evaluate().first.widget as Text).data;
}

Future<void> _clearToast(WidgetTester t) async {
  PillToast.dismissNow();
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugAutoRecordUiOverride = null);

  group('applyReview (fake store)', () {
    test('Confirm: the picked person back on Auto-record with the backup category and ceiling (D4); '
        'the others on Ask first with category and ceiling kept; every mark cleared; Gary untouched', () async {
      final s = await _fake();
      final a = await applyReview(s, await _pending(s), ReviewChoice.confirm({reviewId(tim)}), t1);
      expect([a.auto, a.askFirst, a.failed], [1, 2, 0]);
      final ti = await _get(s, tim), am = await _get(s, amina), mb = await _get(s, mboga), ga = await _get(s, gary);
      expect([ti.level, ti.categoryId, ti.ceilingCents, ti.autoPending], [RuleLevel.autoRecord, 1, 200000, false]);
      expect([am.level, am.categoryId, am.ceilingCents, am.autoPending], [RuleLevel.askFirst, 1, null, false]);
      expect([mb.level, mb.categoryId, mb.ceilingCents, mb.autoPending], [RuleLevel.askFirst, 2, 50000, false]);
      expect(ga, gary);
      expect(await _pending(s), isEmpty);
    });

    test('Keep all: everyone on Ask first, category and ceiling kept, nobody on Auto-record', () async {
      final s = await _fake();
      final a = await applyReview(s, await _pending(s), const ReviewChoice.keepAll(), t1);
      expect([a.auto, a.askFirst, a.failed], [0, 3, 0]);
      for (final r in await s.all()) {
        expect(r.level, isNot(RuleLevel.autoRecord));
        expect(r.autoPending, isFalse);
      }
      expect((await _get(s, mboga)).ceilingCents, 50000);
      expect((await _get(s, tim)).categoryId, 1);
    });

    test('Confirm with no picks: nobody reaches Auto-record', () async {
      final s = await _fake();
      final a = await applyReview(s, await _pending(s), const ReviewChoice.confirm({}), t1);
      expect(a.auto, 0);
      expect((await s.all()).where((r) => r.level == RuleLevel.autoRecord), isEmpty);
    });

    test('a person changed meanwhile (no longer pending, or forgotten) is left alone, even if picked', () async {
      final s = await _fake();
      final people = await _pending(s);
      await s.setLevel(tim.type, tim.key, name: tim.name, level: RuleLevel.suggested, at: t1); // own choice meanwhile
      await s.forget(amina.type, amina.key);
      final a = await applyReview(s, people, ReviewChoice.confirm({reviewId(tim), reviewId(amina)}), t1);
      expect([a.auto, a.askFirst, a.failed], [0, 1, 0]);
      expect((await _get(s, tim)).level, RuleLevel.suggested);
      expect(await s.get(amina.type, amina.key), isNull);
    });

    test('a picked person with no category, or a Paybill one, is never raised (Ask first instead)', () async {
      final noCat = _r(ReceiverType.sendMoney, '0700000111', 'No Cat');
      final kplc = _r(ReceiverType.payBill, '888000', 'KPLC Prepaid', cat: 3);
      final s = await _fake([noCat, kplc]);
      expect(reviewCanAuto(noCat), isFalse);
      expect(reviewCanAuto(kplc), isFalse);
      final a = await applyReview(s, await _pending(s), ReviewChoice.confirm({reviewId(noCat), reviewId(kplc)}), t1);
      expect([a.auto, a.askFirst], [0, 2]);
      expect((await s.all()).map((r) => r.level).toSet(), {RuleLevel.askFirst});
    });

    test('a refused write counts as failed and keeps the mark (the review stays)', () async {
      final s = await _fake();
      final people = await _pending(s);
      s.detailsOn = false;
      final a = await applyReview(s, people, ReviewChoice.confirm({reviewId(tim)}), t1);
      expect([a.auto, a.askFirst, a.failed], [0, 0, 3]);
      expect(await _pending(s), hasLength(3));
      expect(reviewToastText(a), kLevelSheetSaveFailed);
    });

    test('toast text: failures win, then the Auto-record count, else all on Ask first', () {
      expect(reviewToastText(const ReviewApplied(auto: 2, askFirst: 1, failed: 0)), hardReviewToast(2));
      expect(reviewToastText(const ReviewApplied(auto: 0, askFirst: 3, failed: 0)), kHardReviewKeptToast);
      expect(reviewToastText(const ReviewApplied(auto: 1, askFirst: 0, failed: 1)), kLevelSheetSaveFailed);
    });
  });

  group('applyReview (real PrefsRuleStore)', () {
    test('Confirm keeps category and ceiling and clears the mark; Keep keeps them on Ask first', () async {
      final s = PrefsRuleStore();
      for (final r in [tim, amina, mboga, gary]) {
        expect(await s.saveRule(r), isTrue);
      }
      expect((await _pending(s)).map(reviewId).toSet(), {reviewId(tim), reviewId(amina), reviewId(mboga)});
      final a = await applyReview(s, await _pending(s), ReviewChoice.confirm({reviewId(tim), reviewId(amina)}), t1);
      expect([a.auto, a.askFirst, a.failed], [2, 1, 0]);
      final ti = await _get(s, tim), am = await _get(s, amina), mb = await _get(s, mboga);
      expect([ti.level, ti.categoryId, ti.ceilingCents, ti.autoPending], [RuleLevel.autoRecord, 1, 200000, false]);
      expect([am.level, am.categoryId, am.ceilingCents, am.autoPending], [RuleLevel.autoRecord, 1, null, false]);
      expect([mb.level, mb.categoryId, mb.ceilingCents, mb.autoPending], [RuleLevel.askFirst, 2, 50000, false]);
      expect((await _get(s, gary)).level, RuleLevel.askFirst);
      expect(await _pending(s), isEmpty);
    });
  });

  group('review sheet', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('defaults: title, sub, every person on Ask first (checked), Auto-record not checked', (t) async {
      final h = t.ensureSemantics();
      final s = await _fake();
      await _host(t, _Opener(s, []));
      await _tap(t, find.byKey(const Key('open')));
      expect(find.text(kHardReviewTitle), findsOneWidget);
      expect(find.text(kHardReviewSub), findsOneWidget);
      expect(find.text('Gary Kamau'), findsNothing); // own-choice Ask first is not reviewed
      for (final r in [tim, amina, mboga]) {
        expect(find.text(r.name), findsOneWidget);
        final ask = t.getSemantics(_pick(r, 'reviewPickAsk')).getSemanticsData();
        final auto = t.getSemantics(_pick(r, 'reviewPickAuto')).getSemanticsData();
        expect(ask.flagsCollection.isChecked, CheckedState.isTrue);
        expect(auto.flagsCollection.isChecked, CheckedState.isFalse);
        expect(t.getSize(_pick(r, 'reviewPickAsk')).height, greaterThanOrEqualTo(44));
        expect(t.getSize(_pick(r, 'reviewPickAuto')).height, greaterThanOrEqualTo(44));
      }
      expect(find.text('Send Money · 0722***555'), findsOneWidget);
      h.dispose();
    });

    testWidgets('mixed picks then Confirm: only the picked person on Auto-record, toast counts them', (t) async {
      final s = await _fake();
      final out = <ReviewApplied?>[];
      await _host(t, _Opener(s, out));
      await _tap(t, find.byKey(const Key('open')));
      await _tap(t, _pick(tim, 'reviewPickAuto'));
      await _tap(t, _pick(amina, 'reviewPickAuto'));
      await _tap(t, _pick(amina, 'reviewPickAsk')); // changed her mind
      await _tap(t, find.byKey(const Key('reviewConfirm')));
      expect(find.byKey(const Key('reviewSheet')), findsNothing);
      expect(out.single!.auto, 1);
      expect((await _get(s, tim)).level, RuleLevel.autoRecord);
      expect((await _get(s, tim)).ceilingCents, 200000);
      expect((await _get(s, amina)).level, RuleLevel.askFirst);
      expect(_toast(), hardReviewToast(1));
      await _clearToast(t);
    });

    testWidgets('Keep all on Ask first: nobody raised, kept toast', (t) async {
      final s = await _fake();
      await _host(t, _Opener(s, []));
      await _tap(t, find.byKey(const Key('open')));
      await _tap(t, _pick(tim, 'reviewPickAuto')); // a pick, then Keep all overrides it
      await _tap(t, find.byKey(const Key('reviewKeepAll')));
      expect((await s.all()).where((r) => r.level == RuleLevel.autoRecord), isEmpty);
      expect(await _pending(s), isEmpty);
      expect(_toast(), kHardReviewKeptToast);
      await _clearToast(t);
    });

    testWidgets('Confirm with nobody picked: everyone on Ask first, kept toast', (t) async {
      final s = await _fake();
      await _host(t, _Opener(s, []));
      await _tap(t, find.byKey(const Key('open')));
      await _tap(t, find.byKey(const Key('reviewConfirm')));
      expect((await s.all()).where((r) => r.level == RuleLevel.autoRecord), isEmpty);
      expect(_toast(), kHardReviewKeptToast);
      await _clearToast(t);
    });

    testWidgets('closing (Back, tap outside) changes nothing: still pending, no toast, even after a pick', (t) async {
      final s = await _fake();
      final before = await s.all();
      final out = <ReviewApplied?>[];
      await _host(t, _Opener(s, out));
      await _tap(t, find.byKey(const Key('open')));
      await _tap(t, _pick(tim, 'reviewPickAuto'));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reviewSheet')), findsNothing);
      await _tap(t, find.byKey(const Key('open')));
      await t.tapAt(const Offset(195, 20));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('reviewSheet')), findsNothing);
      expect(out, [null, null]);
      expect(await s.all(), before);
      expect(_toast(), isNull);
    });

    testWidgets('a pending person with no stored category: Auto-record is disabled and a tap does nothing', (t) async {
      final h = t.ensureSemantics();
      final noCat = _r(ReceiverType.sendMoney, '0700000111', 'No Cat');
      final s = await _fake([noCat]);
      await _host(t, _Opener(s, []));
      await _tap(t, find.byKey(const Key('open')));
      expect(t.getSemantics(_pick(noCat, 'reviewPickAuto')).getSemanticsData().flagsCollection.isEnabled.name, 'isFalse');
      await _tap(t, _pick(noCat, 'reviewPickAuto'));
      await _tap(t, find.byKey(const Key('reviewConfirm')));
      expect((await _get(s, noCat)).level, RuleLevel.askFirst);
      await _clearToast(t);
      h.dispose();
    });

    testWidgets('a store failure on Confirm shows the existing "Could not save" toast; still pending', (t) async {
      final s = await _fake();
      await _host(t, _Opener(s, []));
      await _tap(t, find.byKey(const Key('open')));
      s.detailsOn = false;
      await _tap(t, _pick(tim, 'reviewPickAuto'));
      await _tap(t, find.byKey(const Key('reviewConfirm')));
      expect(_toast(), kLevelSheetSaveFailed);
      expect(await _pending(s), hasLength(3));
      await _clearToast(t);
    });

    for (final mode in ['light', 'dark']) {
      testWidgets('200% text, $mode: no overflow, the choice moves under the name, buttons reachable', (t) async {
        final s = await _fake();
        await _host(t, _Opener(s, []), scale: 2, mode: mode, height: 1400);
        await _tap(t, find.byKey(const Key('open')));
        expect(t.takeException(), isNull);
        final name = t.getRect(find.text('Tim Otieno'));
        final ask = t.getRect(_pick(tim, 'reviewPickAsk'));
        expect(ask.top, greaterThanOrEqualTo(name.bottom));
        await _tap(t, find.byKey(const Key('reviewKeepAll')));
        expect(await _pending(s), isEmpty);
        await _clearToast(t);
      });
    }
  });

  group('review line', () {
    setUp(() => debugAutoRecordUiOverride = true);

    testWidgets('n comes from the autoPending mark only (Gary is not counted); Review opens the sheet', (t) async {
      final s = await _fake();
      await _host(t, ReviewLine(bulk: RuleBulkOps(s)));
      expect(find.text(hardReviewLine(3)), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('reviewLineButton'))).height, greaterThanOrEqualTo(44));
      await _tap(t, find.byKey(const Key('reviewLineButton')));
      expect(find.byKey(const Key('reviewSheet')), findsOneWidget);
      await _tap(t, find.byKey(const Key('reviewConfirm')));
      expect(find.byKey(const Key('reviewLine')), findsNothing); // re-read after the store change
      await _clearToast(t);
    });

    testWidgets('n = 0 draws nothing', (t) async {
      final s = await _fake([gary]);
      await _host(t, ReviewLine(bulk: RuleBulkOps(s)));
      expect(find.byKey(const Key('reviewLine')), findsNothing);
    });

    testWidgets('closing the sheet keeps the line (still pending)', (t) async {
      final s = await _fake();
      await _host(t, ReviewLine(bulk: RuleBulkOps(s)));
      await _tap(t, find.byKey(const Key('reviewLineButton')));
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(find.text(hardReviewLine(3)), findsOneWidget);
    });

    testWidgets('details OFF draws nothing', (t) async {
      final s = await _fake();
      await _host(t, ReviewLine(bulk: RuleBulkOps(s), detailsOn: false));
      expect(find.byKey(const Key('reviewLine')), findsNothing);
    });

    testWidgets('a restore that adds pending people while the page is open shows the line', (t) async {
      final s = await _fake([gary]);
      await _host(t, ReviewLine(bulk: RuleBulkOps(s)));
      expect(find.byKey(const Key('reviewLine')), findsNothing);
      await s.saveRule(tim);
      await t.pumpAndSettle();
      expect(find.text(hardReviewLine(1)), findsOneWidget);
    });

    testWidgets('200% text, dark: no overflow', (t) async {
      final s = await _fake();
      await _host(t, ReviewLine(bulk: RuleBulkOps(s)), scale: 2, mode: 'dark');
      expect(t.takeException(), isNull);
      expect(find.text(hardReviewLine(3)), findsOneWidget);
    });
  });

  testWidgets('flag off (autoRecordUi false): the review line draws nothing', (t) async {
    debugAutoRecordUiOverride = false;
    final s = await _fake();
    await _host(t, ReviewLine(bulk: RuleBulkOps(s)));
    expect(find.byKey(const Key('reviewLine')), findsNothing);
  });
}
