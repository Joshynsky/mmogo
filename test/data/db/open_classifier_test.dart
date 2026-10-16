// 0.1.2 S10c: the open-failure classifier. Fakes only; no file, no database.

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/data/db/open_stage.dart';

const _snap = OpenSnapshot(userVersion: 2, fkViolationRows: 0, facts: {'a': '1'});

class FakeEvidence implements OpenEvidence {
  int? header = 2;
  OpenSnapshot? snapshot = _snap;
  bool clean = true;
  Duration delay = Duration.zero;
  bool throwOnProbe = false;
  int calls = 0;

  Future<T> _go<T>(T v) async {
    calls++;
    if (throwOnProbe) throw StateError('probe failed');
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return v;
  }

  @override
  Future<int?> headerUserVersion() => _go(header);
  @override
  Future<OpenSnapshot?> takeSnapshot() => _go(snapshot);
  @override
  Future<bool> fileIsClean(OpenSnapshot before) => _go(clean);
}

Future<OpenFailureKind> _classify(
  FakeEvidence e, {
  OpenStage stage = OpenStage.inUpgrade,
  OpenSnapshot? snapshot = _snap,
  bool proof = true,
  Duration timeout = const Duration(milliseconds: 200),
}) =>
    classifyOpenFailure(
      error: StateError('x'),
      stage: stage,
      snapshot: snapshot,
      evidence: e,
      proofOnRecord: proof,
      probeTimeout: timeout,
    );

void main() {
  test('kUpg3ProofOnRecord is false: flip only after CA8 is recorded', () {
    expect(kUpg3ProofOnRecord, isFalse, reason: 'flip only after CA8 is recorded');
  });

  test('flag false with every E true = OPN-1 and no probe is called', () async {
    final e = FakeEvidence();
    expect(await _classify(e, proof: false), OpenFailureKind.other);
    expect(e.calls, 0);
  });

  test('the default flag value is used when none is passed', () async {
    final e = FakeEvidence();
    final k = await classifyOpenFailure(error: 1, stage: OpenStage.inUpgrade, snapshot: _snap, evidence: e);
    expect(k, kUpg3ProofOnRecord ? OpenFailureKind.rolledBackUpgrade : OpenFailureKind.other);
  });

  test('flag true with E0..E4 all true = UPG-3', () async {
    expect(await _classify(FakeEvidence()), OpenFailureKind.rolledBackUpgrade);
  });

  group('flag true, each of E0..E4 failing alone = OPN-1', () {
    test('E0: not in onUpgrade (onConfigure / onOpen throw)', () async {
      expect(await _classify(FakeEvidence(), stage: OpenStage.none), OpenFailureKind.other);
      expect(await _classify(FakeEvidence(), stage: OpenStage.afterUpgrade), OpenFailureKind.other);
    });
    test('E1: no snapshot', () async {
      expect(await _classify(FakeEvidence(), snapshot: null), OpenFailureKind.other);
    });
    test('E1: snapshot version outside 1..kDbVersion-1', () async {
      for (final v in [0, kDbVersion, kDbVersion + 1]) {
        final s = OpenSnapshot(userVersion: v, fkViolationRows: 0, facts: const {'a': '1'});
        expect(await _classify(FakeEvidence()..header = v, snapshot: s), OpenFailureKind.other, reason: 'v=$v');
      }
    });
    test('E2: header changed after the failure (and header 4)', () async {
      expect(await _classify(FakeEvidence()..header = 3), OpenFailureKind.other);
      expect(await _classify(FakeEvidence()..header = 4), OpenFailureKind.other);
      expect(await _classify(FakeEvidence()..header = null), OpenFailureKind.other);
    });
    test('E3: the file is not clean', () async {
      expect(await _classify(FakeEvidence()..clean = false), OpenFailureKind.other);
    });
    test('E4: the snapshot differs', () async {
      final e = FakeEvidence()..snapshot = const OpenSnapshot(userVersion: 2, fkViolationRows: 0, facts: {'a': '2'});
      expect(await _classify(e), OpenFailureKind.other);
      final e2 = FakeEvidence()..snapshot = null;
      expect(await _classify(e2), OpenFailureKind.other);
    });
  });

  test('a probe that throws = OPN-1', () async {
    expect(await _classify(FakeEvidence()..throwOnProbe = true), OpenFailureKind.other);
  });

  test('a probe slower than the timeout = OPN-1 (5 s default, shortened here)', () async {
    expect(kProbeTimeout, const Duration(seconds: 5));
    final e = FakeEvidence()..delay = const Duration(milliseconds: 400);
    expect(await _classify(e, timeout: const Duration(milliseconds: 50)), OpenFailureKind.other);
  });

  group('prepareOpenSnapshot', () {
    test('flag false: null and no probe', () async {
      final e = FakeEvidence();
      expect(await prepareOpenSnapshot(e, proofOnRecord: false), isNull);
      expect(e.calls, 0);
    });
    test('flag true, header 1..kDbVersion-1: the snapshot', () async {
      expect(await prepareOpenSnapshot(FakeEvidence(), proofOnRecord: true), _snap);
    });
    test('header at or above kDbVersion (4, 3) or 0 or unreadable: null, no snapshot taken', () async {
      for (final h in <int?>[4, kDbVersion, 0, null]) {
        final e = FakeEvidence()..header = h;
        expect(await prepareOpenSnapshot(e, proofOnRecord: true), isNull, reason: 'h=$h');
        expect(e.calls, 1, reason: 'only the header was read');
      }
    });
    test('a failed or slow snapshot = null', () async {
      expect(await prepareOpenSnapshot(FakeEvidence()..snapshot = null, proofOnRecord: true), isNull);
      expect(await prepareOpenSnapshot(FakeEvidence()..throwOnProbe = true, proofOnRecord: true), isNull);
      final slow = FakeEvidence()..delay = const Duration(milliseconds: 300);
      expect(
        await prepareOpenSnapshot(slow, proofOnRecord: true, probeTimeout: const Duration(milliseconds: 50)),
        isNull,
      );
    });
  });
}
