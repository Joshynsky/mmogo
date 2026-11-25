// 0.2.2 item 0 Part 1 + F8/F5: the Categorize sheet "Suggested" row, the waiting card chips, "Not now".
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart' show HistorySummaryWriter;
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/ui/categorize_sheet.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/autoread/ui/choose_category_copy.dart';
import 'package:mmogo/autoread/ui/choose_category_row.dart';
import 'package:mmogo/autoread/ui/notifications/notifications_rule_copy.dart' show kAskFirstLater;
import 'package:mmogo/ui/theme/app_theme.dart';

import '../../support/news_fakes.dart' show kFakeNow;
import '../../support/waiting_fakes.dart';

class _Choices implements CategoryChoices {
  _Choices(this.cats);
  final List<CategoryChoice> cats;
  @override
  Future<List<CategoryChoice>> categories() async => cats;
  @override
  Future<CategoryChoice> create(String name) async => throw UnimplementedError();
}

const _fam = CategoryChoice(id: '1', name: 'Family and friends');
const _debts = CategoryChoice(id: '2', name: 'Debts');
const _biz = CategoryChoice(id: '3', name: 'Business');
const _fuel = CategoryChoice(id: '4', name: 'Fuel');
final _all = [_fam, _debts, _biz, _fuel];

WaitingItem _item({int sample = 0}) => WaitingItem(
      id: heldIdFor(1),
      kind: WaitingKind.waitingCategory,
      heldAt: kFakeNow,
      parsed: sampleFields(sample, kFakeNow),
    );

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.theme,
      home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(12), child: child))),
    );

void _size(WidgetTester t, {double width = 400}) {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 900);
  addTearDown(t.view.reset);
}

