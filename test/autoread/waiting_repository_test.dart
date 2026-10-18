@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/model/waiting_repository.dart';

import '../support/waiting_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 10, 0);
  late FakeAutoReadWaitingRepository repo;

  WaitingItem byKind(WaitingKind k) => repo.snapshot.firstWhere((i) => i.kind == k);
  WaitingItem oldestReady() => (repo.snapshot.where((i) => i.kind == WaitingKind.readyToParse).toList()
        ..sort((a, b) => a.heldAt.compareTo(b.heldAt)))
      .first;

  setUp(() {
    repo = FakeAutoReadWaitingRepository.forSet(WaitingDataSet.typical, () => now);
  });

  test('watch emits the current list, then every change', () async {
    final seen = <int>[];
    final sub = repo.watch().listen((l) => seen.add(l.length));
    await Future<void>.delayed(Duration.zero);
    expect(seen, [7]);
    await repo.remove(byKind(WaitingKind.gone).id);
    await Future<void>.delayed(Duration.zero);
    expect(seen, [7, 6]);
    await sub.cancel();
  });

  group('parse', () {
    test('a ready item becomes waiting-category', () async {
      final readable = repo.snapshot.where((i) => i.kind == WaitingKind.readyToParse).toList()
        ..sort((a, b) => b.heldAt.compareTo(a.heldAt)); // newest first
      final id = readable.first.id;
      expect(await repo.parse(id), ParseOutcome.parsed);
      final after = repo.snapshot.firstWhere((i) => i.id == id);
      expect(after.kind, WaitingKind.waitingCategory);
      expect(after.parsed, isNotNull);
    });

    test('the oldest ready item cannot be read and becomes unreadable', () async {
      final oldest = oldestReady();
      expect(await repo.parse(oldest.id), ParseOutcome.couldNotRead);
      expect(repo.snapshot.firstWhere((i) => i.id == oldest.id).kind, WaitingKind.unreadable);
    });

    test('a gone item or unknown id gives gone', () async {
      expect(await repo.parse(byKind(WaitingKind.gone).id), ParseOutcome.gone);
      expect(await repo.parse(heldIdFor(9999)), ParseOutcome.gone);
    });

    test('an item past the window gives gone even though it is stored as ready', () async {
      final late = WaitingItem(
          id: heldIdFor(500), kind: WaitingKind.readyToParse, heldAt: now.subtract(kHeldWindow));
      final r = FakeAutoReadWaitingRepository([late], now: () => now);
      expect(await r.parse(late.id), ParseOutcome.gone);
    });

    test('duplicate removes the held message', () async {
      final i = WaitingItem(id: heldIdFor(501), kind: WaitingKind.readyToParse, heldAt: now);
      final r = FakeAutoReadWaitingRepository([i], now: () => now, duplicateOnParse: {i.id});
      expect(await r.parse(i.id), ParseOutcome.duplicate);
      expect(r.snapshot, isEmpty);
    });
  });

  test('saveCategory removes a waiting item; it throws for anything else', () async {
    final w = byKind(WaitingKind.waitingCategory);
    await repo.saveCategory(w.id, 'food');
    expect(repo.snapshot.any((i) => i.id == w.id), isFalse);
    await expectLater(repo.saveCategory(byKind(WaitingKind.readyToParse).id, 'food'), throwsStateError);
  });

  group('no-discard rule', () {
    test('remove throws StateError for a readable ready item and keeps it', () async {
      final r = byKind(WaitingKind.readyToParse);
      await expectLater(repo.remove(r.id), throwsStateError);
      expect(repo.snapshot.any((i) => i.id == r.id), isTrue);
    });

    test('remove throws StateError for a waiting-category item and keeps it', () async {
      final w = byKind(WaitingKind.waitingCategory);
      await expectLater(repo.remove(w.id), throwsStateError);
      expect(repo.snapshot.any((i) => i.id == w.id), isTrue);
    });

    test('remove works for gone', () async {
      final g = byKind(WaitingKind.gone);
      await repo.remove(g.id);
      expect(repo.snapshot.any((i) => i.id == g.id), isFalse);
    });

    test('remove works for unreadable', () async {
      final oldest = oldestReady();
      await repo.parse(oldest.id);
      await repo.remove(oldest.id);
      expect(repo.snapshot.any((i) => i.id == oldest.id), isFalse);
    });

    test('remove works for a ready item that has run out (counts as gone)', () async {
      final late = WaitingItem(
          id: heldIdFor(502), kind: WaitingKind.readyToParse, heldAt: now.subtract(kHeldWindow));
      final r = FakeAutoReadWaitingRepository([late], now: () => now);
      await r.remove(late.id);
      expect(r.snapshot, isEmpty);
    });

    test('checkRemovable is the one guard', () {
      final w = WaitingItem(
          id: heldIdFor(1), kind: WaitingKind.waitingCategory, heldAt: now, parsed: sampleFields(0, now));
      expect(() => checkRemovable(w, now), throwsStateError);
    });
  });
}
