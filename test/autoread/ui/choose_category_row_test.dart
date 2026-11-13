// The choose-a-category row, against fake callbacks only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/choose_category_copy.dart';
import 'package:mmogo/autoread/ui/choose_category_row.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart' show kFakeNow;
import '../../support/waiting_fakes.dart';

class _Choices implements CategoryChoices {
  _Choices(this.cats);
  final List<CategoryChoice> cats;
  @override
  Future<List<CategoryChoice>> categories() async => cats;
  @override
  Future<CategoryChoice> create(String name) async {
    final c = CategoryChoice(id: '${100 + cats.length}', name: name);
    cats.add(c);
    return c;
  }
}

Widget _host(Widget child, {double scale = 1.0, bool dark = false, double width = 360}) => MaterialApp(
      theme: dark ? AppTheme.forPalette(AppPalette.dark) : AppTheme.theme,
      builder: (context, c) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale), size: Size(width, 800)),
        child: c!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child))),
    );

WaitingItem _item({bool airtime = false}) => WaitingItem(
      id: heldIdFor(1),
      kind: WaitingKind.waitingCategory,
      heldAt: kFakeNow,
      parsed: sampleFields(airtime ? 2 : 0, kFakeNow),
    );

const _desc = 'Sent Ksh 640 to Sample Shop';

void main() {
  final cats = [
    const CategoryChoice(id: '1', name: 'Groceries'),
    const CategoryChoice(id: '2', name: 'Transport and matatu fares'),
    const CategoryChoice(id: '3', name: 'Rent'),
    const CategoryChoice(id: '4', name: 'School fees'),
    const CategoryChoice(id: '5', name: 'Family'),
  ];

  Future<void> open(
    WidgetTester t, {
    WaitingItem? item,
    bool fresh = true,
    List<String>? picks,
    List<String>? laters,
    double scale = 1.0,
    bool dark = false,
    List<CategoryChoice>? choices,
    Future<void> Function(WaitingItem, String)? onPick,
  }) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(360, 800);
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(
      ChooseCategoryRow(
        item: item ?? _item(),
        description: _desc,
        fresh: fresh,
        choicesFor: (_) async => _Choices([...(choices ?? cats)]),
        onPickCategory: onPick ?? (i, id) async => picks?.add(id),
        onLater: laters == null ? null : (i) => laters.add(i.id),
      ),
      scale: scale,
      dark: dark,
    ));
    await t.pump();
    await t.pump();
  }

  testWidgets('chips come from choicesFor, plus + New and Later on a fresh row', (t) async {
    await open(t, laters: []);
    expect(find.text(kChooseCategoryTitle), findsOneWidget);
    expect(find.text(chooseCategoryFresh(_desc)), findsOneWidget);
    for (final c in cats) {
      expect(find.byKey(Key('choose-chip-${c.id}')), findsOneWidget);
    }
    expect(find.text(kCategorizeNewPill), findsOneWidget);
    expect(find.text(kChooseLaterChip), findsOneWidget);
  });

  testWidgets('a chip tap calls onPickCategory once with the id', (t) async {
    final picks = <String>[];
    await open(t, picks: picks);
    await t.tap(find.byKey(const Key('choose-chip-3')));
    await t.pump();
    expect(picks, ['3']);
  });

  testWidgets('double tap is one call', (t) async {
    final picks = <String>[];
    await open(t, picks: picks);
    await t.tap(find.byKey(const Key('choose-chip-1')));
    await t.tap(find.byKey(const Key('choose-chip-1')));
    await t.pump();
    await t.tap(find.byKey(const Key('choose-chip-2')));
    await t.pump();
    expect(picks, ['1']);
  });

  testWidgets('a failed save unlocks the row so a later tap can try again', (t) async {
    var calls = 0;
    await open(t, onPick: (i, id) async {
      calls++;
      if (calls == 1) throw StateError('no');
    });
    await t.tap(find.byKey(const Key('choose-chip-1')));
    await t.pump();
    await t.tap(find.byKey(const Key('choose-chip-1')));
    await t.pump();
    expect(calls, 2);
  });

  testWidgets('Later calls onLater; not shown in To categorize or without a callback', (t) async {
    final laters = <String>[];
    await open(t, laters: laters);
    await t.tap(find.byKey(const Key('choose-later')));
    expect(laters, [heldIdFor(1)]);
    await open(t, laters: laters, fresh: false);
    expect(find.byKey(const Key('choose-later')), findsNothing);
    expect(find.text(chooseCategoryLater(_desc)), findsOneWidget);
    await open(t);
    expect(find.byKey(const Key('choose-later')), findsNothing);
  });

  testWidgets('+ New opens the existing Categorize sheet and saving there picks once', (t) async {
    final picks = <String>[];
    await open(t, picks: picks, laters: []);
    await t.tap(find.byKey(const Key('choose-new')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('categorizeSave')), findsOneWidget);
    await t.tap(find.byKey(const Key('categorizeChip_2')));
    await t.pump();
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(picks, ['2']);
  });

  testWidgets('an airtime row shows its one category, no Later, no + New', (t) async {
    final picks = <String>[];
    await open(t, item: _item(airtime: true), picks: picks, laters: [], choices: [const CategoryChoice(id: '9', name: 'For myself')]);
    expect(find.byKey(const Key('choose-chip-9')), findsOneWidget);
    expect(find.byKey(const Key('choose-later')), findsNothing);
    expect(find.byKey(const Key('choose-new')), findsNothing);
    expect(find.text(kCategorizeAirtimeFixed), findsOneWidget);
    await t.tap(find.byKey(const Key('choose-chip-9')));
    await t.pump();
    expect(picks, ['9']);
  });

  testWidgets('a load failure says so and offers no chips', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(360, 800);
    addTearDown(t.view.reset);
    await t.pumpWidget(_host(ChooseCategoryRow(
      item: _item(),
      description: _desc,
      choicesFor: (_) async => throw StateError('x'),
      onPickCategory: (i, id) async {},
    )));
    await t.pump();
    await t.pump();
    expect(find.text(kCategorizeLoadFailed), findsOneWidget);
    expect(find.byKey(const Key('choose-chips')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('text 1.3, dark $dark: chips wrap onto more than one line, 44 px, no overflow', (t) async {
      await open(t, scale: 1.3, dark: dark, laters: []);
      expect(t.takeException(), isNull);
      final tops = <double>{};
      for (final k in ['choose-chip-1', 'choose-chip-2', 'choose-chip-3', 'choose-chip-4', 'choose-chip-5', 'choose-new', 'choose-later']) {
        final f = find.byKey(Key(k));
        expect(t.getSize(f).height, greaterThanOrEqualTo(44), reason: k);
        expect(t.getSize(f).width, greaterThanOrEqualTo(44), reason: k);
        expect(t.getBottomRight(f).dx, lessThanOrEqualTo(360), reason: k);
        tops.add(t.getTopLeft(f).dy);
      }
      expect(tops.length, greaterThan(1));
    });
  }

  testWidgets('spoken label: Choose a category for <description>', (t) async {
    final h = t.ensureSemantics();
    await open(t, laters: []);
    expect(find.bySemanticsLabel('Choose a category for $_desc'), findsOneWidget);
    expect(find.bySemanticsLabel('Groceries'), findsOneWidget);
    expect(find.bySemanticsLabel(kChooseLaterChip), findsOneWidget);
    h.dispose();
  });
}
