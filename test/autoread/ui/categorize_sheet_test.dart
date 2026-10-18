@Tags(['autoread'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';

import '../../support/category_choices_fake.dart';
import '../../support/waiting_fakes.dart';

WaitingItem _item({bool flagged = false}) {
  final at = DateTime(2026, 10, 18, 8, 30);
  return WaitingItem(
    id: heldIdFor(1),
    kind: WaitingKind.waitingCategory,
    heldAt: at,
    parsed: sampleFields(0, at),
    sameCodeDifferentDetails: flagged,
  );
}

class _Rig {
  _Rig(this.choices, {this.item});
  final FakeCategoryChoices choices;
  WaitingItem? item;
  final saved = <String>[];
  int saveCalls = 0;
  bool closed = false;
}

Future<void> _open(
  WidgetTester tester,
  _Rig rig, {
  Size size = const Size(360, 640),
  double textScale = 1.0,
  double keyboard = 0,
  Future<void> Function(String)? onSave,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          textScaler: TextScaler.linear(textScale),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      );
    },
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await showCategorizeSheet(
                context,
                item: rig.item ?? _item(),
                choices: rig.choices,
                onSave: onSave ??
                    (id) async {
                      rig.saveCalls++;
                      rig.saved.add(id);
                    },
              );
              rig.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

FilledButton _save(WidgetTester t) => t.widget<FilledButton>(find.byKey(const Key('categorizeSave')));

Future<void> _openNew(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('categorizeNewPill')));
  await t.tap(find.byKey(const Key('categorizeNewPill')));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String s) async {
  await t.enterText(find.byKey(const Key('categorizeNewField')), s);
  await t.pump();
}

