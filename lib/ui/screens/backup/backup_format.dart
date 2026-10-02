/// Plain-words text for the Backup page and the Settings row. No row values
/// ever go into these strings, only counts and dates.
library;

import '../../../data/backup/backup_service.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `25 Sep 2026, 09:14` from the local fields of [when].
String formatBackupTime(DateTime when) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${when.day} ${_months[when.month - 1]} ${when.year}, ${two(when.hour)}:${two(when.minute)}';
}

/// `25 Sep 2026` (the Settings row subtitle).
String formatBackupDay(DateTime when) => '${when.day} ${_months[when.month - 1]} ${when.year}';

/// The "Last backup" line on the Backup page.
String lastBackupLine(DateTime? manual) =>
    manual == null ? 'Never backed up' : 'Last backup (manual): ${formatBackupTime(manual)}';

/// The Settings row subtitle: `Never backed up` or `Last backup 25 Sep 2026`.
String backupRowSubtitle(DateTime? lastBackup) =>
    lastBackup == null ? 'Never backed up' : 'Last backup ${formatBackupDay(lastBackup)}';

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// What the user is told after a backup was handed to the share sheet. Reports
/// repaired and skipped counts only when they are not zero.
String backupResultMessage(BackupExport e) {
  final parts = <String>[
    'Backup ready: ${_n(e.transactions, 'transaction', 'transactions')}, '
        '${_n(e.classifications, 'classification', 'classifications')} and '
        '${_n(e.counterpartyMap, 'saved receiver', 'saved receivers')} '
        'went to the share sheet. Check that you saved it where you meant to.',
  ];
  if (e.repairedCount > 0) {
    parts.add(
      '${_n(e.repairedCount, 'entry was', 'entries were')} tidied in the backup copy '
      '(stray characters, extra spaces or very long text). Your data on this phone was not changed.',
    );
  }
  if (e.skippedCount > 0) {
    parts.add(
      '${_n(e.skippedCount, 'entry', 'entries')} could not be made valid and '
      '${e.skippedCount == 1 ? 'was' : 'were'} left out of the backup. Your data on this phone was not changed.',
    );
  }
  return parts.join(' ');
}

const kBackupFailedMessage = 'Could not create the backup. Nothing was shared.';

/// The line under "Back up now" about recently deleted transactions.
String notIncludedLine(int deleted) => deleted == 1
    ? '1 recently deleted transaction is not included. Restore it first if you want it in the backup.'
    : '$deleted recently deleted transactions are not included. Restore them first if you want them in the backup.';
