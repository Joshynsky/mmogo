// A FAKE Delete data service for every widget test that can reach Settings
// (0.1.2 S9b-2, A1). The real `DeleteDataServiceImpl` deletes the database and
// the preferences: nothing in test/ may reach it through the app's default.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/settings/delete_data_factory.dart';

/// A peek with something to delete at both levels (invented counts).
const kFakePeekFull = DeleteDataPeek(
  liveTransactions: 12,
  softDeletedTransactions: 2,
  learnedReceivers: 3,
  safetyCopyPresent: true,
  rememberedRecipientsPresent: true,
  rememberedRecipientsCount: 2,
  queuePresent: false,
);

/// Level 1 has nothing left; Level 2 still has (a category or a preference).
const kFakePeekLevel1Empty = DeleteDataPeek(
  liveTransactions: 0,
  softDeletedTransactions: 0,
  learnedReceivers: 0,
  safetyCopyPresent: false,
  rememberedRecipientsPresent: false,
  queuePresent: false,
);

/// Nothing left at either level.
const kFakePeekNothing = DeleteDataPeek(
  liveTransactions: 0,
  softDeletedTransactions: 0,
  learnedReceivers: 0,
  safetyCopyPresent: false,
  rememberedRecipientsPresent: false,
  queuePresent: false,
  nothingLeftAtLevel2: true,
);

const kFakeDone = DeleteDataResult(outcome: DeleteDataOutcome.done, transactionsDeleted: 12);

class FakeDeleteDataService implements DeleteDataService {
  FakeDeleteDataService({this.peekValue = kFakePeekFull});

  DeleteDataPeek peekValue;

  /// When set, peek() throws this (the row must fall back, never crash).
  Object? peekError;

  /// Results handed out in order (the last repeats). Per method.
  List<DeleteDataResult> level1Results = [kFakeDone];
  List<DeleteDataResult> resetResults = [kFakeDone];

  /// When set, the next delete / reset waits for this (the busy state).
  Completer<void>? hold;

  final calls = <String>[];
  int get peekCalls => calls.where((c) => c == 'peek').length;
  int get deleteCalls => calls.where((c) => c == 'deleteMyTransactions').length;
  int get resetCalls => calls.where((c) => c == 'resetApp').length;

  @override
  Future<DeleteDataPeek> peek() async {
    calls.add('peek');
    final e = peekError;
    if (e != null) throw e;
    return peekValue;
  }

  @override
  Future<DeleteDataResult> deleteMyTransactions() async {
    calls.add('deleteMyTransactions');
    await hold?.future;
    return level1Results[(deleteCalls - 1).clamp(0, level1Results.length - 1)];
  }

  @override
  Future<DeleteDataResult> resetApp() async {
    calls.add('resetApp');
    await hold?.future;
    return resetResults[(resetCalls - 1).clamp(0, resetResults.length - 1)];
  }
}

/// A Back up now flow with no export, share or prefs: it returns [outcome].
class FakeBackupFlow extends BackupExportFlow {
  FakeBackupFlow([this.outcome = const BackupNotShared()]);

  BackupOutcome outcome;
  int runs = 0;

  @override
  Future<BackupOutcome> execute() async {
    runs++;
    return outcome;
  }
}

/// Makes the app's default Delete data service a fake for this test (call in
/// `setUp`). Returns the fake so a test can steer it.
FakeDeleteDataService useFakeDeleteData([FakeDeleteDataService? fake]) {
  final f = fake ?? FakeDeleteDataService();
  DeleteDataServices.override = () => f;
  addTearDown(() => DeleteDataServices.override = null);
  return f;
}