Future<void> _tapAdd(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('categorizeNewAdd')));
  await t.tap(find.byKey(const Key('categorizeNewAdd')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('shows the parsed details read-only and the category chips', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    expect(find.text('Categorize'), findsWidgets);
    expect(find.text('Ksh 640.00'), findsOneWidget);
    expect(find.text('Sample Shop'), findsOneWidget);
    expect(find.text('18-10-2026, 08:30'), findsOneWidget);
    expect(find.text('Send Money'), findsOneWidget);
    for (final n in ['Food', 'Transport', 'Airtime', 'Rent', '+ New']) {
      expect(find.text(n), findsOneWidget);
    }
  });

  testWidgets('flagged item shows the warning box with an icon', (t) async {
    final rig = _Rig(FakeCategoryChoices(), item: _item(flagged: true));
    await _open(t, rig);
    expect(find.byKey(const Key('categorizeFlag')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.textContaining('Check this one.', findRichText: true), findsOneWidget);
  });

  testWidgets('Save is disabled with no choice and enabled after choosing', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    expect(_save(t).onPressed, isNull);
    expect(find.text('Choose a category to save'), findsOneWidget);
    await t.tap(find.text('Food'));
    await t.pump();
    expect(_save(t).onPressed, isNotNull);
    expect(find.text('Save in Food'), findsOneWidget);
  });

  testWidgets('"+ New" opens a name field and hides the pill', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    expect(find.byKey(const Key('categorizeNewField')), findsOneWidget);
    expect(find.text('New category name'), findsOneWidget);
    expect(find.byKey(const Key('categorizeNewPill')), findsNothing);
  });

  testWidgets('empty name shows an icon and text, creates nothing', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, '   ');
    await _tapAdd(t);
    expect(find.text('Type a name for the category.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('categorizeNewError')), matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
    expect(_save(t).onPressed, isNull);
  });

  testWidgets('duplicate name (any case, spaces) shows an icon and text', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, '  fOOd ');
    await _tapAdd(t);
    expect(find.text('A category named "fOOd" already exists.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('categorizeNewError')), matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
    expect((await rig.choices.categories()).length, 4);
    expect(_save(t).onPressed, isNull);
  });

  testWidgets('a name over 100 characters shows an icon and text', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, 'x' * 101);
    await _tapAdd(t);
    expect(find.text('A category name can be up to 100 characters.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('categorizeNewError')), matching: find.byIcon(Icons.warning_amber_rounded)), findsOneWidget);
    // Exactly 100 is fine.
    await _type(t, 'y' * 100);
    await _tapAdd(t);
    expect(find.byKey(const Key('categorizeNewError')), findsNothing);
  });

  testWidgets('a good name becomes a chosen chip and enables Save', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, ' Gym ');
    await _tapAdd(t);
    expect(find.text('Gym'), findsOneWidget);
    expect(find.text('Save in Gym'), findsOneWidget);
    expect(_save(t).onPressed, isNotNull);
    expect(find.byKey(const Key('categorizeNewField')), findsNothing);
    expect(find.byKey(const Key('categorizeNewPill')), findsOneWidget);
    // The chosen chip carries a check icon (not colour alone).
    expect(find.byIcon(Icons.check), findsOneWidget);
    // The fake (same source as Add) now returns it.
    expect((await rig.choices.categories()).map((c) => c.name), contains('Gym'));
  });

  testWidgets('Enter in the name field adds', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, 'Books');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pumpAndSettle();
    expect(find.text('Save in Books'), findsOneWidget);
    expect(rig.choices.createCalls, 1);
  });

  testWidgets('Save calls onSave once with the right id, even on double tap, then closes', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await t.tap(find.text('Transport'));
    await t.pump();
    final btn = find.byKey(const Key('categorizeSave'));
    await t.tap(btn);
    await t.tap(btn, warnIfMissed: false);
    await t.pumpAndSettle();
    expect(rig.saveCalls, 1);
    expect(rig.saved, ['c2']);
    expect(rig.closed, isTrue);
    expect(find.byType(CategorizeSheet), findsNothing);
  });

  testWidgets('Save with a newly created category passes its id', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await _openNew(t);
    await _type(t, 'Gym');
    await _tapAdd(t);
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(rig.saved, ['c5']);
  });

  testWidgets('a failing Save keeps the sheet open, shows text, and can retry', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    var calls = 0;
    await _open(t, rig, onSave: (id) async {
      calls++;
      if (calls == 1) throw StateError('x');
    });
    await t.tap(find.text('Food'));
    await t.pump();
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(find.text('Could not save. Try again.'), findsOneWidget);
    expect(find.byType(CategorizeSheet), findsOneWidget);
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(CategorizeSheet), findsNothing);
  });

  testWidgets('Close button closes without saving', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await t.tap(find.text('Food'));
    await t.pump();
    await t.tap(find.byKey(const Key('categorizeClose')));
    await t.pumpAndSettle();
    expect(find.byType(CategorizeSheet), findsNothing);
    expect(rig.saveCalls, 0);
    expect(rig.closed, isTrue);
  });

  testWidgets('scrim tap closes without saving', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await t.tapAt(const Offset(180, 10));
    await t.pumpAndSettle();
    expect(find.byType(CategorizeSheet), findsNothing);
    expect(rig.saveCalls, 0);
  });

  testWidgets('Back closes without saving', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await t.tap(find.text('Food'));
    await t.pump();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.byType(CategorizeSheet), findsNothing);
    expect(rig.saveCalls, 0);
  });

  for (final w in [360.0, 390.0]) {
    testWidgets('keyboard open at $w px: name field visible, no overflow', (t) async {
      final rig = _Rig(FakeCategoryChoices(['Food', 'Transport', 'Airtime', 'Rent', 'Health', 'School fees', 'Gifts']));
      await _open(t, rig, size: Size(w, 640), keyboard: 300);
      await _openNew(t);
      final field = find.byKey(const Key('categorizeNewField'));
      final r = t.getRect(field);
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(640 - 300 + 0.5));
      expect(t.takeException(), isNull);
      await _type(t, 'x' * 101);
      await _tapAdd(t);
      expect(find.byKey(const Key('categorizeNewError')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('text scale 1.3 at $w px: no overflow, long names wrap', (t) async {
      final rig = _Rig(FakeCategoryChoices(['Food', 'Transport and fuel for the week', 'Airtime', 'Rent', 'Health', 'School fees', 'Gifts']),
          item: _item(flagged: true));
      await _open(t, rig, size: Size(w, 640), textScale: 1.3);
      await t.ensureVisible(find.text('Transport and fuel for the week'));
      await t.tap(find.text('Transport and fuel for the week'));
      await t.pump();
      expect(t.takeException(), isNull);
      await _openNew(t);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('tall content scrolls instead of overflowing', (t) async {
    final rig = _Rig(FakeCategoryChoices([for (var i = 0; i < 40; i++) 'Category number $i']), item: _item(flagged: true));
    await _open(t, rig, size: const Size(360, 480), textScale: 1.3);
    expect(t.takeException(), isNull);
    await t.scrollUntilVisible(find.byKey(const Key('categorizeSave')), 200, scrollable: find.byType(Scrollable).last);
    expect(find.byKey(const Key('categorizeSave')), findsOneWidget);
  });

  testWidgets('targets are at least 44 px', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    for (final k in ['categorizeClose', 'categorizeNewPill', 'categorizeChip_c1', 'categorizeChip_c4']) {
      final s = t.getSize(find.byKey(Key(k)));
      expect(s.height, greaterThanOrEqualTo(44), reason: k);
      expect(s.width, greaterThanOrEqualTo(44), reason: k);
    }
    expect(t.getSize(find.byKey(const Key('categorizeSave'))).height, greaterThanOrEqualTo(44));
    await _openNew(t);
    expect(t.getSize(find.byKey(const Key('categorizeNewAdd'))).height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byKey(const Key('categorizeNewField'))).height, greaterThanOrEqualTo(44));
  });

  testWidgets('chips are spoken as a chosen/not chosen choice', (t) async {
    final rig = _Rig(FakeCategoryChoices());
    await _open(t, rig);
    await t.tap(find.text('Food'));
    await t.pump();
    final h = t.ensureSemantics();
    expect(t.getSemantics(find.byKey(const Key('categorizeChip_c1'))), matchesSemantics(
      label: 'Food',
      isButton: true,
      hasCheckedState: true,
      isChecked: true,
      isInMutuallyExclusiveGroup: true,
      hasTapAction: true,
    ));
    h.dispose();
  });

  testWidgets('name rules: trim, case-insensitive duplicate, 100 limit (interface)', (t) async {
    final c = FakeCategoryChoices();
    await expectLater(c.create(''), throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.empty)));
    await expectLater(c.create(' rent '), throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.duplicate)));
    await expectLater(c.create('z' * 101), throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.tooLong)));
    expect((await c.create('z' * 100)).name.length, 100);
  });
}
