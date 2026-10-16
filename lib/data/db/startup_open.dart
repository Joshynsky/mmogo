import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app_database.dart';
import 'open_classifier.dart';
import 'open_evidence_file.dart';
import 'open_stage.dart';

/// §DATA.DB.STARTUP_OPEN — the real functions `main()` hands to `StartupGate`
/// (0.1.2 S10c). Tests never call these (they use fakes); they are the only
/// place the gate's seams meet `AppDatabase.instance`.

/// The open Home would do anyway; the gate runs it once and Home reuses it.
Future<void> openAppDatabaseForStart() async {
  await AppDatabase.instance.database;
}

/// Bounded close of the cached handle (10 s inside [AppDatabase.close]).
Future<void> closeAppDatabaseForRetry() => AppDatabase.instance.close();

OpenStage readAppOpenStage() => AppDatabase.instance.lastOpenStage;

Future<FileOpenEvidence> _evidence() async =>
    FileOpenEvidence(path: await AppDatabase.instance.databasePath(), factory: databaseFactory);

/// Once per gate run. With [kUpg3ProofOnRecord] false: nothing, no probe.
Future<OpenSnapshot?> prepareAppOpenSnapshot() async {
  if (!kUpg3ProofOnRecord) return null;
  return prepareOpenSnapshot(await _evidence());
}

Future<OpenFailureKind> classifyAppOpenFailure(Object error, OpenStage stage, OpenSnapshot? snapshot) async {
  if (!kUpg3ProofOnRecord) return OpenFailureKind.other;
  return classifyOpenFailure(error: error, stage: stage, snapshot: snapshot, evidence: await _evidence());
}
