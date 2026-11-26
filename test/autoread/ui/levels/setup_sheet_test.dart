// The Set up sheet (0.2.2 item 2 redesign, slice U-SETUP; mock-remembered-v2 setup-half / setup-full / setup-sm /
// setup-pb / setup-bg / setup-search / chk-rtl-p): title and back arrow, opens at 3/4 and goes to full, the list
// from the source, the type chips, search by name only (F2: never the hidden digits, a typed phone number finds
// nothing), never the key, the level tags, a row tap = onPick and the focus back on the row, Airtime only as a
// link (PM Q3), loading / error / empty / details OFF, 200% text, RTL, light and dark, 44 px targets.
// Invented names and numbers only.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_copy.dart';
import 'package:mmogo/autoread/ui/levels/levels_copy.dart';
import 'package:mmogo/autoread/ui/levels/setup_ports.dart';
import 'package:mmogo/autoread/ui/levels/setup_sheet.dart';
import 'package:mmogo/autoread/ui/levels/setup_type_chips.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import '../../../support/redesign_fakes.dart';

// Full phone keys (what the sheet must never draw) and their masked forms.
const _bobKey = '0722123555';
const _aliceKey = '0711222111';

// The list is lazy: a tall test screen builds every row (small-phone checks pass their own size).
const double _tall = 1600;

List<SetupRecipient> _people() => [
      setupTestRecipient('MAMA MBOGA SHOP',
          type: ReceiverType.pochi, name: 'Mama Mboga', maskedNumber: null, paymentCount: 31, level: RuleLevel.autoRecord),
      setupTestRecipient(_aliceKey, name: 'Alice Wanjiru', maskedNumber: '0711***111', paymentCount: 22, level: RuleLevel.askFirst),
      setupTestRecipient(_bobKey, name: 'Bob Otieno', maskedNumber: '0722***555', paymentCount: 18),
      setupTestRecipient('NAIVAS', type: ReceiverType.buyGoods, name: 'Naivas', maskedNumber: null, paymentCount: 1),
      setupTestRecipient('KPLC PREPAID#1234567',
          type: ReceiverType.payBill, name: 'KPLC Prepaid', maskedNumber: null, paymentCount: 9, level: RuleLevel.askFirst),
      setupTestRecipient('KPLC PREPAID#7654321',
          type: ReceiverType.payBill, name: 'KPLC Prepaid', maskedNumber: null, paymentCount: 2),
      setupTestRecipient('0733444777', name: 'Mary Wanjiku', maskedNumber: '0733***777', paymentCount: 6, level: RuleLevel.suggested),
    ];

class _Harness {
  final picks = <SetupRecipient>[];
  int airtime = 0;
  bool closed = false;
  Completer<void>? pickDone;
}

Future<_Harness> _open(
  WidgetTester t, {
  FakeSetupRecipientsSource? source,
  bool airtime = true,
  double width = 390,
  double height = _tall,
  double textScale = 1,
  TextDirection dir = TextDirection.ltr,
  String appearance = 'light',
  bool settle = true,
  void Function(_Harness h)? setup,
}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final h = _Harness();
  setup?.call(h);
  final src = source ?? FakeSetupRecipientsSource(_people());
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
                await showSetupSheet(
                  c,
                  source: src,
                  onPick: (r) async {
                    h.picks.add(r);
                    if (h.pickDone != null) await h.pickDone!.future;
                  },
                  onAirtime: airtime ? () => h.airtime++ : null,
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
  if (settle) {
    await t.pumpAndSettle();
  } else {
    await t.pump();
  }
  return h;
}

Finder _row(SetupRecipient r) => find.byKey(Key('setupRow.${r.type.code}.${r.key}'));
Finder get _rows => find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('setupRow.'));

List<String> _rowNames(WidgetTester t) => [
      for (final e in _rows.evaluate())
        (t.widget<Text>(find.descendant(of: find.byWidget(e.widget), matching: find.byKey(const Key('setupRowName')))).data)!,
    ];

Future<void> _search(WidgetTester t, String q) async {
  await t.enterText(find.byKey(const Key('setupSearch')), q);
  await t.pumpAndSettle();
}

