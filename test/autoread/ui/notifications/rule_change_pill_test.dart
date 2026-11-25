// §AUTOREAD.RULE_CHANGE_PILL tests (slice U3): constants pinned, stage timing on fake time, no expand for Ask
// first / Suggested, Change ceiling callback, replacement, swipe away, semantics, reduced motion, large text,
// dark theme, RTL.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:mmogo/ui/widgets/pill_toast.dart';

Future<void> _host(
  WidgetTester t, {
  double scale = 1,
  double width = 390,
  bool reduce = false,
  bool dark = false,
  TextDirection dir = TextDirection.ltr,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(width, 800);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    navigatorKey: appNavigatorKey,
    theme: AppTheme.forPalette(dark ? AppPalette.dark : AppPalette.light),
    builder: (c, child) => Directionality(
      textDirection: dir,
      child: MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduce,
          platformBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: child!,
      ),
    ),
    home: const Scaffold(body: Center(child: Text('PAGE'))),
  ));
}

const _pill = RuleChangePill();
const _amina = 'Amina Wanjiku';

Future<void> _show(WidgetTester t, String name, RuleLevel level, {int? ceiling, VoidCallback? onChange}) async {
  _pill.show(name, level, ceiling, onChange);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

String _stage2(int? ceiling) => hardPillStage2(_amina, ceiling);

void main() {
  tearDown(() {
    RuleChangePill.dismissNow();
    PillToast.dismissNow();
  });

  test('constants pinned: 1.5 s expand, 2.5 s short hold (PM to confirm), stage 2 >= toast minimum', () {
    expect(kRuleChangePillExpandAfter, const Duration(milliseconds: 1500));
    expect(kRuleChangePillShortHold, const Duration(milliseconds: 2500));
    expect(kRuleChangePillLongHold, kPillToastMinDuration);
    expect(kRuleChangePillLongHold >= kPillToastMinDuration, isTrue);
  });

  test('it is a RuleChangeNotice', () {
    expect(_pill, isA<RuleChangeNotice>());
  });

  testWidgets('Auto-record: stage 1 with the name, expands at 1.5 s, stage 2 stays >= 6 s, then gone', (t) async {
    await _host(t);
    _pill.show(_amina, RuleLevel.autoRecord, null, () {});
    await t.pump();
    expect(find.text(hardPillStage1(_amina, RuleLevel.autoRecord)), findsOneWidget);
    expect(find.text(_stage2(null)), findsNothing);

    await t.pump(const Duration(milliseconds: 1400));
    expect(find.text(_stage2(null)), findsNothing, reason: 'still stage 1 before 1.5 s');

    await t.pump(const Duration(milliseconds: 150)); // 1.55 s
    await t.pump(const Duration(milliseconds: 300)); // resize settles
    expect(find.text(hardPillStage1(_amina, RuleLevel.autoRecord)), findsNothing, reason: 'the same pill grew');
    expect(find.text(_stage2(null)), findsOneWidget);
    expect(find.text(kHardPillStage2Sub), findsOneWidget);
    expect(find.text(kHardPillChangeCeiling), findsOneWidget);

    await t.pump(const Duration(milliseconds: 5500)); // 5.8 s into stage 2
    expect(RuleChangePill.isShowing, isTrue);
    expect(find.text(_stage2(null)), findsOneWidget);

    await t.pump(const Duration(milliseconds: 300)); // past 6 s
    await t.pump(const Duration(milliseconds: 400)); // slide away
    expect(find.text(_stage2(null)), findsNothing);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('stage 2 names the ceiling when there is one', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 50000, onChange: () {});
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_stage2(50000)), findsOneWidget);
    expect(_stage2(50000), contains('500'));
  });

  for (final level in [RuleLevel.askFirst, RuleLevel.suggested]) {
    testWidgets('$level: stage 1 only, never expands, gone after 2.5 s', (t) async {
      await _host(t);
      var called = 0;
      await _show(t, 'Gary Kamau', level, onChange: () => called++);
      expect(find.text(hardPillStage1('Gary Kamau', level)), findsOneWidget);

      await t.pump(const Duration(milliseconds: 1500)); // 1.8 s since show
      expect(find.text(kHardPillChangeCeiling), findsNothing);
      expect(find.text(kHardPillStage2Sub), findsNothing);
      expect(RuleChangePill.isShowing, isTrue);

      await t.pump(const Duration(milliseconds: 600)); // 2.4 s since show: still up
      expect(RuleChangePill.isShowing, isTrue);
      expect(find.text(hardPillStage1('Gary Kamau', level)), findsOneWidget);

      await t.pump(const Duration(milliseconds: 100)); // 2.5 s: the hold ends, the pill starts to leave
      await t.pump(const Duration(milliseconds: 300)); // slide away done
      expect(find.text(hardPillStage1('Gary Kamau', level)), findsNothing);
      expect(RuleChangePill.isShowing, isFalse);
      expect(called, 0);
    });
  }

  testWidgets('Change ceiling: 44 px, runs the callback once and dismisses the pill', (t) async {
    await _host(t);
    var n = 0;
    bool? showingInside;
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {
      n++;
      showingInside = RuleChangePill.isShowing;
    });
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    final btn = find.widgetWithText(TextButton, kHardPillChangeCeiling);
    expect(t.getSize(btn).height, greaterThanOrEqualTo(44));
    expect(t.getSize(btn).width, greaterThanOrEqualTo(44));
    await t.tap(btn);
    await t.pump();
    expect(n, 1);
    expect(showingInside, isFalse, reason: 'the pill is gone before the callback runs');
    expect(RuleChangePill.isShowing, isFalse);
    expect(find.text(_stage2(null)), findsNothing);
  });

  testWidgets('Change ceiling double tap: the callback runs once', (t) async {
    await _host(t);
    var n = 0;
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () => n++);
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    // Two presses in the same frame (a quick double tap lands both before the pill is rebuilt away).
    final press = t.widget<TextButton>(find.widgetWithText(TextButton, kHardPillChangeCeiling)).onPressed!;
    press();
    press();
    await t.pump();
    expect(find.text(kHardPillChangeCeiling), findsNothing, reason: 'no button left for a later tap');
    expect(n, 1);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('Change ceiling that shows a new pill keeps the new one', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord,
        onChange: () => _pill.show('Tim Otieno', RuleLevel.askFirst, null, null));
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text(kHardPillChangeCeiling));
    await t.pump();
    expect(find.text(hardPillStage1('Tim Otieno', RuleLevel.askFirst)), findsOneWidget);
    expect(RuleChangePill.isShowing, isTrue);
  });

  testWidgets('no callback: stage 2 still says it, without a button', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord);
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(_stage2(null)), findsOneWidget);
    expect(find.text(kHardPillChangeCeiling), findsNothing);
  });

  testWidgets('a newer pill replaces the older; the old one never expands later', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await _show(t, 'Gary Kamau', RuleLevel.askFirst);
    expect(find.text(hardPillStage1(_amina, RuleLevel.autoRecord)), findsNothing);
    expect(find.text(hardPillStage1('Gary Kamau', RuleLevel.askFirst)), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text(_stage2(null)), findsNothing);
    await t.pump(const Duration(seconds: 3));
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('it replaces a plain PillToast on screen (no two stacked)', (t) async {
    await _host(t);
    PillToast.show('Saved');
    await t.pump();
    expect(find.text('Saved'), findsOneWidget);
    await _show(t, 'Gary Kamau', RuleLevel.suggested);
    expect(find.text('Saved'), findsNothing);
    expect(PillToast.isShowing, isFalse);
  });

  testWidgets('swipe up dismisses, at stage 1 and at stage 2', (t) async {
    await _host(t);
    await _show(t, 'Gary Kamau', RuleLevel.askFirst);
    await t.drag(find.text(hardPillStage1('Gary Kamau', RuleLevel.askFirst)), const Offset(0, -60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);

    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    await t.drag(find.text(_stage2(null)), const Offset(0, -60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('top centre, inside 90% of the width; stage 2 fills that width', (t) async {
    await _host(t);
    const tim = 'Tim Otieno';
    await _show(t, tim, RuleLevel.autoRecord, onChange: () {});
    final s1 = t.getRect(find.ancestor(of: find.text(hardPillStage1(tim, RuleLevel.autoRecord)), matching: find.byType(Material)).first);
    expect(s1.center.dx, closeTo(195, 1));
    expect(s1.top, lessThan(100));
    expect(s1.width, lessThanOrEqualTo(390 * 0.9 + 0.01));
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    final s2 = t.getRect(find.ancestor(of: find.text(hardPillStage2(tim, null)), matching: find.byType(Material)).first);
    expect(s2.width, closeTo(390 * 0.9, 0.5));
    expect(s2.center.dx, closeTo(195, 1));
    // A short stage 1 sizes to its text (the test font is about 14 px per letter).
    await _show(t, 'Al', RuleLevel.suggested);
    final short = t.getRect(find.ancestor(of: find.text(hardPillStage1('Al', RuleLevel.suggested)), matching: find.byType(Material)).first);
    expect(short.width, lessThan(390 * 0.9));
  });

  testWidgets('semantics: live region at each stage, button labelled', (t) async {
    final handle = t.ensureSemantics();
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    expect(
      t.getSemantics(find.text(hardPillStage1(_amina, RuleLevel.autoRecord))),
      matchesSemantics(label: hardPillStage1(_amina, RuleLevel.autoRecord), isLiveRegion: true),
    );
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    final node = t.getSemantics(find.text(_stage2(null)));
    final region = _liveAncestor(node);
    expect(region, isNotNull);
    expect(region!.label, contains(_stage2(null)));
    expect(region.label, contains(kHardPillStage2Sub));
    expect(find.bySemanticsLabel(kHardPillChangeCeiling), findsOneWidget);
    handle.dispose();
  });

  testWidgets('announces stage 1 and stage 2 to the screen reader', (t) async {
    final said = <String>[];
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final data = (m as Map)['data'] as Map?;
      if (data != null && data['message'] is String) said.add(data['message'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 200000, onChange: () {});
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    expect(said, contains(hardPillStage1(_amina, RuleLevel.autoRecord)));
    expect(said.any((s) => s.contains(_stage2(200000)) && s.contains(kHardPillStage2Sub)), isTrue);
  });

  testWidgets('reduced motion: no slide, fade or resize; still expands and leaves on time', (t) async {
    await _host(t, reduce: true);
    _pill.show(_amina, RuleLevel.autoRecord, null, () {});
    await t.pump();
    Finder above(String text, Type type) => find.ancestor(of: find.text(text), matching: find.byType(type));
    expect(above(hardPillStage1(_amina, RuleLevel.autoRecord), SlideTransition), findsNothing);
    expect(above(hardPillStage1(_amina, RuleLevel.autoRecord), FadeTransition), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing);
    expect(find.text(hardPillStage1(_amina, RuleLevel.autoRecord)), findsOneWidget);
    await t.pump(kRuleChangePillExpandAfter);
    expect(find.text(_stage2(null)), findsOneWidget);
    expect(find.byType(AnimatedSize), findsNothing);
    await t.pump(kRuleChangePillLongHold);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('200% text on a narrow screen: wraps, no overflow, hold times stretch', (t) async {
    await _host(t, scale: 2, width: 320);
    await _show(t, 'Mama Mboga wa Soko la Gikomba', RuleLevel.autoRecord, ceiling: 100000000, onChange: () {});
    expect(t.takeException(), isNull);
    await t.pump(kRuleChangePillExpandAfter); // the expand delay does not stretch
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(hardPillStage2('Mama Mboga wa Soko la Gikomba', 100000000)), findsOneWidget);
    expect(t.takeException(), isNull);
    final btn = find.widgetWithText(TextButton, kHardPillChangeCeiling);
    expect(t.getSize(btn).height, greaterThanOrEqualTo(44));
    await t.pump(const Duration(seconds: 7)); // 6 s x 2 = 12 s at 200%
    expect(RuleChangePill.isShowing, isTrue);
    await t.pump(const Duration(seconds: 6));
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('dark theme and RTL: draws, button at the end side', (t) async {
    await _host(t, dark: true, dir: TextDirection.rtl);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await t.pump(kRuleChangePillExpandAfter);
    await t.pump(const Duration(milliseconds: 300));
    expect(t.takeException(), isNull);
    final pill = t.getRect(find.ancestor(of: find.text(_stage2(null)), matching: find.byType(Material)).first);
    final btn = t.getRect(find.widgetWithText(TextButton, kHardPillChangeCeiling));
    expect(btn.center.dx, lessThan(pill.center.dx), reason: 'end side is the left in RTL');
  });

  testWidgets('no app on screen: show does nothing', (t) async {
    final old = appNavigatorKey;
    addTearDown(() => appNavigatorKey = old);
    appNavigatorKey = GlobalKey<NavigatorState>();
    _pill.show(_amina, RuleLevel.autoRecord, null, null);
    expect(RuleChangePill.isShowing, isFalse);
  });
}

SemanticsNode? _liveAncestor(SemanticsNode node) {
  SemanticsNode? n = node;
  while (n != null) {
    if (n.flagsCollection.isLiveRegion) return n;
    n = n.parent;
  }
  return null;
}
