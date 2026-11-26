@Tags(['autoread'])
library;

// 0.2.2 item 2, slice C0: the confirm dialog before a NEW Auto-record (both bodies, Cancel / scrim / Back
// give false, Turn on gives true, 44 px buttons, large text does not overflow) and the copy file's
// PM-signed edits (no "(optional)" on the label, no "yet" on the Paybill line).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_confirm_dialog.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';

Future<List<bool?>> _open(WidgetTester t, {int? ceilingCents, double scale = 1}) async {
  final results = <bool?>[];
  t.view.physicalSize = const Size(390, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(
      body: Builder(
        builder: (c) => TextButton(
          key: const Key('open'),
          onPressed: () async =>
              results.add(await showHardRuleConfirm(c, name: 'Tim Otieno', category: 'Family & friends', ceilingCents: ceilingCents)),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('no ceiling: title, no-ceiling body, Turn on returns true', (t) async {
    final r = await _open(t);
    expect(find.text('Auto-record Tim Otieno?'), findsOneWidget);
    expect(find.text(hardConfirmBodyNoCeiling('Tim Otieno', 'Family & friends')), findsOneWidget);
    expect(find.textContaining('up to'), findsNothing);
    await t.tap(find.byKey(const Key('hardConfirmOk')));
    await t.pumpAndSettle();
    expect(r, [true]);
  });

  testWidgets('with a ceiling: the amount is in the body; Cancel returns false', (t) async {
    final r = await _open(t, ceilingCents: 200000);
    expect(
        find.text("From now on mmogo records Tim Otieno's payments up to Ksh 2,000 as Family & friends without asking. "
            'Above that it asks first. You can Undo any of them.'),
        findsOneWidget);
    await t.tap(find.byKey(const Key('hardConfirmCancel')));
    await t.pumpAndSettle();
    expect(r, [false]);
  });

  testWidgets('tapping outside (scrim) and Back both return false', (t) async {
    final r = await _open(t);
    await t.tapAt(const Offset(5, 5));
    await t.pumpAndSettle();
    expect(find.byType(HardRuleConfirmDialog), findsNothing);
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(r, [false, false]);
  });

  testWidgets('both buttons are at least 44 px tall and text at 200% does not overflow', (t) async {
    await _open(t, ceilingCents: 100000000, scale: 2);
    expect(t.takeException(), isNull);
    for (final k in ['hardConfirmOk', 'hardConfirmCancel']) {
      expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(44));
    }
  });

  group('copy', () {
    test('PM-signed edits are applied', () {
      expect(kHardCeilingLabel, 'Ask first above Ksh');
      expect(kHardWhyNotWithdrawal.toLowerCase(), isNot(contains('yet')));
    });

    test('pill and row lines keep the name and format amounts in whole shillings', () {
      // I2: the old stage 1/2 pill lines and the old row line were deleted; the signed ones replace them.
      expect(hardPillAuto('Amina Wanjiku', 'Food'), 'Amina Wanjiku set to Auto-record as Food');
      expect(hardPillSuggested('Gary'), 'Gary set to Suggested');
      expect(hardPillUpTo(200000), 'Records up to Ksh 2,000.');
      expect(hardRowRecordsUpTo('Food', 50000), 'Records as Food, up to Ksh 500');
      expect(hardOfferBody('Tim', 'Food', 4), contains('as Food 4 times in a row'));
      expect([for (final l in RuleLevel.values) hardRuleLevelName(l)], ['Suggested', 'Ask first', 'Auto-record']);
    });
  });
}
