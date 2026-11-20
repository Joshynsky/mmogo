@Tags(['autoread'])
library;

// 0.2.1 Ask first: a Yes tapped on a phone alert is queued by Kotlin and recorded when the app opens. Pure
// decision (which marks lead to a record), the importer with fakes (duplicate-code protection, a gone
// category, a failing save, no message text), the preference marks, the category names, and the toast with Undo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/data/queued_yes_toast.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/ui/shell/app_messenger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/waiting_fakes.dart';

final DateTime _now = DateTime(2026, 11, 19, 12);

WaitingItem _item(int n, {RuleHint? hint, WaitingKind kind = WaitingKind.waitingCategory}) => WaitingItem(
      id: heldIdFor(n),
      kind: kind,
      heldAt: _now.subtract(const Duration(hours: 1)),
      parsed: kind == WaitingKind.waitingCategory ? sampleFields(n, _now) : null,
      hint: hint,
    );

RuleHint _ask({List<int> cats = const [7]}) =>
    RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: '0712345678', suggested: cats);

class _Marks implements YesMarks {
  _Marks(this.marks);
  Map<String, DateTime> marks;
  final List<String> removed = [];
  @override
  Future<Map<String, DateTime>> read() async => Map.of(marks);
  @override
  Future<void> remove(Iterable<String> ids) async => removed.addAll(ids);
}

class _ThrowingMarks implements YesMarks {
  @override
  Future<Map<String, DateTime>> read() async => throw StateError('prefs');
  @override
  Future<void> remove(Iterable<String> ids) async {}
}

