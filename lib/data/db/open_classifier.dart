import 'dart:async';

import 'migrations.dart';
import 'open_stage.dart';

/// §DATA.DB.OPEN_CLASSIFIER — what kind of open failure this is (0.1.2 S10c,
/// OF1 / DB7 / CA8). Pure logic plus an evidence interface; no file access
/// here (the real evidence is in open_evidence_file.dart).

/// The Android proof of CA8 (an emulator and the lowest-API image show the
/// plugin rolls an `onUpgrade` throw back, restores `user_version` and leaves
/// no cached handle) is NOT on record. Until it is, every failure is OPN-1.
/// Flip only after CA8 is recorded.
const bool kUpg3ProofOnRecord = false;

/// How long one evidence probe may take.
const Duration kProbeTimeout = Duration(seconds: 5);

enum OpenFailureKind {
  /// UPG-3: a verified rolled-back upgrade (all of E0-E4 and the CA8 proof).
  rolledBackUpgrade,

  /// OPN-1: anything else. Makes no promise about the data.
  other,
}

/// What the file looked like BEFORE the open (E1/E4). Equality is by value.
class OpenSnapshot {
  const OpenSnapshot({required this.userVersion, required this.fkViolationRows, required this.facts});

  /// The header `user_version` (bytes 60-63) before the open.
  final int userVersion;

  /// Row count of `PRAGMA foreign_key_check` before the open.
  final int fkViolationRows;

  /// Everything else E4 compares (counts, sums, schema rows, canary reads),
  /// as sorted `key -> text` facts.
  final Map<String, String> facts;

  @override
  bool operator ==(Object other) =>
      other is OpenSnapshot &&
      other.userVersion == userVersion &&
      other.fkViolationRows == fkViolationRows &&
      other.facts.length == facts.length &&
      facts.entries.every((e) => other.facts[e.key] == e.value);

  @override
  int get hashCode => Object.hash(userVersion, fkViolationRows, facts.length);
}

/// The probes behind E1-E4. Real: reads the file with read-only,
/// `singleInstance: false` opens. Tests: fakes. Each call is bounded and
/// caught by the caller; a throw or timeout counts as "not proven".
abstract class OpenEvidence {
  /// The raw header `user_version` (bytes 60-63), or null when unreadable.
  Future<int?> headerUserVersion();

  /// A read-only snapshot of the file, or null when it cannot be taken.
  Future<OpenSnapshot?> takeSnapshot();

  /// E3: no non-empty `-wal`, no hot `-journal`, a fresh read-only open works,
  /// `quick_check` is ok and the `foreign_key_check` row count equals
  /// [before]'s.
  Future<bool> fileIsClean(OpenSnapshot before);
}

/// Runs one probe, bounded; null on any throw or timeout.
Future<T?> _bounded<T>(Future<T?> Function() probe, Duration timeout) async {
  try {
    return await probe().timeout(timeout);
  } catch (_) {
    return null;
  }
}

/// Once per gate run, BEFORE the open (never per retry). With the proof off it
/// returns null and no probe ever runs. With it on: header `user_version`
/// between 1 and [kDbVersion] - 1 takes the snapshot; anything else (above the
/// live version, unreadable, a failed snapshot) returns null = OPN-1.
Future<OpenSnapshot?> prepareOpenSnapshot(
  OpenEvidence evidence, {
  bool proofOnRecord = kUpg3ProofOnRecord,
  Duration probeTimeout = kProbeTimeout,
}) async {
  if (!proofOnRecord) return null;
  final header = await _bounded(evidence.headerUserVersion, probeTimeout);
  if (header == null || header < 1 || header > kDbVersion - 1) return null;
  final snap = await _bounded(evidence.takeSnapshot, probeTimeout);
  if (snap == null || snap.userVersion != header) return null;
  return snap;
}

/// UPG-3 only when [proofOnRecord] AND E0..E4 all hold; every other case,
/// including any probe that throws or takes over [probeTimeout], is OPN-1.
/// With the proof off no probe is called.
Future<OpenFailureKind> classifyOpenFailure({
  required Object error,
  required OpenStage stage,
  required OpenSnapshot? snapshot,
  required OpenEvidence evidence,
  bool proofOnRecord = kUpg3ProofOnRecord,
  Duration probeTimeout = kProbeTimeout,
}) async {
  if (!proofOnRecord) return OpenFailureKind.other;
  // E0: the throw happened while onUpgrade was running.
  if (stage != OpenStage.inUpgrade) return OpenFailureKind.other;
  // E1: a snapshot was taken before the open (header 1..kDbVersion-1).
  if (snapshot == null || snapshot.userVersion < 1 || snapshot.userVersion > kDbVersion - 1) {
    return OpenFailureKind.other;
  }
  // E2: the header user_version still equals the pre-open value.
  final header = await _bounded(evidence.headerUserVersion, probeTimeout);
  if (header == null || header != snapshot.userVersion) return OpenFailureKind.other;
  // E3: no wal / hot journal, a fresh read-only open, quick_check, fk count.
  final clean = await _bounded(() => evidence.fileIsClean(snapshot), probeTimeout);
  if (clean != true) return OpenFailureKind.other;
  // E4: the file is equal to the snapshot.
  final after = await _bounded(evidence.takeSnapshot, probeTimeout);
  if (after == null || after != snapshot) return OpenFailureKind.other;
  return OpenFailureKind.rolledBackUpgrade;
}
