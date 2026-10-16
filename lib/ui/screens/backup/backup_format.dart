/// Plain-words text for the Backup page and the Settings row. No row values
/// ever go into these strings, only counts and dates.
library;

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// `25 Sep 2026, 09:14` from the local fields of [when].
String formatBackupTime(DateTime when) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${when.day} ${_months[when.month - 1]} ${when.year}, ${two(when.hour)}:${two(when.minute)}';
}

/// `25 Sep 2026` (the Settings row subtitle).
String formatBackupDay(DateTime when) => '${when.day} ${_months[when.month - 1]} ${when.year}';

/// The "Last backup" line on the Backup page: the manual backup, then the
/// last automatic one when [auto] is given (the page passes it only while
/// auto-backup is on, has a folder and is not paused).
String lastBackupLine(DateTime? manual, {DateTime? auto}) {
  final parts = [
    if (manual != null) 'Last backup (manual): ${formatBackupTime(manual)}',
    if (auto != null) 'Last auto-backup: ${formatBackupTime(auto)}',
  ];
  return parts.isEmpty ? 'Never backed up' : parts.join(' · ');
}

/// The Settings row subtitle: `Never backed up` or `Last backup 25 Sep 2026`.
String backupRowSubtitle(DateTime? lastBackup) =>
    lastBackup == null ? 'Never backed up' : 'Last backup ${formatBackupDay(lastBackup)}';

const kBackupFailedMessage = 'Could not create the backup. Nothing was shared.';

/// The line under "Back up now" about recently deleted transactions.
String notIncludedLine(int deleted) => deleted == 1
    ? '1 recently deleted transaction is not included. Restore it first if you want it in the backup.'
    : '$deleted recently deleted transactions are not included. Restore them first if you want them in the backup.';
