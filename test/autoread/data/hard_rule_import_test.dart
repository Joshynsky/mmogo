// 0.2.2 item 2 slice B2d: the import of an AUTOMATIC mark (Kotlin's "record" decision) when mmogo opens. Pure
// pick, the importer with fakes (flag false drops every automatic mark, the re-check decides, any failed check
// drops the mark and the item keeps waiting, the row is marked automatic), and the preference marks (a Yes mark
// and an automatic mark under the same key never mix). Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/waiting_fakes.dart';

final DateTime _now = DateTime(2026, 11, 25, 12);
final DateTime _marked = _now.subtract(const Duration(minutes: 5));

RuleHint _hint(RuleLevel l, {List<int> cats = const [7]}) =>
    RuleHint(level: l, type: ReceiverType.sendMoney, key: '0700000001', suggested: cats);

WaitingItem _item(int n, {RuleHint? hint}) => WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _now.subtract(const Duration(hours: 1)),
      parsed: sampleFields(n, _now),
      hint: hint ?? _hint(RuleLevel.autoRecord),
    );

class _Marks implements YesMarks, AutoMarks {
  _Marks([Map<String, DateTime>? m]) : marks = m ?? {};
  Map<String, DateTime> marks;
  final List<String> removed = [];
  @override
  Future<Map<String, DateTime>> read() async => Map.of(marks);
  @override
  Future<void> remove(Iterable<String> ids) async {
    removed.addAll(ids);
    ids.forEach(marks.remove);
  }
}

