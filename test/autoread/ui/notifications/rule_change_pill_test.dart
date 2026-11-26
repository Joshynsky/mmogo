// §AUTOREAD.RULE_CHANGE_PILL tests (slices U3 + U-PILL): constants pinned (stage 2 held longer, F-2), signed lines
// with the category, stage timing on fake time, stage 2 in the same box with no resize animation, "Set a limit" /
// "Change" both run onChangeCeiling, no phone number or key in any pill text, replacement, swipe away, semantics,
// reduced motion, large text (stacked button), dark theme, RTL.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill.dart';
import 'package:mmogo/autoread/ui/notifications/rule_change_pill_body.dart';
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
const _amina = 'Amina Wanjiku'; // no digits, so any digit in a no-limit pill would be a leak
const _cat = 'Family & friends';
const _key = '0722123456'; // the person's key (phone number) the caller knows; it must never reach the pill
const _masked = '0722***456';

Future<void> _show(WidgetTester t, String name, RuleLevel level,
    {int? ceiling, VoidCallback? onChange, String? category = _cat}) async {
  _pill.show(name, level, ceiling, onChange, categoryName: category);
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

Future<void> _toStage2(WidgetTester t) async {
  await t.pump(kRuleChangePillExpandAfter);
  await t.pump();
}

String _auto(String name) => hardPillAuto(name, _cat);

/// Every string drawn on screen by Text widgets.
List<String> _allTexts(WidgetTester t) =>
    [for (final w in t.widgetList<Text>(find.byType(Text))) w.data ?? w.textSpan?.toPlainText() ?? ''];

void main() {
  tearDown(() {
    RuleChangePill.dismissNow();
    PillToast.dismissNow();
  });

  test('constants pinned: 1.5 s expand, 2.5 s short hold (PM to confirm), stage 2 held longer than the toast minimum',
      () {
    expect(kRuleChangePillExpandAfter, const Duration(milliseconds: 1500));
    expect(kRuleChangePillShortHold, const Duration(milliseconds: 2500));
    expect(kRuleChangePillLongHold, const Duration(seconds: 10));
    expect(kRuleChangePillLongHold > kPillToastMinDuration, isTrue, reason: 'F-2: stage 2 holds longer');
  });

  test('it is a RuleChangeNotice', () {
    expect(_pill, isA<RuleChangeNotice>());
  });

  group('ruleChangePillLines (signed lines only)', () {
    RuleChangePillLines lines(RuleLevel l, {String? cat = _cat, int? limit, bool stage2 = false, bool button = true}) =>
        ruleChangePillLines(name: _amina, level: l, category: cat, limitCents: limit, stage2: stage2, hasButton: button);

    test('Suggested and Ask first', () {
      expect(lines(RuleLevel.suggested).line1, hardPillSuggested(_amina));
      expect(lines(RuleLevel.askFirst).line1, hardPillAskFirst(_amina, _cat));
      expect(lines(RuleLevel.askFirst, stage2: true).line2, isNull, reason: 'stage 2 is Auto-record only');
    });

    test('Auto-record stage 1 and both stage 2 forms', () {
      expect(lines(RuleLevel.autoRecord).line1, hardPillAuto(_amina, _cat));
      expect(lines(RuleLevel.autoRecord).line2, isNull);
      final any = lines(RuleLevel.autoRecord, stage2: true);
      expect(any.line1, hardPillAuto(_amina, _cat));
      expect(any.line2, kHardPillAnyAmount);
      expect(any.button, kHardPillSetLimit);
      final upTo = lines(RuleLevel.autoRecord, stage2: true, limit: 150000);
      expect(upTo.line2, hardPillUpTo(150000));
      expect(upTo.button, kHardPillChange);
      expect(lines(RuleLevel.autoRecord, stage2: true, button: false).button, isNull);
      expect(upTo.spoken, '${hardPillAuto(_amina, _cat)} ${hardPillUpTo(150000)}');
    });

    test('no category name: the W2 placeholder, never an empty slot', () {
      for (final c in [null, '', '  ']) {
        final l = lines(RuleLevel.askFirst, cat: c).line1;
        expect(l, startsWith('$_amina set to Ask first · '));
        expect(l, contains('[PM to write:'));
      }
    });

    test('no line carries a digit except the limit amount', () {
      for (final level in RuleLevel.values) {
        for (final stage2 in [false, true]) {
          final x = lines(level, stage2: stage2);
          for (final s in [x.line1, x.line2, x.button]) {
            if (s != null) expect(RegExp(r'\d').hasMatch(s), isFalse, reason: s);
          }
        }
      }
    });
  });

  testWidgets('Auto-record: line with the category, the same box grows at 1.5 s, stage 2 held 10 s, then gone',
      (t) async {
    await _host(t);
    _pill.show(_amina, RuleLevel.autoRecord, null, () {}, categoryName: _cat);
    await t.pump();
    expect(find.text(_auto(_amina)), findsOneWidget);
    expect(find.text(_auto(_amina)).evaluate().single.widget, isA<Text>());
    expect(find.textContaining(_cat), findsOneWidget, reason: 'category shown');
    expect(find.text(kHardPillAnyAmount), findsNothing);

    await t.pump(const Duration(milliseconds: 1400));
    expect(find.text(kHardPillAnyAmount), findsNothing, reason: 'still stage 1 before 1.5 s');

    await t.pump(const Duration(milliseconds: 150)); // 1.55 s
    await t.pump(); // drawn at once: no resize to settle
    expect(find.text(_auto(_amina)), findsOneWidget, reason: 'stage 2 keeps the first line (one message growing)');
    expect(find.text(kHardPillAnyAmount), findsOneWidget);
    expect(find.widgetWithText(TextButton, kHardPillSetLimit), findsOneWidget);
    expect(find.text(kHardPillChange), findsNothing);

    await t.pump(const Duration(milliseconds: 9800)); // 9.8 s into stage 2
    expect(RuleChangePill.isShowing, isTrue);
    expect(find.text(kHardPillAnyAmount), findsOneWidget);

    await t.pump(const Duration(milliseconds: 300)); // past 10 s
    await t.pump(const Duration(milliseconds: 400)); // slide away
    expect(find.text(kHardPillAnyAmount), findsNothing);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('stage 2 is drawn in the same box: one Material holds both lines, no AnimatedSize, no second pill',
      (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 150000, onChange: () {});
    final box1 = find.ancestor(of: find.text(_auto(_amina)), matching: find.byType(Material)).first;
    final m1 = t.widget<Material>(box1);
    expect(m1.shape, isA<StadiumBorder>());
    await _toStage2(t);
    expect(find.byType(AnimatedSize), findsNothing, reason: 'no grow animation now');
    final a = find.ancestor(of: find.text(_auto(_amina)), matching: find.byType(Material)).first;
    final b = find.ancestor(of: find.text(hardPillUpTo(150000)), matching: find.byType(Material)).first;
    expect(t.element(a), same(t.element(b)), reason: 'both lines in one box');
    expect(t.widget<Material>(a).shape, isA<RoundedRectangleBorder>());
    expect(find.text(_auto(_amina)), findsOneWidget, reason: 'no second pill');
  });

  testWidgets('with a limit: "Records up to Ksh ..." + Change', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 150000, onChange: () {});
    await _toStage2(t);
    expect(find.text(hardPillUpTo(150000)), findsOneWidget);
    expect(hardPillUpTo(150000), contains('1,500'));
    expect(find.widgetWithText(TextButton, kHardPillChange), findsOneWidget);
    expect(find.text(kHardPillSetLimit), findsNothing);
    expect(find.text(kHardPillAnyAmount), findsNothing);
  });

  for (final limit in [null, 150000]) {
    final label = limit == null ? kHardPillSetLimit : kHardPillChange;
    testWidgets('"$label": 44 px, runs onChangeCeiling once and dismisses the pill first', (t) async {
      await _host(t);
      var n = 0;
      bool? showingInside;
      await _show(t, _amina, RuleLevel.autoRecord, ceiling: limit, onChange: () {
        n++;
        showingInside = RuleChangePill.isShowing;
      });
      await _toStage2(t);
      final btn = find.widgetWithText(TextButton, label);
      expect(t.getSize(btn).height, greaterThanOrEqualTo(44));
      expect(t.getSize(btn).width, greaterThanOrEqualTo(44));
      await t.tap(btn);
      await t.pump();
      expect(n, 1);
      expect(showingInside, isFalse, reason: 'the pill is gone before the callback runs');
      expect(RuleChangePill.isShowing, isFalse);
    });
  }

  testWidgets('double tap: the callback runs once', (t) async {
    await _host(t);
    var n = 0;
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () => n++);
    await _toStage2(t);
    // Two presses in the same frame (a quick double tap lands both before the pill is rebuilt away).
    final press = t.widget<TextButton>(find.widgetWithText(TextButton, kHardPillSetLimit)).onPressed!;
    press();
    press();
    await t.pump();
    expect(find.text(kHardPillSetLimit), findsNothing, reason: 'no button left for a later tap');
    expect(n, 1);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('a callback that shows a new pill keeps the new one', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord,
        onChange: () => _pill.show('Tim Otieno', RuleLevel.askFirst, null, null, categoryName: _cat));
    await _toStage2(t);
    await t.tap(find.text(kHardPillSetLimit));
    await t.pump();
    expect(find.text(hardPillAskFirst('Tim Otieno', _cat)), findsOneWidget);
    expect(RuleChangePill.isShowing, isTrue);
  });

  testWidgets('no callback: stage 2 still says it, without a button', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord);
    await _toStage2(t);
    expect(find.text(kHardPillAnyAmount), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('Ask first: "{name} set to Ask first · {category}", never expands, gone after 2.5 s', (t) async {
    await _host(t);
    var called = 0;
    await _show(t, 'Gary Kamau', RuleLevel.askFirst, onChange: () => called++);
    expect(find.text(hardPillAskFirst('Gary Kamau', _cat)), findsOneWidget);
    expect(find.textContaining(_cat), findsOneWidget, reason: 'category shown');

    await t.pump(const Duration(milliseconds: 1500)); // 1.8 s since show
    expect(find.byType(TextButton), findsNothing);
    expect(find.text(kHardPillAnyAmount), findsNothing);
    await t.pump(const Duration(milliseconds: 600)); // 2.4 s: still up
    expect(RuleChangePill.isShowing, isTrue);
    await t.pump(const Duration(milliseconds: 100)); // 2.5 s: the hold ends
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text(hardPillAskFirst('Gary Kamau', _cat)), findsNothing);
    expect(RuleChangePill.isShowing, isFalse);
    expect(called, 0);
  });

  testWidgets('Suggested: "{name} set to Suggested", never expands, gone after 2.5 s', (t) async {
    await _host(t);
    await _show(t, 'Gary Kamau', RuleLevel.suggested, onChange: () {});
    expect(find.text(hardPillSuggested('Gary Kamau')), findsOneWidget);
    await t.pump(const Duration(milliseconds: 2100)); // 2.4 s
    expect(find.byType(TextButton), findsNothing);
    expect(RuleChangePill.isShowing, isTrue);
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 300));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('no category name from the caller: the placeholder shows, nothing crashes', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {}, category: null);
    expect(find.textContaining('$_amina set to Auto-record as [PM to write:'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  group('never a phone number', () {
    for (final level in RuleLevel.values) {
      for (final limit in [null, 150000]) {
        testWidgets('$level limit=$limit: no key, no masked number, digits only in the limit line', (t) async {
          await _host(t);
          await _show(t, _amina, level, ceiling: limit, onChange: () {});
          final seen = <String>[..._allTexts(t)];
          await _toStage2(t);
          seen.addAll(_allTexts(t));
          final pill = seen.where((s) => s != 'PAGE').toList();
          expect(pill, isNotEmpty);
          for (final s in pill) {
            expect(s, isNot(contains(_key)));
            expect(s, isNot(contains(_masked)));
            expect(s, isNot(contains('***')));
            if (limit != null && level == RuleLevel.autoRecord && s == hardPillUpTo(limit)) continue;
            expect(RegExp(r'\d').hasMatch(s), isFalse, reason: 'digit in "$s"');
          }
        });
      }
    }
  });

  testWidgets('a newer pill replaces the older; the old one never expands later', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await _show(t, 'Gary Kamau', RuleLevel.askFirst);
    expect(find.text(_auto(_amina)), findsNothing);
    expect(find.text(hardPillAskFirst('Gary Kamau', _cat)), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1500));
    expect(find.text(kHardPillAnyAmount), findsNothing);
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
    await t.drag(find.text(hardPillAskFirst('Gary Kamau', _cat)), const Offset(0, -60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);

    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await _toStage2(t);
    await t.drag(find.text(kHardPillAnyAmount), const Offset(0, -60));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('top centre, inside 90% of the width; stage 2 fills that width', (t) async {
    await _host(t);
    const tim = 'Tim';
    await _show(t, tim, RuleLevel.autoRecord, onChange: () {}, category: 'Food');
    final s1 = t.getRect(find.ancestor(of: find.text(hardPillAuto(tim, 'Food')), matching: find.byType(Material)).first);
    expect(s1.center.dx, closeTo(195, 1));
    expect(s1.top, lessThan(100));
    expect(s1.width, lessThanOrEqualTo(390 * 0.9 + 0.01));
    await _toStage2(t);
    final s2 = t.getRect(find.ancestor(of: find.text(kHardPillAnyAmount), matching: find.byType(Material)).first);
    expect(s2.width, closeTo(390 * 0.9, 0.5));
    expect(s2.center.dx, closeTo(195, 1));
    expect(s2.top, closeTo(s1.top, 0.5), reason: 'the box grows downward from the same top');
    // A short stage 1 sizes to its text.
    await _show(t, 'Al', RuleLevel.suggested);
    final short = t.getRect(find.ancestor(of: find.text(hardPillSuggested('Al')), matching: find.byType(Material)).first);
    expect(short.width, lessThan(390 * 0.9));
  });

  testWidgets('semantics: one live region gains the limit line; the button is labelled on its own', (t) async {
    final handle = t.ensureSemantics();
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 150000, onChange: () {});
    expect(
      t.getSemantics(find.text(_auto(_amina))),
      matchesSemantics(label: _auto(_amina), isLiveRegion: true),
    );
    await _toStage2(t);
    final region = _liveAncestor(t.getSemantics(find.text(hardPillUpTo(150000))));
    expect(region, isNotNull);
    expect(region!.label, contains(_auto(_amina)));
    expect(region.label, contains(hardPillUpTo(150000)));
    expect(find.bySemanticsLabel(kHardPillChange), findsOneWidget);
    handle.dispose();
  });

  testWidgets('announces stage 1 and stage 2 to the screen reader (with the category, no number)', (t) async {
    final said = <String>[];
    t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (m) async {
      final data = (m as Map)['data'] as Map?;
      if (data != null && data['message'] is String) said.add(data['message'] as String);
      return null;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, ceiling: 200000, onChange: () {});
    await _toStage2(t);
    expect(said, contains(_auto(_amina)));
    expect(said, contains('${_auto(_amina)} ${hardPillUpTo(200000)}'));
    expect(said.any((s) => s.contains(_key) || s.contains(_masked)), isFalse);
  });

  testWidgets('reduced motion: no slide or fade; still expands and leaves on time', (t) async {
    await _host(t, reduce: true);
    _pill.show(_amina, RuleLevel.autoRecord, null, () {}, categoryName: _cat);
    await t.pump();
    Finder above(String text, Type type) => find.ancestor(of: find.text(text), matching: find.byType(type));
    expect(above(_auto(_amina), SlideTransition), findsNothing);
    expect(above(_auto(_amina), FadeTransition), findsNothing);
    expect(find.byType(AnimatedSize), findsNothing);
    await t.pump(kRuleChangePillExpandAfter);
    expect(find.text(kHardPillAnyAmount), findsOneWidget);
    await t.pump(kRuleChangePillLongHold);
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('200% text on a narrow screen: the button stacks under the line, no overflow, hold times stretch',
      (t) async {
    await _host(t, scale: 2, width: 320);
    const mama = 'Mama Mboga wa Soko la Gikomba';
    await _show(t, mama, RuleLevel.autoRecord, ceiling: 100000000, onChange: () {});
    expect(t.takeException(), isNull);
    await _toStage2(t); // the expand delay does not stretch
    expect(find.text(hardPillUpTo(100000000)), findsOneWidget);
    expect(t.takeException(), isNull);
    final btn = find.widgetWithText(TextButton, kHardPillChange);
    expect(t.getSize(btn).height, greaterThanOrEqualTo(44));
    expect(t.getRect(btn).top, greaterThanOrEqualTo(t.getRect(find.text(hardPillUpTo(100000000))).bottom - 0.5),
        reason: 'stacked under the limit line');
    await t.pump(const Duration(seconds: 19)); // 10 s x 2 = 20 s at 200%
    expect(RuleChangePill.isShowing, isTrue);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 400));
    expect(RuleChangePill.isShowing, isFalse);
  });

  testWidgets('normal text: the button sits beside the limit line, at the end side', (t) async {
    await _host(t);
    await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
    await _toStage2(t);
    final line = t.getRect(find.text(kHardPillAnyAmount));
    final btn = t.getRect(find.widgetWithText(TextButton, kHardPillSetLimit));
    expect(btn.left, greaterThan(line.left));
    expect((btn.center.dy - line.center.dy).abs(), lessThan(20), reason: 'same row');
  });

  for (final dark in [false, true]) {
    testWidgets('${dark ? 'dark' : 'light'} theme and RTL: draws, button at the end side (left)', (t) async {
      await _host(t, dark: dark, dir: TextDirection.rtl);
      await _show(t, _amina, RuleLevel.autoRecord, onChange: () {});
      await _toStage2(t);
      expect(t.takeException(), isNull);
      final pill = t.getRect(find.ancestor(of: find.text(kHardPillAnyAmount), matching: find.byType(Material)).first);
      final btn = t.getRect(find.widgetWithText(TextButton, kHardPillSetLimit));
      expect(btn.center.dx, lessThan(pill.center.dx), reason: 'end side is the left in RTL');
      // Not colour alone: the button is underlined text with its own words.
      final style = t.widget<TextButton>(find.widgetWithText(TextButton, kHardPillSetLimit)).style!;
      expect(style.textStyle!.resolve({})!.decoration, TextDecoration.underline);
    });
  }

  testWidgets('no app on screen: show does nothing', (t) async {
    final old = appNavigatorKey;
    addTearDown(() => appNavigatorKey = old);
    appNavigatorKey = GlobalKey<NavigatorState>();
    _pill.show(_amina, RuleLevel.autoRecord, null, null, categoryName: _cat);
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
