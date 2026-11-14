// The choose-a-category row, against fake callbacks only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/choose_category_copy.dart';
import 'package:mmogo/autoread/ui/choose_category_row.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart' show kActionCategorize;
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

  testWidgets('a compact row: Categorize and Later on a fresh row, no chips on the row', (t) async {
    await open(t, laters: []);
    expect(find.text(kChooseCategoryTitle), findsOneWidget);
    expect(find.text(chooseCategoryFresh(_desc)), findsOneWidget);
    expect(find.byKey(const Key('choose-categorize')), findsOneWidget);
    expect(find.text(kChooseLaterChip), findsOneWidget);
    for (final c in cats) {
      expect(find.byKey(Key('choose-chip-${c.id}')), findsNothing);
    }
    expect(find.byKey(const Key('categorizeSave')), findsNothing, reason: 'the sheet is closed');
  });

  testWidgets('Categorize opens the sheet; picking there and Save calls onPickCategory once with the id', (t) async {
    final picks = <String>[];
    await open(t, picks: picks, laters: []);
    await t.tap(find.byKey(const Key('choose-categorize')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('categorizeSave')), findsOneWidget);
    for (final c in cats) {
      expect(find.byKey(Key('categorizeChip_${c.id}')), findsOneWidget, reason: c.name);
    }
    expect(find.text(kCategorizeNewPill), findsOneWidget);
    await t.tap(find.byKey(const Key('categorizeChip_2')));
    await t.pump();
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(picks, ['2']);
    expect(find.byKey(const Key('categorizeSave')), findsNothing, reason: 'the sheet closed after saving');
  });

  testWidgets('a failed save shows the sheet error and a second Save can try again', (t) async {
    var calls = 0;
    await open(t, onPick: (i, id) async {
      calls++;
      if (calls == 1) throw StateError('no');
    });
    await t.tap(find.byKey(const Key('choose-categorize')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('categorizeChip_1')));
    await t.pump();
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(find.text(kCategorizeSaveFailed), findsOneWidget);
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('Close on the sheet saves nothing and leaves the row', (t) async {
    final picks = <String>[];
    await open(t, picks: picks);
    await t.tap(find.byKey(const Key('choose-categorize')));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip(kCategorizeClose));
    await t.pumpAndSettle();
    expect(picks, isEmpty);
    expect(find.byKey(const Key('choose-categorize')), findsOneWidget);
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

  testWidgets('an airtime row: no Later; the sheet shows its one fixed category preselected, Save picks it', (t) async {
    final picks = <String>[];
    await open(t, item: _item(airtime: true), picks: picks, laters: [], choices: [const CategoryChoice(id: '9', name: 'For myself')]);
    expect(find.byKey(const Key('choose-later')), findsNothing);
    await t.tap(find.byKey(const Key('choose-categorize')));
    await t.pumpAndSettle();
    expect(find.text(kCategorizeAirtimeFixed), findsOneWidget);
    expect(find.text(kCategorizeNewPill), findsNothing);
    await t.tap(find.byKey(const Key('categorizeSave')));
    await t.pumpAndSettle();
    expect(picks, ['9']);
  });

  testWidgets('a load failure says so on the row and the sheet does not open', (t) async {
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
    await t.tap(find.byKey(const Key('choose-categorize')));
    await t.pumpAndSettle();
    expect(find.text(kCategorizeLoadFailed), findsOneWidget);
    expect(find.byKey(const Key('categorizeSave')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('text 1.3, dark $dark: the buttons are 44 px and nothing overflows', (t) async {
      await open(t, scale: 1.3, dark: dark, laters: []);
      expect(t.takeException(), isNull);
      for (final k in ['choose-categorize', 'choose-later']) {
        final f = find.byKey(Key(k));
        expect(t.getSize(f).height, greaterThanOrEqualTo(44), reason: k);
        expect(t.getSize(f).width, greaterThanOrEqualTo(44), reason: k);
        expect(t.getBottomRight(f).dx, lessThanOrEqualTo(360), reason: k);
      }
    });
  }

  testWidgets('spoken label: Choose a category for <description>', (t) async {
    final h = t.ensureSemantics();
    await open(t, laters: []);
    expect(find.bySemanticsLabel('Choose a category for $_desc'), findsOneWidget);
    expect(find.bySemanticsLabel(kActionCategorize), findsOneWidget);
    expect(find.bySemanticsLabel(kChooseLaterChip), findsOneWidget);
    h.dispose();
  });
}