/// Every text drawn and every semantics label, joined (for "never shows X" checks).
String _everything(WidgetTester t) {
  final texts = [
    for (final e in find.byType(Text).evaluate()) (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '',
    for (final e in find.byType(RichText).evaluate()) (e.widget as RichText).text.toPlainText(),
    for (final e in find.byType(EditableText).evaluate()) (e.widget as EditableText).controller.text,
  ];
  final labels = <String>[];
  void walk(SemanticsNode n) {
    labels
      ..add(n.label)
      ..add(n.value)
      ..add(n.hint)
      ..add(n.tooltip);
    n.visitChildren((c) {
      walk(c);
      return true;
    });
  }

  final sheet = find.byKey(const Key('setupSheet'));
  if (sheet.evaluate().isNotEmpty && t.binding.semanticsEnabled) {
    SemanticsNode n = t.getSemantics(sheet);
    while (n.parent != null) {
      n = n.parent!;
    }
    walk(n);
  }
  return [...texts, ...labels].join('\n');
}

void _noOverflow(WidgetTester t) {
  expect(t.takeException(), isNull);
}

void main() {
  testWidgets('title, back arrow (no X), opens at three quarters, the list in the source order', (t) async {
    await _open(t);
    expect(find.text(kHardSetUpTitle), findsOneWidget);
    expect(find.byKey(const Key('setupBack')), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    final sheetH = t.getSize(find.byKey(const Key('setupSheet'))).height;
    expect(sheetH, closeTo(_tall * kSetupSheetStart, 2));
    expect(_rowNames(t), ['Mama Mboga', 'Alice Wanjiru', 'Bob Otieno', 'Naivas', 'KPLC Prepaid', 'KPLC Prepaid', 'Mary Wanjiku']);
    expect(find.text(kHardSetUpHint), findsOneWidget);
    _noOverflow(t);
  });

  testWidgets('rows style B: name, masked number or "{k} payments", type line, level tag; Suggested has no tag', (t) async {
    await _open(t);
    final people = _people();
    // Bob: number at the end, "Send Money · 18 payments" under it, no tag (no rule).
    final bob = _row(people[2]);
    expect(find.descendant(of: bob, matching: find.text('0722***555')), findsOneWidget);
    expect(find.descendant(of: bob, matching: find.text('${setupTypeName(ReceiverType.sendMoney)} · ${hardPaymentsCount(18)}')),
        findsOneWidget);
    expect(find.descendant(of: bob, matching: find.byKey(const Key('setupTag.askFirst'))), findsNothing);
    // Naivas: no number, so "1 payment" at the end and the type alone under it.
    final naivas = _row(people[3]);
    expect(find.descendant(of: naivas, matching: find.text(hardPaymentsCount(1))), findsOneWidget);
    expect(find.descendant(of: naivas, matching: find.text(setupTypeName(ReceiverType.buyGoods))), findsOneWidget);
    // Tags in words.
    expect(find.descendant(of: _row(people[0]), matching: find.text(kHardLevelAutoRecord)), findsOneWidget);
    expect(find.descendant(of: _row(people[1]), matching: find.text(kHardLevelAskFirst)), findsOneWidget);
    expect(find.descendant(of: _row(people[6]), matching: find.text(kHardLevelSuggested)), findsNothing);
    // Paybill accounts of one business share the name (no account field in the port).
    expect(find.descendant(of: _row(people[4]), matching: find.text('KPLC Prepaid')), findsOneWidget);
    expect(find.descendant(of: _row(people[5]), matching: find.text('KPLC Prepaid')), findsOneWidget);
    // No dark box behind name or number: plain Text, no decorated box between the row and its texts.
    final boxes = find.descendant(of: bob, matching: find.byWidgetPredicate((w) => w is DecoratedBox || (w is Container && w.decoration != null)));
    expect(boxes, findsNothing);
  });

  testWidgets('never shows the key: no full phone number in any text or spoken label', (t) async {
    final sem = t.ensureSemantics();
    await _open(t);
    final all = _everything(t);
    for (final k in [_bobKey, _aliceKey, '0733444777', 'MAMA MBOGA SHOP', 'KPLC PREPAID#1234567', '1234567']) {
      expect(all.contains(k), isFalse, reason: k);
    }
    expect(all.contains('0722***555'), isTrue);
    sem.dispose();
  });

  testWidgets('type chips filter the list; the chosen chip shows its name and count; All shows everyone', (t) async {
    final sem = t.ensureSemantics();
    final src = FakeSetupRecipientsSource(_people());
    await _open(t, source: src);
    await t.tap(find.byKey(const Key('setupType.PB')));
    await t.pumpAndSettle();
    expect(_rowNames(t), ['KPLC Prepaid', 'KPLC Prepaid']);
    expect(find.text('${setupTypeName(ReceiverType.payBill)} 2'), findsOneWidget);
    expect(t.getSemantics(find.byKey(const Key('setupType.PB'))), matchesSemantics(
      label: '${setupTypeName(ReceiverType.payBill)}, 2',
      isButton: true,
      hasSelectedState: true,
      isSelected: true,
      isInMutuallyExclusiveGroup: true,
      hasTapAction: true,
    ));
    await t.tap(find.byKey(const Key('setupType.SM')));
    await t.pumpAndSettle();
    expect(_rowNames(t), ['Alice Wanjiru', 'Bob Otieno', 'Mary Wanjiku']);
    await t.tap(find.byKey(const Key('setupType.BG')));
    await t.pumpAndSettle();
    expect(_rowNames(t), ['Naivas']);
    await t.tap(find.byKey(const Key('setupType.PO')));
    await t.pumpAndSettle();
    expect(_rowNames(t), ['Mama Mboga']);
    // Tapping the chosen chip again = All.
    await t.tap(find.byKey(const Key('setupType.PO')));
    await t.pumpAndSettle();
    expect(_rows, findsNWidgets(7));
    await t.tap(find.byKey(const Key('setupType.SM')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('setupType.all')));
    await t.pumpAndSettle();
    expect(_rows, findsNWidgets(7));
    // One read per open: the chips filter what was read.
    expect(src.calls, [null]);
    sem.dispose();
  });

  testWidgets('Airtime is only a link (PM Q3): closes the sheet and calls onAirtime; hidden when null', (t) async {
    final sem = t.ensureSemantics();
    final h = await _open(t);
    final chip = find.byKey(const Key('setupType.airtime'));
    expect(chip, findsOneWidget);
    final node = t.getSemantics(chip);
    expect(node.label, setupAirtimeChip.$2);
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.flagsCollection.isSelected, isNot(true));
    await t.tap(chip);
    await t.pumpAndSettle();
    expect(h.airtime, 1);
    expect(h.closed, isTrue);
    expect(find.byKey(const Key('setupSheet')), findsNothing);
    sem.dispose();
  });

  testWidgets('no onAirtime: no Airtime chip', (t) async {
    await _open(t, airtime: false);
    expect(find.byKey(const Key('setupType.airtime')), findsNothing);
    expect(find.byKey(const Key('setupType.SM')), findsOneWidget);
  });

  testWidgets('search matches names, any case; chips count what the search left', (t) async {
    await _open(t);
    await _search(t, ' wanji ');
    expect(_rowNames(t), ['Alice Wanjiru', 'Mary Wanjiku']);
    await t.tap(find.byKey(const Key('setupType.SM')));
    await t.pumpAndSettle();
    expect(find.text('${setupTypeName(ReceiverType.sendMoney)} 2'), findsOneWidget);
    await _search(t, 'KPLC');
    expect(_rows, findsNothing); // Send Money chosen, KPLC is Paybill
    expect(find.text(kHardSearchEmpty), findsOneWidget);
  });

  testWidgets('search (F2): a typed phone number, hidden digits, the type or a Paybill account find nothing', (t) async {
    await _open(t);
    for (final q in [_bobKey, '0722123', '123', '+254722123555', '254722123555', '1234567', 'send money', 'paybill', '***']) {
      await _search(t, q);
      expect(_rows, findsNothing, reason: q);
      expect(find.text(kHardSearchEmpty), findsOneWidget, reason: q);
    }
    await _search(t, 'bob');
    expect(_rowNames(t), ['Bob Otieno']);
  });

  testWidgets('a row tap calls onPick with that recipient; the list is read again; the focus comes back to the row',
      (t) async {
    final src = FakeSetupRecipientsSource(_people());
    late _Harness h;
    h = await _open(t, source: src, setup: (x) => x.pickDone = Completer<void>());
    final bob = _people()[2];
    await t.tap(_row(bob));
    await t.pump();
    expect(h.picks, [bob]);
    // A second tap while the person sheet is open does nothing.
    await t.tap(_row(bob), warnIfMissed: false);
    await t.pump();
    expect(h.picks, hasLength(1));
    // The person sheet set Bob to Ask first, then closed.
    src.recipients[2] = setupTestRecipient(_bobKey, name: 'Bob Otieno', maskedNumber: '0722***555', paymentCount: 18, level: RuleLevel.askFirst);
    h.pickDone!.complete();
    await t.pumpAndSettle();
    expect(src.calls, [null, null]);
    expect(find.descendant(of: _row(bob), matching: find.text(kHardLevelAskFirst)), findsOneWidget);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused, isNotNull);
    expect(find.descendant(of: _row(bob), matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode == focused)),
        findsOneWidget);
  });

  testWidgets('loading: a spoken circle; then the rows', (t) async {
    final sem = t.ensureSemantics();
    final gate = Completer<void>();
    final src = _GatedSource(gate.future, _people());
    await _openWith(t, src);
    expect(find.byKey(const Key('setupLoading')), findsOneWidget);
    expect(_rows, findsNothing);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('setupLoading')), findsNothing);
    expect(_rows, findsNWidgets(7));
    sem.dispose();
  });

  testWidgets('error: the source throws -> the existing "Could not load this list." line, read out', (t) async {
    final sem = t.ensureSemantics();
    final src = FakeSetupRecipientsSource(_people())..fail = true;
    await _open(t, source: src);
    expect(find.text(kLevelsLoadFailed), findsOneWidget);
    expect(_rows, findsNothing);
    expect(t.getSemantics(find.byKey(const Key('setupFailed'))).flagsCollection.isLiveRegion, isTrue);
    _noOverflow(t);
    sem.dispose();
  });

  testWidgets('empty: nobody paid yet -> the existing empty line, no hint', (t) async {
    await _open(t, source: FakeSetupRecipientsSource());
    expect(find.text(kLevelsEmpty), findsOneWidget);
    expect(find.text(kHardSetUpHint), findsNothing);
    expect(_rows, findsNothing);
  });

  testWidgets('details OFF: the source answers empty, so nobody is listed (the page hides Set up, I2)', (t) async {
    final sem = t.ensureSemantics();
    final src = FakeSetupRecipientsSource(_people())..detailsOn = false;
    await _open(t, source: src);
    expect(_rows, findsNothing);
    expect(find.text(kLevelsEmpty), findsOneWidget);
    final all = _everything(t);
    for (final n in ['Bob Otieno', 'Alice Wanjiru', '0722***555']) {
      expect(all.contains(n), isFalse, reason: n);
    }
    sem.dispose();
  });

  testWidgets('the handle makes it full and back; its spoken name follows', (t) async {
    final sem = t.ensureSemantics();
    await _open(t);
    expect(t.getSemantics(find.byKey(const Key('setupHandle'))).label, kHardSheetTaller);
    await t.tap(find.byKey(const Key('setupHandle')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('setupSheet'))).height, closeTo(_tall, 2));
    expect(t.getSemantics(find.byKey(const Key('setupHandle'))).label, kHardSheetShorter);
    await t.tap(find.byKey(const Key('setupHandle')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('setupSheet'))).height, closeTo(_tall * kSetupSheetStart, 2));
    sem.dispose();
  });

  testWidgets('dragging the handle up makes it full; down far closes it', (t) async {
    final h = await _open(t);
    await t.drag(find.byKey(const Key('setupHandle')), const Offset(0, -500));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(const Key('setupSheet'))).height, closeTo(_tall, 2));
    await t.drag(find.byKey(const Key('setupHandle')), const Offset(0, 1300));
    await t.pumpAndSettle();
    expect(h.closed, isTrue);
  });

  testWidgets('the back arrow closes the sheet', (t) async {
    final h = await _open(t);
    await t.tap(find.byKey(const Key('setupBack')));
    await t.pumpAndSettle();
    expect(h.closed, isTrue);
    expect(h.picks, isEmpty);
  });

  testWidgets('screen reader: row label = its visible words, a button; title is a header', (t) async {
    final sem = t.ensureSemantics();
    await _open(t);
    final alice = _people()[1];
    expect(
      t.getSemantics(_row(alice)),
      matchesSemantics(
        label: 'Alice Wanjiru, 0711***111, ${setupTypeName(ReceiverType.sendMoney)}, ${hardPaymentsCount(22)}, $kHardLevelAskFirst',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(t.getSemantics(find.byKey(const Key('setupTitle'))).flagsCollection.isHeader, isTrue);
    sem.dispose();
  });

  testWidgets('44 px targets: back, handle, chips, rows, search', (t) async {
    await _open(t);
    expect(t.getSize(find.byKey(const Key('setupBack'))).height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byKey(const Key('setupHandle'))).height, greaterThanOrEqualTo(44));
    expect(t.getSize(find.byKey(const Key('setupHandle'))).width, greaterThanOrEqualTo(44));
    for (final k in ['all', 'SM', 'PB', 'BG', 'PO', 'airtime']) {
      final s = t.getSize(find.byKey(Key('setupType.$k')));
      expect(s.height, greaterThanOrEqualTo(44), reason: k);
      expect(s.width, greaterThanOrEqualTo(44), reason: k);
    }
    for (final r in _rows.evaluate()) {
      expect(t.getSize(find.byWidget(r.widget)).height, greaterThanOrEqualTo(44));
    }
    expect(t.getSize(find.byKey(const Key('setupSearch'))).height, greaterThanOrEqualTo(44));
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('${dark ? 'dark' : 'light'}, text ${(scale * 100).round()}%: no overflow on a small phone, rows reachable',
          (t) async {
        await _open(t, appearance: dark ? 'dark' : 'light', textScale: scale, width: 320, height: 640);
        _noOverflow(t);
        await t.tap(find.byKey(const Key('setupType.SM')));
        await t.pumpAndSettle();
        _noOverflow(t);
        // The last row can be scrolled to and tapped.
        final mary = _people()[6];
        await t.scrollUntilVisible(_row(mary), 200, scrollable: find.descendant(
            of: find.byKey(const Key('setupScroll')), matching: find.byType(Scrollable)).first);
        await t.pumpAndSettle();
        _noOverflow(t);
        expect(_row(mary).hitTestable(), findsOneWidget);
      });
    }
  }

  testWidgets('RTL (chk-rtl-p): draws, the back arrow sits on the right, the tag sits on the left of the row', (t) async {
    await _open(t, dir: TextDirection.rtl);
    _noOverflow(t);
    final sheet = t.getRect(find.byKey(const Key('setupSheet')));
    final back = t.getRect(find.byKey(const Key('setupBack')));
    expect(back.center.dx, greaterThan(sheet.center.dx));
    final alice = _row(_people()[1]);
    final tag = t.getRect(find.descendant(of: alice, matching: find.byKey(const Key('setupTag.askFirst'))));
    final name = t.getRect(find.descendant(of: alice, matching: find.byKey(const Key('setupRowName'))));
    expect(tag.center.dx, lessThan(name.center.dx));
    await t.tap(find.byKey(const Key('setupType.SM')));
    await t.pumpAndSettle();
    _noOverflow(t);
  });

  testWidgets('200% text: the row stacks (number and tag under the name)', (t) async {
    await _open(t, textScale: 2);
    final alice = _row(_people()[1]);
    final name = t.getRect(find.descendant(of: alice, matching: find.byKey(const Key('setupRowName'))));
    final end = t.getRect(find.descendant(of: alice, matching: find.byKey(const Key('setupRowEnd'))));
    expect(end.top, greaterThanOrEqualTo(name.bottom - 1));
    _noOverflow(t);
  });
}

/// The chips' type names (the sheet's single source).
String setupTypeName(ReceiverType t) => setupTypeChip(t).$2;

/// A source that answers only after [gate].
class _GatedSource implements SetupRecipientsSource {
  _GatedSource(this.gate, this.people);
  final Future<void> gate;
  final List<SetupRecipient> people;
  @override
  Future<List<SetupRecipient>> list({ReceiverType? type}) async {
    await gate;
    return people;
  }
}

Future<void> _openWith(WidgetTester t, SetupRecipientsSource src) async {
  t.view.physicalSize = const Size(390, _tall);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', 'light'),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () => showSetupSheet(c, source: src, onPick: (_) async {}),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.byKey(const Key('open')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}
