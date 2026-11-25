// The category chips picker (0.2.2 item 2, slice U-PICK; mock pick-multi, pick-one): order fixed on open
// (chosen first), nothing moves while tapping, a third chip refused with the limit line, the "used before" dot
// has a text label, Done / Back answers, 200% text, RTL, dark, tap targets, and the PickCategories port shape.
import 'dart:ui' show CheckedState;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/levels/category_chips_picker.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

const _cats = [
  CategoryChoice(id: '1', name: 'Food'),
  CategoryChoice(id: '2', name: 'Family & friends'),
  CategoryChoice(id: '3', name: 'Bills'),
  CategoryChoice(id: '4', name: 'Transport'),
  CategoryChoice(id: 'x', name: 'Not a number'),
];

class _Harness {
  List<int>? result;
  bool closed = false;
}

Future<_Harness> _open(
  WidgetTester t, {
  CategoryPickMode mode = CategoryPickMode.upTo2,
  List<CategoryChoice> choices = _cats,
  List<int> initial = const [],
  Set<int> usedBefore = const {},
  String? name = 'Bob',
  double width = 390,
  double height = 800,
  double textScale = 1,
  TextDirection dir = TextDirection.ltr,
  String appearance = 'light',
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final h = _Harness();
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', appearance),
      child: MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Directionality(textDirection: dir, child: child!),
        ),
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () async {
                h.result = await showCategoryChipsPicker(
                  c,
                  mode: mode,
                  choices: choices,
                  initial: initial,
                  usedBefore: usedBefore,
                  name: name,
                );
                h.closed = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pumpAndSettle();
  return h;
}

Finder _chip(int id) => find.byKey(Key('chipsPick.$id'));

bool _checked(WidgetTester t, int id) =>
    t.getSemantics(_chip(id)).getSemanticsData().flagsCollection.isChecked == CheckedState.isTrue;

Map<int, Rect> _rects(WidgetTester t, Iterable<int> ids) => {for (final id in ids) id: t.getRect(_chip(id))};

Future<void> _done(WidgetTester t) async {
  await t.tap(find.byKey(const Key('chipsPickerDone')));
  await t.pumpAndSettle();
}

void main() {
  test('the picker fits the PickCategories port', () {
    const PickCategories port = showCategoryChipsPicker;
    expect(port, isNotNull);
  });

  group('pure', () {
    test('order: chosen first, each part in category order; non-number ids not offered', () {
      expect(chipsPickerOrder(_cats, [4, 2]).map((c) => c.id), ['2', '4', '1', '3']);
      expect(chipsPickerOrder(_cats, const []).map((c) => c.id), ['1', '2', '3', '4']);
    });

    test('start: cut to offered ids, no id twice, at most the mode max, order kept', () {
      expect(chipsPickerStart(_cats, [4, 4, 9, 1, 2], CategoryPickMode.upTo2), [4, 1]);
      expect(chipsPickerStart(_cats, [3, 1], CategoryPickMode.one), [3]);
      expect(chipsPickerMax(CategoryPickMode.one), 1);
      expect(chipsPickerMax(CategoryPickMode.upTo2), 2);
    });
  });

  testWidgets('order on open: the chosen chips come first', (t) async {
    await _open(t, initial: const [3, 4]);
    final r = _rects(t, [1, 2, 3, 4]);
    // Bills (3) then Transport (4) lead; Food (1) follows them.
    expect(r[3]!.left, lessThan(r[4]!.left));
    expect(r[4]!.top <= r[1]!.top, isTrue);
    if (r[4]!.top == r[1]!.top) expect(r[4]!.left, lessThan(r[1]!.left));
    expect(find.text('Not a number'), findsNothing);
    expect(find.text(hardPickerTitleMulti('Bob')), findsOneWidget);
    expect(find.text('${hardPickerUpTo(2)} ${hardPickerCount(2, 2)}'), findsOneWidget);
  });

  testWidgets('nothing moves while tapping (on, off, refused)', (t) async {
    await _open(t, initial: const [3]);
    final before = _rects(t, [1, 2, 3, 4]);
    for (final id in [1, 3, 2, 4, 1]) {
      await t.tap(_chip(id));
      await t.pumpAndSettle();
      expect(_rects(t, [1, 2, 3, 4]), before, reason: 'after tapping $id');
    }
  });

  testWidgets('a third chip is refused with the limit line; Done keeps the two', (t) async {
    final h = await _open(t, initial: const [1, 2]);
    expect(find.byKey(const Key('chipsPickerLimit')), findsNothing);
    await t.tap(_chip(3));
    await t.pumpAndSettle();
    expect(find.text(hardPickerLimit(2)), findsOneWidget);
    expect(_checked(t, 3), isFalse);
    // Turning one off clears the line and frees a place.
    await t.tap(_chip(1));
    await t.pumpAndSettle();
    expect(find.text(hardPickerLimit(2)), findsNothing);
    expect(find.text('${hardPickerUpTo(2)} ${hardPickerCount(1, 2)}'), findsOneWidget);
    await t.tap(_chip(3));
    await t.pumpAndSettle();
    await _done(t);
    expect(h.result, [2, 3]);
  });

  testWidgets('up to 2: Done returns the ids in the order chosen; empty is a real answer', (t) async {
    var h = await _open(t);
    await t.tap(_chip(4));
    await t.tap(_chip(1));
    await t.pumpAndSettle();
    await _done(t);
    expect(h.result, [4, 1]);

    h = await _open(t, initial: const [2]);
    await t.tap(_chip(2));
    await t.pumpAndSettle();
    await _done(t);
    expect(h.closed, isTrue);
    expect(h.result, isEmpty);
  });

  testWidgets('one: a tap moves the choice; no count line; Done returns it', (t) async {
    final h = await _open(t, mode: CategoryPickMode.one, initial: const [1]);
    expect(find.byKey(const Key('chipsPickerCount')), findsNothing);
    expect(find.text(hardPickerTitleOne('Bob')), findsOneWidget);
    await t.tap(_chip(3));
    await t.pumpAndSettle();
    expect(_checked(t, 1), isFalse);
    expect(_checked(t, 3), isTrue);
    expect(t.getSemantics(_chip(3)).getSemanticsData().flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    await _done(t);
    expect(h.result, [3]);
  });

  testWidgets('one: Done with nothing chosen and Back both answer null', (t) async {
    var h = await _open(t, mode: CategoryPickMode.one);
    await _done(t);
    expect(h.closed, isTrue);
    expect(h.result, isNull);

    h = await _open(t, initial: const [1]);
    await t.tap(_chip(2));
    await t.tap(find.byKey(const Key('chipsPickerBack')));
    await t.pumpAndSettle();
    expect(h.closed, isTrue);
    expect(h.result, isNull);
  });

  testWidgets('used before: a dot with a spoken text label and a key line', (t) async {
    final sem = t.ensureSemantics();
    await _open(t, usedBefore: const {3});
    expect(find.bySemanticsLabel('Bills, $kHardPickerUsedBefore'), findsOneWidget);
    expect(find.bySemanticsLabel('Food'), findsOneWidget);
    expect(find.byKey(const Key('chipsPickerUsedKey')), findsOneWidget);
    sem.dispose();
  });

  testWidgets('no used-before key line when nothing was used before', (t) async {
    await _open(t);
    expect(find.byKey(const Key('chipsPickerUsedKey')), findsNothing);
  });

  testWidgets('no name: the title falls back to the existing words', (t) async {
    await _open(t, name: null);
    expect(find.text(kHardSuggestChoose), findsOneWidget);
  });

  testWidgets('no categories: the existing empty line', (t) async {
    await _open(t, choices: const []);
    expect(find.byKey(const Key('chipsPickerEmpty')), findsOneWidget);
  });

  testWidgets('tap targets: chips 48 high, Back and Done at least 44', (t) async {
    await _open(t);
    for (final id in [1, 2, 3, 4]) {
      expect(t.getSize(_chip(id)).height, greaterThanOrEqualTo(48));
    }
    expect(t.getSize(find.byKey(const Key('chipsPickerBack'))).height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byKey(const Key('chipsPickerDone'))).height, greaterThanOrEqualTo(44));
  });

  testWidgets('200% text on a short phone: no overflow, Done stays on screen and works', (t) async {
    final long = [
      for (var i = 1; i <= 14; i++) CategoryChoice(id: '$i', name: 'A rather long category name number $i'),
    ];
    final h = await _open(t, choices: long, initial: const [9], usedBefore: const {2, 9}, textScale: 2, height: 640);
    expect(t.takeException(), isNull);
    final done = t.getRect(find.byKey(const Key('chipsPickerDone')));
    expect(done.bottom, lessThanOrEqualTo(640));
    await t.dragUntilVisible(_chip(14), find.byKey(const Key('chipsPickerScroll')), const Offset(0, -200));
    await t.tap(_chip(14));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await _done(t);
    expect(h.result, [9, 14]);
  });

  testWidgets('RTL: chips run right to left, no overflow', (t) async {
    await _open(t, dir: TextDirection.rtl, initial: const [3], usedBefore: const {1});
    expect(t.takeException(), isNull);
    final r = _rects(t, [3, 1]);
    expect(r[3]!.top, r[1]!.top);
    expect(r[3]!.left, greaterThan(r[1]!.left));
  });

  testWidgets('dark: draws without errors and the chosen chip still says it is chosen', (t) async {
    final sem = t.ensureSemantics();
    await _open(t, appearance: 'dark', initial: const [2], usedBefore: const {2});
    expect(t.takeException(), isNull);
    expect(_checked(t, 2), isTrue);
    expect(find.byIcon(Icons.check), findsOneWidget);
    sem.dispose();
  });
}
