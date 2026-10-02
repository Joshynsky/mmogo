/// Plain-language text for the Restore flow. Nothing here ever includes a value
/// taken from the file: only counts, dates, and names this app owns.
library;

import '../../../data/backup/backup_limits.dart';
import '../../../data/backup/restore_types.dart';
import '../../../data/backup/restore_service.dart' show RestoreRejected, RestoreRejectReason;
import '../../copy/data_copy.dart';
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
  'classifications': 'classifications',
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

/// `187 transactions, 2 classifications, 15 saved receivers`.
String restoreCountsLine(int transactions, int classifications, int receivers) =>
    '${_n(transactions, 'transaction', 'transactions')}, '
    '${_n(classifications, 'classification', 'classifications')}, '
    '${_n(receivers, 'saved receiver', 'saved receivers')}';

/// `20 Sep 2026, 10:15` from the file's epoch-millisecond creation time.
String restoreFileDate(int epochMs) => formatBackupTime(DateTime.fromMillisecondsSinceEpoch(epochMs));

/// The user-visible text of a [RestoreFailed]. Replace refused for an
/// incomplete safety copy is the only case that differs from the one message.
String restoreFailedText(RestoreFailed e) =>
    e.reason == RestoreFailReason.safetyCopyIncomplete ? kReplaceNeedsCompleteCopy : kRestoreFailedMessage;
