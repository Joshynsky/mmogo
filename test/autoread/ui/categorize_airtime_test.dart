// Row 17: the Categorize sheet for an airtime item offers only its own kind's category, preselected and
// not switchable; there is no "+ New". Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

import '../../support/category_choices_fake.dart';
import '../../support/waiting_fakes.dart';

WaitingItem _airtime({required bool other}) {
  final at = DateTime(2026, 10, 18, 8, 30);
  return WaitingItem(
    id: heldIdFor(1),
    kind: WaitingKind.waitingCategory,
    heldAt: at,
    parsed: ParsedSmsFields(
      code: 'SAMPLEAT01',
      sourceType: SmsSourceType.airtime,
      amountCents: 10000,
      transactionCostCents: 0,
      counterpartyLabel: 'Sample Network',
      counterpartyPhone: null,
      paybillAccountNumber: null,
      transactionOccurredAt: at.millisecondsSinceEpoch,
      airtimeOther: other,
    ),
  );
}

Future<void> _open(WidgetTester t, WaitingItem item, CategoryChoices choices, Future<void> Function(String) onSave) async {
  t.view.physicalSize = const Size(360, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () => showCategorizeSheet(context, item: item, choices: choices, onSave: onSave),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
}

FilledButton _save(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('categorizeSave')));

void main() {
  testWidgets('categorize_sheet_offers_only_myself_for_own_item', (t) async {
    final saved = <String>[];
    await _open(t, _airtime(other: false), FakeCategoryChoices(['For myself']), (id) async => saved.add(id));
    expect(find.text('For myself'), findsWidgets);
    expect(find.text('For another number'), findsNothing);
    expect(find.byKey(const Key('categorizeNewPill')), findsNothing);
    expect(find.byKey(const Key('categorizeAirtimeFixed')), findsOneWidget);
    expect(_save(t).onPressed, isNotNull); // preselected
    expect(find.text('Save in For myself'), findsOneWidget);
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(saved, ['c1']);
  });

  testWidgets('categorize_sheet_offers_only_other_for_other_item', (t) async {
    await _open(t, _airtime(other: true), FakeCategoryChoices(['For another number']), (_) async {});
    expect(find.text('For another number'), findsWidgets);
    expect(find.text('For myself'), findsNothing);
    expect(find.byKey(const Key('categorizeNewPill')), findsNothing);
    expect(find.text('Save in For another number'), findsOneWidget);
  });

  testWidgets('categorize_sheet_airtime_category_not_switchable', (t) async {
    await _open(t, _airtime(other: false), FakeCategoryChoices(['For myself']), (_) async {});
    final chip = t.widget<InkWell>(find.byKey(const Key('categorizeChip_c1')));
    expect(chip.onTap, isNull);
    await t.tap(find.byKey(const Key('categorizeChip_c1')), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('Save in For myself'), findsOneWidget); // still chosen, not cleared
  });

  testWidgets('categorize_airtime_no_category_found_save_disabled', (t) async {
    await _open(t, _airtime(other: true), FakeCategoryChoices(const []), (_) async {});
    expect(_save(t).onPressed, isNull);
  });

  testWidgets('categorize_stale_wrong_category_saves_nothing', (t) async {
    // The repository refuses a category that is not the item's kind (it throws); the sheet then stays
    // open with the failure line and nothing is recorded.
    var calls = 0;
    await _open(t, _airtime(other: true), FakeCategoryChoices(['For another number']), (_) async {
      calls++;
      throw StateError('stale category');
    });
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(calls, 1);
    expect(find.text(kCategorizeSaveFailed), findsOneWidget);
    expect(find.byKey(const Key('categorizeSave')), findsOneWidget); // still open
  });

  testWidgets('categorize_non_airtime_item_unchanged_new_pill_and_no_preselect', (t) async {
    final at = DateTime(2026, 10, 18, 8, 30);
    final item = WaitingItem(
      id: heldIdFor(2),
      kind: WaitingKind.waitingCategory,
      heldAt: at,
      parsed: sampleFields(0, at),
    );
    await _open(t, item, FakeCategoryChoices(['Food', 'Rent']), (_) async {});
    expect(find.byKey(const Key('categorizeNewPill')), findsOneWidget);
    expect(find.byKey(const Key('categorizeAirtimeFixed')), findsNothing);
    expect(_save(t).onPressed, isNull);
  });
}