void main() {
  group('Categorize sheet: Suggested row', () {
    Future<void> openSheet(WidgetTester t,
        {Future<List<CategoryChoice>> Function()? chips, Future<void> Function(String)? onSave}) async {
      _size(t);
      await t.pumpWidget(_host(Builder(
        builder: (c) => TextButton(
          onPressed: () => showCategorizeSheet(c,
              item: _item(), choices: _Choices(_all), onSave: onSave ?? (_) async {}, suggestedChips: chips),
          child: const Text('open'),
        ),
      )));
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }

    testWidgets('chips on top, most used on the RIGHT, rest below, no repeats, labelled', (t) async {
      await openSheet(t, chips: () async => [_debts, _fam]);
      expect(find.text(kCategorizeSuggestedLabel), findsOneWidget);
      expect(find.text(kCategorizeAllLabel), findsOneWidget);
      expect(find.text(kCategorizeCategoryLabel), findsNothing);
      final d = t.getRect(find.byKey(const Key('categorizeChip_2')));
      final f = t.getRect(find.byKey(const Key('categorizeChip_1')));
      // Reading order (line, then left): the test font is wide, so the chips may wrap.
      expect(d.top != f.top ? d.top < f.top : d.left < f.left, isTrue,
          reason: 'Debts (less used) first, Family and friends (most used) last, on the right');
      for (final c in _all) {
        expect(find.byKey(Key('categorizeChip_${c.id}')), findsOneWidget, reason: c.name);
      }
      expect(t.getRect(find.byKey(const Key('categorizeChip_3'))).top, greaterThan(f.bottom));
      expect(t.getRect(find.text(kCategorizeSuggestedLabel)).top, lessThan(d.top));
    });

    testWidgets('capped at 2 even if 3 are offered', (t) async {
      await openSheet(t, chips: () async => [_biz, _debts, _fam]);
      final row = find.descendant(of: find.byKey(const Key('categorizeSuggestedRow')), matching: find.byType(InkWell));
      expect(row, findsNWidgets(2));
    });

    testWidgets('a chip is selectable and Save uses it', (t) async {
      String? saved;
      await openSheet(t, chips: () async => [_debts], onSave: (id) async => saved = id);
      await t.tap(find.byKey(const Key('categorizeChip_2')));
      await t.pump();
      await t.tap(find.byKey(const Key('categorizeSave')));
      await t.pumpAndSettle();
      expect(saved, '2');
    });

    final cases = <String, Future<List<CategoryChoice>> Function()?>{
      'no callback': null,
      'empty': () async => const <CategoryChoice>[],
      'throws': () async => throw StateError('x'),
      'only unknown categories': () async => [const CategoryChoice(id: '99', name: 'Gone')],
    };
    for (final c in cases.entries) {
      testWidgets('no chips (${c.key}): no label, the full list as today', (t) async {
        await openSheet(t, chips: c.value);
        expect(find.text(kCategorizeSuggestedLabel), findsNothing);
        expect(find.text(kCategorizeAllLabel), findsNothing);
        expect(find.text(kCategorizeCategoryLabel), findsOneWidget);
        expect(find.byKey(const Key('categorizeSuggestedRow')), findsNothing);
        for (final x in _all) {
          expect(find.byKey(Key('categorizeChip_${x.id}')), findsOneWidget);
        }
      });
    }
  });

  group('Waiting card chips', () {
    Future<void> pumpRow(
      WidgetTester t, {
      required Future<List<CategoryChoice>> Function(WaitingItem) chipsFor,
      required Future<bool> Function(WaitingItem, CategoryChoice) onPickChip,
      bool fresh = true,
      WaitingItem? item,
      bool withLater = false,
      double width = 400,
    }) async {
      _size(t, width: width);
      await t.pumpWidget(_host(ChooseCategoryRow(
        item: item ?? _item(),
        description: 'Sent Ksh 300 to Gary',
        fresh: fresh,
        choicesFor: (_) async => _Choices(_all),
        onPickCategory: (i, id) async {},
        chipsFor: chipsFor,
        onPickChip: onPickChip,
        onLater: withLater ? (_) {} : null,
      )));
      await t.pump();
      await t.pump();
    }

    testWidgets('chips left to right, most used last and on the right, after Categorize', (t) async {
      await pumpRow(t, chipsFor: (_) async => [_debts, _fam], onPickChip: (i, c) async => true);
      final cat = t.getRect(find.byKey(const Key('choose-categorize')));
      final d = t.getRect(find.byKey(const Key('choose-chip-2')));
      final f = t.getRect(find.byKey(const Key('choose-chip-1')));
      // Reading order (line, then left): the test font is wide, so the pills may wrap.
      int order(Rect a, Rect b) => a.top != b.top ? a.top.compareTo(b.top) : a.left.compareTo(b.left);
      expect(order(cat, d), lessThan(0));
      expect(order(d, f), lessThan(0));
    });

    testWidgets('N1: a card already on screen re-reads its chips when the history summary changes', (t) async {
      var order = [_debts, _fam];
      var reads = 0;
      await pumpRow(t, chipsFor: (_) async {
        reads++;
        return order;
      }, onPickChip: (i, c) async => true);
      int left(String k) => t.getRect(find.byKey(Key(k))).left.round();
      expect(reads, 1);
      order = [_fam, _debts]; // a record or Undo flipped the best two
      HistorySummaryWriter.changes.value++;
      await t.pump();
      await t.pump();
      expect(reads, 2);
      int ord(String a, String b) {
        final ra = t.getRect(find.byKey(Key(a))), rb = t.getRect(find.byKey(Key(b)));
        return ra.top != rb.top ? ra.top.compareTo(rb.top) : ra.left.compareTo(rb.left);
      }

      expect(ord('choose-chip-1', 'choose-chip-2'), lessThan(0), reason: 'Family now less used (left), Debts last');
      expect(left('choose-chip-1'), isNonNegative);
      // after the card is gone the listener is gone (no error on a later change)
      await t.pumpWidget(const SizedBox());
      HistorySummaryWriter.changes.value++;
      await t.pump();
      expect(reads, 2);
    });

    testWidgets('N5: Not now + Categorize + 2 chips stay on ONE row (no wrap, no overflow)', (t) async {
      await pumpRow(t, withLater: true, width: 700, chipsFor: (_) async => [_debts, _fam], onPickChip: (i, c) async => true);
      final tops = [
        for (final k in ['choose-later', 'choose-categorize', 'choose-chip-2', 'choose-chip-1'])
          t.getRect(find.byKey(Key(k))).top
      ];
      // (the test font is 13 px per letter, much wider than the real one: 700 here is a narrow phone)
      expect(tops.toSet(), hasLength(1), reason: 'one row: $tops');
      expect(t.takeException(), isNull);
    });

    // N5 (emulator re-check 24-11): real phone widths. Never a stray chip alone on a wrapped row: either
    // everything shares one row, or row 1 = Not now + Categorize and row 2 = both chips together.
    // (The test font is much wider than the real one, so both layouts are allowed; the stray-chip one is not.)
    for (final w in [360.0, 390.0]) {
      for (final scale in [1.0, 1.3]) {
        for (final longName in [false, true]) {
          testWidgets('N5: ${w.toInt()} dp, text x$scale, ${longName ? 'long' : 'short'} names: tidy rows, no overflow, 44 px targets', (t) async {
            const long = CategoryChoice(id: '7', name: 'Quarterly_School_Trip_Contributions');
            _size(t, width: w);
            t.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
            await t.pumpWidget(_host(ChooseCategoryRow(
              item: _item(),
              description: 'Sent Ksh 300 to Gary',
              choicesFor: (_) async => _Choices(_all),
              onPickCategory: (i, id) async {},
              chipsFor: (_) async => [longName ? long : _debts, _fam],
              onPickChip: (i, c) async => true,
              onLater: (_) {},
            )));
            await t.pump();
            await t.pump();
            expect(t.takeException(), isNull, reason: 'no overflow');
            final lessKey = longName ? 'choose-chip-7' : 'choose-chip-2';
            final keys = ['choose-later', 'choose-categorize', lessKey, 'choose-chip-1'];
            final r = {for (final k in keys) k: t.getRect(find.byKey(Key(k)))};
            for (final e in r.entries) {
              expect(e.value.height, greaterThanOrEqualTo(44), reason: '${e.key} tap height');
              expect(e.value.width, greaterThanOrEqualTo(44), reason: '${e.key} tap width');
              expect(e.value.right, lessThanOrEqualTo(w), reason: '${e.key} inside the screen');
              expect(e.value.left, greaterThanOrEqualTo(0), reason: '${e.key} inside the screen');
            }
            final rows = {for (final v in r.values) v.top.round()}.toList()..sort();
            if (rows.length == 1) return; // all on one row: fine
            // Huge text in the (very wide) test font may push Not now / Categorize onto lines of their own;
            // the chips still stay together on the last row.
            expect(rows.length, lessThanOrEqualTo(scale > 1 ? 3 : 2), reason: 'too many rows: $rows');
            final chipsTop = r[lessKey]!.top.round();
            expect(r['choose-chip-1']!.top.round(), chipsTop, reason: 'both chips together on one row');
            if (scale == 1.0) {
              expect(r['choose-later']!.top.round(), rows.first, reason: 'Not now on the first row');
              expect(r['choose-categorize']!.top.round(), rows.first, reason: 'Categorize on the first row');
            }
            expect(chipsTop, rows.last, reason: 'chips on the second row');
            expect(r['choose-chip-1']!.left, greaterThan(r[lessKey]!.left), reason: 'most used on the right');
          });
        }
      }
    }

    testWidgets('N5: very long chip names are cut with an ellipsis, never overflow', (t) async {
      const long = CategoryChoice(id: '7', name: 'A very very long category name that cannot fit');
      await pumpRow(t, withLater: true, chipsFor: (_) async => [long, _fam], onPickChip: (i, c) async => true);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('choose-chip-7')), findsOneWidget);
    });

    testWidgets('cap: never more than 2 chips', (t) async {
      await pumpRow(t, chipsFor: (_) async => [_biz, _debts, _fam], onPickChip: (i, c) async => true);
      expect(find.byKey(const Key('choose-chip-3')), findsNothing);
      expect(find.byKey(const Key('choose-chip-2')), findsOneWidget);
      expect(find.byKey(const Key('choose-chip-1')), findsOneWidget);
    });

    final cases = <String, Future<List<CategoryChoice>> Function(WaitingItem)>{
      'empty': (_) async => const <CategoryChoice>[],
      'throws': (_) async => throw StateError('x'),
    };
    for (final c in cases.entries) {
      testWidgets('no chips (${c.key}): only Categorize, as before, no error text', (t) async {
        await pumpRow(t, chipsFor: c.value, onPickChip: (i, ch) async => true);
        expect(find.byKey(const Key('choose-categorize')), findsOneWidget);
        expect(find.byKey(const Key('choose-chip-1')), findsNothing);
        expect(find.text(kCategorizeLoadFailed), findsNothing);
        expect(find.text(kCategorizeSaveFailed), findsNothing);
      });
    }

    testWidgets('an airtime item never shows chips', (t) async {
      await pumpRow(t, item: _item(sample: 2), chipsFor: (_) async => [_fam], onPickChip: (i, c) async => true);
      expect(find.byKey(const Key('choose-chip-1')), findsNothing);
    });

    testWidgets('a chip tap records once, with that chip', (t) async {
      final taps = <String>[];
      await pumpRow(t, chipsFor: (_) async => [_debts, _fam], onPickChip: (i, c) async {
        taps.add(c.id);
        return true;
      });
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.pump();
      expect(taps, ['1']);
    });

    testWidgets('double tap and a second chip while the first is saving: one record only', (t) async {
      final taps = <String>[];
      final gate = Completer<bool>();
      await pumpRow(t, chipsFor: (_) async => [_debts, _fam], onPickChip: (i, c) {
        taps.add(c.id);
        return gate.future;
      });
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.tap(find.byKey(const Key('choose-chip-2')));
      await t.pump();
      expect(taps, ['1']);
      gate.complete(true);
      await t.pump();
      await t.tap(find.byKey(const Key('choose-chip-2')));
      await t.pump();
      expect(taps, ['1'], reason: 'accepted: the row stays locked');
    });

    testWidgets('inactive at tap time: nothing recorded, chips refresh, the user can choose again', (t) async {
      var loads = 0;
      final taps = <String>[];
      await pumpRow(t, chipsFor: (_) async {
        loads++;
        return loads == 1 ? [_debts, _fam] : [_debts];
      }, onPickChip: (i, c) async {
        taps.add(c.id);
        return c.id != '1';
      });
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.pump();
      await t.pump();
      expect(loads, 2, reason: 'chips refreshed');
      expect(find.byKey(const Key('choose-chip-1')), findsNothing);
      await t.tap(find.byKey(const Key('choose-chip-2')));
      await t.pump();
      expect(taps, ['1', '2'], reason: 'a refused tap does not lock the row');
    });

    testWidgets('a failed save shows the save-failed line and allows another tap', (t) async {
      var n = 0;
      await pumpRow(t, chipsFor: (_) async => [_fam], onPickChip: (i, c) async {
        n++;
        if (n == 1) throw StateError('db');
        return true;
      });
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.pump();
      await t.pump();
      expect(find.text(kCategorizeSaveFailed), findsOneWidget);
      await t.tap(find.byKey(const Key('choose-chip-1')));
      await t.pump();
      expect(n, 2);
    });

    testWidgets('Categorize opens the sheet with the Suggested row (no repeats)', (t) async {
      await pumpRow(t, chipsFor: (_) async => [_debts, _fam], onPickChip: (i, c) async => true);
      await t.tap(find.byKey(const Key('choose-categorize')));
      await t.pumpAndSettle();
      expect(find.text(kCategorizeSuggestedLabel), findsOneWidget);
      expect(find.byKey(const Key('categorizeChip_1')), findsOneWidget);
    });
  });

  group('Not now (F8) and the F5 rule', () {
    test('both words are "Not now"', () {
      expect(kAskFirstLater, 'Not now');
      expect(kChooseLaterChip, 'Not now');
    });

    testWidgets('a card from a Parse (fresh) has Not now; a card already in To categorize has none', (t) async {
      final later = <String>[];
      _size(t);
      Future<void> pump(bool fresh) => t.pumpWidget(_host(ChooseCategoryRow(
            key: ValueKey(fresh),
            item: _item(),
            description: 'Sent Ksh 300 to Gary',
            fresh: fresh,
            choicesFor: (_) async => _Choices(_all),
            onPickCategory: (i, id) async {},
            onLater: (i) => later.add(i.id),
          )));
      await pump(true);
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Later'), findsNothing);
      await t.tap(find.byKey(const Key('choose-later')));
      expect(later, [heldIdFor(1)]);
      await pump(false);
      expect(find.text('Not now'), findsNothing);
    });
  });
}
