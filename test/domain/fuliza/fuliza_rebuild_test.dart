// 0.2.0 S12 slice C (Judge C5): Rebuild only adds, never deletes, and is idempotent. Invented data.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/fuliza/fuliza_rebuild.dart';
import 'package:mmogo/domain/fuliza/fuliza_repository.dart';

FulizaEvent _e(String code, FulizaEventKind k) => FulizaEvent(
  kind: k,
  code: code,
  at: DateTime(2026, 11, 1),
  amountCents: 10000,
  feeCents: k == FulizaEventKind.draw ? 100 : 0,
);

void main() {
  tearDown(() => FulizaRebuild.hook = null);

  test('no hook returns 0', () async {
    expect(await FulizaRebuild.run(), 0);
  });

  test('a throwing hook counts as 0', () async {
    FulizaRebuild.hook = () async => throw StateError('x');
    expect(await FulizaRebuild.run(), 0);
  });

  test('adds what is missing, never removes stored events, second run adds nothing', () async {
    final repo = InMemoryFulizaRepository();
    await repo.addEvent(_e('QDMFR00001', FulizaEventKind.draw));
    await repo.addEvent(_e('QDMFR00009', FulizaEventKind.repayFull)); // stored, not among the held messages
    final held = [
      _e('QDMFR00001', FulizaEventKind.draw), // already stored
      _e('QDMFR00002', FulizaEventKind.draw), // missing
    ];
    FulizaRebuild.hook = () async {
      var added = 0;
      for (final e in held) {
        if (await repo.addEvent(e)) added++;
      }
      return added;
    };
    expect(await FulizaRebuild.run(), 1);
    expect((await repo.events()).map((e) => e.code).toSet(), {'QDMFR00001', 'QDMFR00002', 'QDMFR00009'});
    expect(await FulizaRebuild.run(), 0);
    expect((await repo.events()).length, 3);
  });
}
