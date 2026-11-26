// 0.2.2 item 2 slice B-ARR (B-2), the importer alone with fakes: every mark it finishes (recorded, already
// recorded, dropped, flag off) ends in the cancel of that item's alert; a save that throws keeps its mark AND its
// alert; a cancel that throws never stops the others or the import. Invented data only.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';

import '../../support/waiting_fakes.dart';

final DateTime _now = DateTime(2026, 11, 25, 12);
final DateTime _marked = _now.subtract(const Duration(minutes: 5));

WaitingItem _item(int n, RuleLevel level) => WaitingItem(
      id: heldIdFor(n),
      kind: WaitingKind.waitingCategory,
      heldAt: _now.subtract(const Duration(hours: 1)),
      parsed: sampleFields(n, _now),
      hint: RuleHint(level: level, type: ReceiverType.sendMoney, key: '0700000001', suggested: const [7]),
    );

class _Marks implements YesMarks, AutoMarks {
  _Marks([Map<String, DateTime>? m]) : marks = m ?? {};
  Map<String, DateTime> marks;
  @override
  Future<Map<String, DateTime>> read() async => Map.of(marks);
  @override
  Future<void> remove(Iterable<String> ids) async => ids.forEach(marks.remove);
}

void main() {
  late List<String> cancelled;

  QueuedYesImporter importer({
    required _Marks yes,
    required _Marks auto,
    bool live = true,
    Future<int?> Function(String, int)? record,
    Future<void> Function(String)? cancel,
  }) {
    var row = 100;
    return QueuedYesImporter(
      marks: yes,
      undone: FakeUndoneCodes(),
      categoryActive: (_) async => true,
      record: record ?? (_, _) async => ++row,
      now: () => _now,
      autoMarks: auto,
      autoRecheck: (_) async => true,
      markAutomatic: (_) async {},
      cancelAlert: cancel ??
          (id) async {
            cancelled.add(id);
          },
      live: live,
    );
  }

  setUp(() => cancelled = []);

  test('a tapped Yes and a no-tap automatic entry, both recorded: both alerts cancelled, after the record', () async {
    final out = await importer(yes: _Marks({heldIdFor(2): _marked}), auto: _Marks({heldIdFor(1): _marked}))
        .run([_item(1, RuleLevel.autoRecord), _item(2, RuleLevel.askFirst)]);
    expect(out, hasLength(2));
    expect(cancelled, [heldIdFor(2), heldIdFor(1)]);
  });

  test('dropped marks (no item, expired, already recorded) are cancelled too: the "Queued" line is no longer true', () async {
    final out = await importer(
      yes: _Marks({heldIdFor(3): _marked, heldIdFor(4): _now.subtract(const Duration(hours: 25))}),
      auto: _Marks({heldIdFor(1): _marked}),
      record: (_, _) async => null, // the code was already recorded
    ).run([_item(1, RuleLevel.autoRecord), _item(4, RuleLevel.askFirst)]);
    expect(out, isEmpty);
    expect(cancelled.toSet(), {heldIdFor(3), heldIdFor(4), heldIdFor(1)});
  });

  test('flag false: every automatic mark is dropped unrecorded and its alert cancelled', () async {
    final out = await importer(yes: _Marks(), auto: _Marks({heldIdFor(1): _marked}), live: false)
        .run([_item(1, RuleLevel.autoRecord)]);
    expect(out, isEmpty);
    expect(cancelled, [heldIdFor(1)]);
  });

  test('a save that throws keeps its mark and its alert (tried again next time)', () async {
    final auto = _Marks({heldIdFor(1): _marked});
    final out = await importer(yes: _Marks(), auto: auto, record: (_, _) async => throw StateError('db busy'))
        .run([_item(1, RuleLevel.autoRecord)]);
    expect(out, isEmpty);
    expect(auto.marks.keys, [heldIdFor(1)]);
    expect(cancelled, isEmpty);
  });

  test('a cancel that throws stops neither the other cancels nor the import', () async {
    final tried = <String>[];
    final out = await importer(
      yes: _Marks({heldIdFor(2): _marked}),
      auto: _Marks({heldIdFor(1): _marked}),
      cancel: (id) async {
        tried.add(id);
        throw StateError('channel gone');
      },
    ).run([_item(1, RuleLevel.autoRecord), _item(2, RuleLevel.askFirst)]);
    expect(out, hasLength(2));
    expect(tried, [heldIdFor(2), heldIdFor(1)]);
  });

  test('nothing queued: no cancel', () async {
    final out = await importer(yes: _Marks(), auto: _Marks()).run([_item(1, RuleLevel.autoRecord)]);
    expect(out, isEmpty);
    expect(cancelled, isEmpty);
  });
}