void main() {
  final tapped = _now.subtract(const Duration(minutes: 5));

  group('pickQueuedYes (pure)', () {
    QueuedYesPlan plan(List<WaitingItem> items, Map<String, DateTime> marks, {Set<String> undone = const {}}) =>
        pickQueuedYes(items: items, marks: marks, undoneCodes: undone, now: _now);

    test('an Ask first item with a fresh mark is recorded with the category of ITS OWN hint', () {
      final p = plan([_item(1, hint: _ask(cats: [9, 4]))], {heldIdFor(1): tapped});
      expect(p.picks.single.categoryId, 9);
      expect(p.drop, isEmpty);
    });

    test('no mark, no record: an Ask first item without a mark is left alone', () {
      final p = plan([_item(1, hint: _ask())], {});
      expect(p.picks, isEmpty);
      expect(p.drop, isEmpty);
    });

    test('a mark is dropped, never recorded, when the item is gone, has no Ask first hint, or offers nothing', () {
      final p = plan([
        _item(1), // no hint
        _item(2, hint: const RuleHint(level: RuleLevel.suggested, type: ReceiverType.sendMoney, key: 'k', suggested: [3])),
        _item(3, hint: _ask(cats: const [])),
      ], {for (final n in [1, 2, 3, 4]) heldIdFor(n): tapped});
      expect(p.picks, isEmpty);
      expect(p.drop.toSet(), {for (final n in [1, 2, 3, 4]) heldIdFor(n)});
    });

    test('a mark older than 24 h, or from the future, is dropped', () {
      final p = plan([_item(1, hint: _ask()), _item(2, hint: _ask())], {
        heldIdFor(1): _now.subtract(const Duration(hours: 24, seconds: 1)),
        heldIdFor(2): _now.add(const Duration(minutes: 1)),
      });
      expect(p.picks, isEmpty);
      expect(p.drop, hasLength(2));
    });

    test('a code the user just undid is never recorded again', () {
      final item = _item(1, hint: _ask());
      final p = plan([item], {heldIdFor(1): tapped}, undone: {item.parsed!.code});
      expect(p.picks, isEmpty);
      expect(p.drop, [heldIdFor(1)]);
    });
  });

  group('QueuedYesImporter', () {
    QueuedYesImporter importer(
      _Marks marks,
      List<(String, int)> saved, {
      FakeUndoneCodes? undone,
      bool active = true,
      Future<int?> Function(String, int)? record,
    }) =>
        QueuedYesImporter(
          marks: marks,
          undone: undone ?? FakeUndoneCodes(),
          categoryActive: (_) async => active,
          record: record ??
              (id, cat) async {
                saved.add((id, cat));
                return 100 + saved.length;
              },
          now: () => _now,
        );

    test('records the Yes, reports the row for Undo, and removes the mark', () async {
      final marks = _Marks({heldIdFor(1): tapped});
      final saved = <(String, int)>[];
      final out = await importer(marks, saved).run([_item(1, hint: _ask())]);
      expect(saved, [(heldIdFor(1), 7)]);
      expect(out.single.rowId, 101);
      expect(out.single.amountCents, sampleFields(1, _now).amountCents);
      expect(marks.removed, [heldIdFor(1)]);
    });

    test('an undone code is not recorded (duplicate-code protection) and its mark goes', () async {
      final item = _item(1, hint: _ask());
      final undone = FakeUndoneCodes();
      await undone.add(item.parsed!.code, now: _now);
      final marks = _Marks({heldIdFor(1): tapped});
      final saved = <(String, int)>[];
      final out = await importer(marks, saved, undone: undone).run([item]);
      expect(saved, isEmpty);
      expect(out, isEmpty);
      expect(marks.removed, [heldIdFor(1)]);
    });

    test('a category that is gone records nothing; the item stays for a human choice', () async {
      final marks = _Marks({heldIdFor(1): tapped});
      final saved = <(String, int)>[];
      final out = await importer(marks, saved, active: false).run([_item(1, hint: _ask())]);
      expect(saved, isEmpty);
      expect(out, isEmpty);
      expect(marks.removed, [heldIdFor(1)]);
    });

    test('a code already recorded (the save writes nothing) gives no entry and no toast, and the mark goes', () async {
      final marks = _Marks({heldIdFor(1): tapped});
      final out = await importer(marks, [], record: (_, _) async => null).run([_item(1, hint: _ask())]);
      expect(out, isEmpty);
      expect(marks.removed, [heldIdFor(1)]);
    });

    test('a save that throws keeps its mark for the next ingest and does not stop the others', () async {
      final marks = _Marks({heldIdFor(1): tapped, heldIdFor(2): tapped});
      final out = await importer(marks, [], record: (id, _) async {
        if (id == heldIdFor(1)) throw StateError('db busy');
        return 55;
      }).run([_item(1, hint: _ask()), _item(2, hint: _ask())]);
      expect(out.map((e) => e.itemId), [heldIdFor(2)]);
      expect(marks.removed, [heldIdFor(2)]);
    });

    test('a failing mark store never throws', () async {
      final out = await QueuedYesImporter(
        marks: _ThrowingMarks(),
        undone: FakeUndoneCodes(),
        categoryActive: (_) async => true,
        record: (_, _) async => 1,
      ).run([_item(1, hint: _ask())]);
      expect(out, isEmpty);
    });
  });

  group('PrefsYesMarks and CategoryNameCache (the keys Kotlin writes and reads)', () {
    test('marks: only valid ids with an int time; remove deletes only those', () async {
      SharedPreferences.setMockInitialValues({
        '$kYesMarkPrefix${heldIdFor(1)}': tapped.millisecondsSinceEpoch,
        '$kYesMarkPrefix${heldIdFor(2)}': 'not a number',
        '${kYesMarkPrefix}short': 5,
        'other': 1,
      });
      final marks = PrefsYesMarks();
      expect((await marks.read()).keys, [heldIdFor(1)]);
      await marks.remove([heldIdFor(1)]);
      expect(await marks.read(), isEmpty);
      expect((await SharedPreferences.getInstance()).getInt('other'), 1);
    });

    test('names: written as one JSON object, rewritten whole, removed when empty', () async {
      SharedPreferences.setMockInitialValues({});
      await CategoryNameCache().write({7: 'Transport', 9: 'Food'});
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString(kCategoryNamesKey)!), {'7': 'Transport', '9': 'Food'});
      await CategoryNameCache().write({});
      expect(p.getString(kCategoryNamesKey), isNull);
    });
  });

  group('the toast', () {
    testWidgets('one toast per entry with Undo; Undo calls back once and says where it went', (t) async {
      final undone = <int>[];
      await t.pumpWidget(MaterialApp(
        navigatorKey: appNavigatorKey,
        home: const Scaffold(body: SizedBox()),
      ));
      showQueuedYesToasts([
        const QueuedYesRecorded(itemId: 'a', rowId: 5, amountCents: 50000, categoryId: 7),
      ], (e) async => undone.add(e.rowId));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400)); // the pill slides in
      expect(find.text(queuedYesToast('Ksh 500')), findsOneWidget);
      await t.tap(find.text(kQueuedYesUndo));
      await t.pumpAndSettle();
      expect(undone, [5]);
      expect(find.text(kQueuedYesUndone), findsOneWidget);
    });

    test('no overlay shows nothing and does not throw', () {
      showQueuedYesToasts([const QueuedYesRecorded(itemId: 'a', rowId: 1, amountCents: 100, categoryId: 1)], (_) async {});
    });
  });
}