void main() {
  group('pickAutoMarks (pure)', () {
    QueuedYesPlan plan(List<WaitingItem> items, Map<String, DateTime> marks, {Set<String> undone = const {}}) =>
        pickAutoMarks(items: items, marks: marks, undoneCodes: undone, now: _now);

    test('an auto item with a fresh mark is picked with ITS OWN hint category', () {
      final p = plan([_item(1, hint: _hint(RuleLevel.autoRecord, cats: [9]))], {heldIdFor(1): _marked});
      expect(p.picks.single.categoryId, 9);
      expect(p.drop, isEmpty);
    });

    test('dropped: no item, an Ask first or Suggested hint, no hint, nothing offered, old, future, undone code', () {
      final undoneItem = _item(7);
      final p = plan([
        _item(2, hint: _hint(RuleLevel.askFirst)),
        _item(3, hint: _hint(RuleLevel.suggested)),
        WaitingItem(id: heldIdFor(4), kind: WaitingKind.waitingCategory, heldAt: _now, parsed: sampleFields(4, _now)),
        _item(5, hint: _hint(RuleLevel.autoRecord, cats: const [])),
        _item(6),
        _item(8),
        undoneItem,
      ], {
        heldIdFor(1): _marked, // no such item
        heldIdFor(2): _marked,
        heldIdFor(3): _marked,
        heldIdFor(4): _marked,
        heldIdFor(5): _marked,
        heldIdFor(6): _now.subtract(const Duration(hours: 24, seconds: 1)),
        heldIdFor(8): _now.add(const Duration(minutes: 1)),
        heldIdFor(7): _marked,
      }, undone: {undoneItem.parsed!.code});
      expect(p.picks, isEmpty);
      expect(p.drop, hasLength(8));
    });
  });

  group('QueuedYesImporter, automatic marks', () {
    late _Marks yes;
    late _Marks auto;
    late List<(String, int)> saved;
    late List<int> marked;
    late List<String> rechecked;

    QueuedYesImporter importer({
      bool live = true,
      bool recheck = true,
      bool active = true,
      FakeUndoneCodes? undone,
      Future<int?> Function(String, int)? record,
      bool withRecheck = true,
    }) =>
        QueuedYesImporter(
          marks: yes,
          undone: undone ?? FakeUndoneCodes(),
          categoryActive: (_) async => active,
          record: record ??
              (id, cat) async {
                saved.add((id, cat));
                return 100 + saved.length;
              },
          now: () => _now,
          autoMarks: auto,
          autoRecheck: withRecheck
              ? (i) async {
                  rechecked.add(i.id);
                  return recheck;
                }
              : null,
          markAutomatic: (row) async => marked.add(row),
          live: live,
        );

    setUp(() {
      yes = _Marks();
      auto = _Marks({heldIdFor(1): _marked});
      saved = [];
      marked = [];
      rechecked = [];
    });

    test('the default follows autoRecordLive, which is false', () {
      expect(autoRecordLive, isFalse);
    });

    test('flag false: NO row from any automatic mark; the mark is dropped and nothing is re-checked', () async {
      final out = await importer(live: false).run([_item(1)]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
      expect(marked, isEmpty);
      expect(rechecked, isEmpty);
      expect(auto.removed, [heldIdFor(1)]);
    });

    test('flag false through the default constructor (no live argument): no row', () async {
      final out = await QueuedYesImporter(
        marks: yes,
        undone: FakeUndoneCodes(),
        categoryActive: (_) async => true,
        record: (id, cat) async {
          saved.add((id, cat));
          return 1;
        },
        now: () => _now,
        autoMarks: auto,
        autoRecheck: (_) async => true,
        markAutomatic: (row) async => marked.add(row),
      ).run([_item(1)]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
    });

    test('no re-check given: dropped, never recorded', () async {
      final out = await importer(withRecheck: false).run([_item(1)]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
      expect(auto.removed, [heldIdFor(1)]);
    });

    test('re-check passes: recorded through the save with the hint category, marked automatic, reported automatic', () async {
      final out = await importer().run([_item(1)]);
      expect(saved, [(heldIdFor(1), 7)]);
      expect(marked, [101]);
      expect(out.single.automatic, isTrue);
      expect(out.single.rowId, 101);
      expect(auto.removed, [heldIdFor(1)]);
    });

    test('re-check fails: the mark is dropped, nothing is saved, the item stays (no remove call on it)', () async {
      final out = await importer(recheck: false).run([_item(1)]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
      expect(rechecked, [heldIdFor(1)]);
      expect(auto.removed, [heldIdFor(1)]);
    });

    test('a category that is gone: dropped, nothing saved', () async {
      final out = await importer(active: false).run([_item(1)]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
    });

    test('an undone code (the user undid this message within 24 h) is never recorded again', () async {
      final item = _item(1);
      final undone = FakeUndoneCodes();
      await undone.add(item.parsed!.code, now: _now);
      final out = await importer(undone: undone).run([item]);
      expect(out, isEmpty);
      expect(saved, isEmpty);
      expect(rechecked, isEmpty);
    });

    test('duplicate code (the save writes nothing): no entry, not marked, mark dropped', () async {
      final out = await importer(record: (_, _) async => null).run([_item(1)]);
      expect(out, isEmpty);
      expect(marked, isEmpty);
      expect(auto.removed, [heldIdFor(1)]);
    });

    test('a save that throws keeps the mark (re-checked again next time)', () async {
      final out = await importer(record: (_, _) async => throw StateError('db busy')).run([_item(1)]);
      expect(out, isEmpty);
      expect(auto.removed, isEmpty);
    });

    test('a Yes and an automatic mark in one run: both recorded, only the automatic one is marked', () async {
      yes.marks[heldIdFor(2)] = _marked;
      final out = await importer().run([_item(1), _item(2, hint: _hint(RuleLevel.askFirst))]);
      expect(out.map((e) => (e.itemId, e.automatic)), [(heldIdFor(2), false), (heldIdFor(1), true)]);
      expect(marked, hasLength(1));
    });

    test('a Yes tapped on an auto item that Kotlin did not record (it asked) is recorded as a Yes', () {
      final p = pickQueuedYes(items: [_item(1)], marks: {heldIdFor(1): _marked}, undoneCodes: const {}, now: _now);
      expect(p.picks.single.categoryId, 7);
    });
  });

  group('the preference marks (same key, two kinds of value)', () {
    test('Yes marks are numbers, automatic marks are "auto:<ms>" strings; each reader sees only its own', () async {
      SharedPreferences.setMockInitialValues({
        '$kYesMarkPrefix${heldIdFor(1)}': _marked.millisecondsSinceEpoch,
        '$kYesMarkPrefix${heldIdFor(2)}': '$kAutoMarkTag${_marked.millisecondsSinceEpoch}',
        '$kYesMarkPrefix${heldIdFor(3)}': 'auto:abc',
        '$kYesMarkPrefix${heldIdFor(4)}': 'not a mark',
        '${kYesMarkPrefix}short': 'auto:5',
      });
      expect((await PrefsYesMarks().read()).keys, [heldIdFor(1)]);
      final a = await PrefsAutoMarks().read();
      expect(a, {heldIdFor(2): _marked});
    });

    test('removing automatic marks never removes a Yes mark under the same key', () async {
      SharedPreferences.setMockInitialValues({
        '$kYesMarkPrefix${heldIdFor(1)}': _marked.millisecondsSinceEpoch,
        '$kYesMarkPrefix${heldIdFor(2)}': '${kAutoMarkTag}1',
      });
      await PrefsAutoMarks().remove([heldIdFor(1), heldIdFor(2)]);
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('$kYesMarkPrefix${heldIdFor(1)}'), _marked.millisecondsSinceEpoch);
      expect(p.containsKey('$kYesMarkPrefix${heldIdFor(2)}'), isFalse);
    });

    test('autoMarkTime', () {
      expect(autoMarkTime('auto:0'), DateTime.fromMillisecondsSinceEpoch(0));
      expect(autoMarkTime(5), isNull);
      expect(autoMarkTime('auto:'), isNull);
      expect(autoMarkTime(null), isNull);
    });
  });
}
