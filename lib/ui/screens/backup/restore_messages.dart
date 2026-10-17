/// Plain-language text for the Restore flow. Nothing here ever includes a value
/// taken from the file: only counts, dates, and names this app owns.
library;

import '../../../data/backup/backup_limits.dart';
import '../../../data/backup/restore_types.dart';
import '../../../data/backup/restore_service.dart' show RestoreRejected, RestoreRejectReason;
import '../../copy/backup_copy.dart';
import '../../copy/data_copy.dart';
import '../../copy/delete_data_copy.dart';
import 'backup_format.dart';

/// The reason line the rejection dialog shows for [e].
///
/// For an invalid entry it names the table, the row number and the field, but
/// only when they match this app's own fixed names; anything else (a key that
/// came from the file) is left out, so hostile text can never reach the screen.
String restoreRejectReasonText(RestoreRejected e) {
  switch (e.reason) {
    case RestoreRejectReason.notMmogo:
      return kRejectNotMmogo;
    case RestoreRejectReason.newer:
      return kRejectNewer;
    case RestoreRejectReason.corrupt:
      return kRejectDamaged;
    case RestoreRejectReason.tooLarge:
    case RestoreRejectReason.tooMany:
      return kRejectTooLarge;
    case RestoreRejectReason.invalidRow:
    case RestoreRejectReason.danglingRef:
      return _invalidEntryText(e);
  }
}

const _tableNames = {
  'classifications': 'categories',
  'transactions': 'transactions',
  'counterparty_map': 'saved receivers',
  'prefs': 'settings',
};

String _invalidEntryText(RestoreRejected e) {
  final table = _tableNames[e.table];
  final field = _knownField(e.table, e.field);
  final row = e.rowIndex;
  final parts = <String>[
    ?table,
    if (row != null && row >= 0) 'row ${row + 1}',
    ?field,
  ];
  return parts.isEmpty ? '$kRejectInvalidEntry.' : '$kRejectInvalidEntry (${parts.join(', ')}).';
}

String? _knownField(String? table, String? field) {
  if (field == null) return null;
  final known = switch (table) {
    'classifications' => kBackupClassificationKeys,
    'transactions' => kBackupTransactionKeys,
    'counterparty_map' => kBackupMapKeys,
    _ => const <String>[],
  };
  return known.contains(field) ? field : null;
}

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// `187 transactions, 2 categories, 15 saved receivers` (F3, R44: the word is
/// "categories"; the file's JSON key "classifications" is not touched).
String restoreCountsLine(int transactions, int categories, int receivers) =>
    '${_n(transactions, 'transaction', 'transactions')}, '
    '${_n(categories, 'category', 'categories')}, '
    '${_n(receivers, 'saved receiver', 'saved receivers')}';

/// `20 Sep 2026, 10:15` from the file's epoch-millisecond creation time.
String restoreFileDate(int epochMs) => formatBackupTime(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// The user-visible text of a [RestoreFailed] outside the Replace confirm
/// (Merge, Undo): busy and "this changed" have their own texts, everything
/// else is the one message. `safetyCopyIncomplete` is no longer thrown (S10a)
/// and has no text.
String restoreFailedText(RestoreFailed e) => switch (e.reason) {
      RestoreFailReason.busy => kDataOpBusy,
      RestoreFailReason.skippedChanged => kChangedWhileChecking,
      _ => kRestoreFailedMessage,
    };

/// The text in the red box inside the Replace confirm (mock M3, A9f): the
/// safety copy could not be saved, another change is running, or the one
/// message. ("This changed" is not a failure: the flow shows the preview again.)
String replaceFailedText(Object error) {
  if (error is RestoreFailed) {
    return switch (error.reason) {
      RestoreFailReason.safetyCopyFailed => kReplaceSafetyCopyFailed,
      RestoreFailReason.busy => kDataOpBusy,
      _ => kRestoreFailedMessage,
    };
  }
  return kRestoreFailedMessage;
}
