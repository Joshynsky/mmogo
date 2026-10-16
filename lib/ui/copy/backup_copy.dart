/// §COPY.BACKUP_S10B — the words of the 0.1.2 S10b Backup and restore screens
/// (Backup shared sheet, the "not included" lists, the Replace warning /
/// confirm / progress / result sheets, the leftover and old-folder sheet).
///
/// Every sentence marked PLACEHOLDER is wording the PM may change; they are
/// listed in `_pipeline/v0.1.2/baseline/s10b-deviations.md`. Rules (A8):
/// phone-side texts say "lost" or "not kept in the safety copy", never
/// "skipped"; "categories", never "classifications"; dates are dd-mm-yyyy; no
/// name, amount, phone number, code or URI ever goes into any of these.
library;

String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String _two(int n) => n.toString().padLeft(2, '0');

/// `03-09-2026` (A8: dates in the lists and the leftover range).
String backupDmy(DateTime d) => '${_two(d.day)}-${_two(d.month)}-${d.year}';

// --- Backup page and the Backup shared sheet (BP2, A3) ----------------------

const kBackupSharedTitle = 'Backup shared';

/// The only claim the sheet makes about where the file went (mandated).
const kBackupFilesApp = 'mmogo cannot see where you saved it. Check your Files app.';

const kBackupNotSharedLine = 'The share sheet was closed. No backup was saved.';

String backupSharedCountsLine(int transactions, int categories, int receivers) =>
    '${_n(transactions, 'transaction', 'transactions')}, '
    '${_n(categories, 'category', 'categories')} and '
    '${_n(receivers, 'saved receiver', 'saved receivers')} went to the share sheet.';

/// "N entries could not be made valid and were left out of the backup. ..."
/// [allEntries] false (a category or saved receiver was left out too) says
/// "items".
String backupLeftOutLine(int n, {required bool allEntries}) {
  final what = allEntries ? (n == 1 ? 'entry' : 'entries') : (n == 1 ? 'item' : 'items');
  return '$n $what could not be made valid and ${n == 1 ? 'was' : 'were'} left out of the backup. '
      'Your data on this phone was not changed.';
}

/// P-Backup-28: rows kept but tidied in the copy.
String backupTidiedLine(int n) =>
    '${_n(n, 'entry was', 'entries were')} tidied in the backup copy '
    '(stray characters, extra spaces or very long text). Your data on this phone was not changed.';

const kShowWhich = 'Show which';
const kHideList = 'Hide the list';
const kShowAll = 'Show all';
const kDone = 'Done';

// --- the described-rows lists (A3 / BP1 / A2c) ------------------------------

String notIncludedTitle(int n) => 'Not included in this backup ($n)';
String lostWarningListTitle(int n) => 'Entries that will be lost ($n)';
String lostResultListTitle(int n) => 'Entries that were lost ($n)';
const kStillInApp = 'These entries are still in the app.';
const kOnlyDateAndType = 'Only the date and type are shown.';
const kShowingFirst20 = 'Showing the first 20.';
String moreNotShown(int m) => 'and $m more not shown';

const kRowUnreadableEntry = 'An entry that could not be read';
const kRowCategory = 'A category';
const kRowSavedReceiver = 'A saved receiver';

// Reasons (PM placeholders; the cascaded one is the S10b choice).
const kReasonMissingDetail = 'a required detail is missing';
const kReasonNotAllowed = 'a value is not allowed';
const kReasonCouldNotRead = 'it could not be read';
const kReasonCascaded = 'it belonged to a category that was left out';

// --- the Replace warning (A2, RS1) ------------------------------------------

const kLostWarningTitle = 'Some entries will be lost';

/// [allEntries] false says "items".
String lostWarningBody(int n, {required bool allEntries}) {
  final what = allEntries ? (n == 1 ? 'entry' : 'entries') : (n == 1 ? 'item' : 'items');
  final they = n == 1 ? 'it' : 'they';
  return 'Replace swaps everything on this phone for what is in the file. '
      '$n $what on this phone cannot be kept in the safety copy because ${n == 1 ? 'it breaks' : 'they break'} '
      "the app's rules. If you continue, $they ${n == 1 ? 'is' : 'are'} lost for good. "
      'Undo cannot bring ${n == 1 ? 'it' : 'them'} back.';
}

const kLostTickLabel = 'I understand they cannot be recovered';
const kContinue = 'Continue';
const kCancel = 'Cancel';

/// PLACEHOLDER (A9c): shown on the warning after the count changed.
const kChangedWhileChecking = 'This changed while you were checking. Please look again.';

/// A9a: the non-dismissible "Checking" sheet while the full export runs.
const kReplaceChecking = 'Checking what would be lost...';

// --- the Replace confirm (CB8, F3) ------------------------------------------

String keptAndLostSentence({required int live, required int included, required int lost}) =>
    'Of the ${_n(live, 'transaction', 'transactions')} on this phone, $included go into the safety copy '
    'and $lost ${lost == 1 ? 'is' : 'are'} lost for good ($included + $lost = $live).';

String lostForGoodLine(int n, String what) => '$n $what ${n == 1 ? 'is' : 'are'} lost for good.';
const kUndoRestoresRest = 'Undo restores everything else.';

/// `3 transactions, 1 category you made, 2 saved receivers` (the Replace
/// confirm; "category", never "classification").
String replaceCountsLine(int transactions, int categories, int receivers) =>
    '${_n(transactions, 'transaction', 'transactions')}, '
    '${_n(categories, 'category', 'categories')}, '
    '${_n(receivers, 'saved receiver', 'saved receivers')}';

const kReplaceSafetyCopyFailed = 'Could not save a safety copy, so nothing was replaced.';

// --- progress (BP2, A10) ----------------------------------------------------

/// The progress sheet's title for a Replace (names the route).
const kReplaceProgressTitle = 'Replacing from the backup';
const kStepValidating = 'Checking the file';
const kStepSafetyCopy = 'Saving a safety copy';
const kStepWriting = 'Replacing your data';

/// PLACEHOLDER (mock text): shown when a `slow` step event arrives.
const kRestoreSlow = 'This is taking longer than usual. Keep mmogo open.';

// --- the Replace result (A9d) -----------------------------------------------

String replaceRestoredLine(int restored, int lost) =>
    '${_n(restored, 'entry', 'entries')} restored.${lost > 0 ? ' $lost lost.' : ''}';

/// PLACEHOLDER: the Replace result's Undo line when rows were lost.
String replaceUndoLostNote(int n) =>
    'Undo brings back everything except ${n == 1 ? 'that entry' : 'those $n entries'}.';

/// A14 (CB13): the fixed labels of the settings a restore applied. Never a value.
const Map<String, String> kRestoredSettingLabels = {
  'user_display_name': 'Display name',
  'palette_id': 'Colour palette',
  'auto_recognize_classifications': 'Auto-recognise categories',
  'capture_identity_preference': 'Capture identity',
  'auto_backup_every_n': 'Auto-backup: every N entries',
  'auto_backup_keep_k': 'Auto-backup: files to keep',
  'first_day_of_week': 'First day of the week',
  'month_chart_style': 'Month chart style',
  'year_view_amounts': 'Year view',
  'show_withdrawals_in_chart': 'Withdrawals in the chart',
  'where_it_went_style': 'Where it went style',
};

String settingsRestoredLine(List<String> labels) => 'Settings restored: ${labels.join(', ')}.';

// --- leftover files and the old folder (LF1, CB9, A4) ------------------------

const kLeftoverTitle = 'Old automatic backups found';
const kLeftoverCountedNote = 'Only files named mmogo-auto-... are counted.';

String leftoverBody(int n, DateTime? oldest, DateTime? newest) {
  final what = n == 1 ? '1 automatic backup file' : '$n automatic backup files';
  String range = '';
  if (oldest != null && newest != null) {
    final a = backupDmy(oldest);
    final b = backupDmy(newest);
    range = n == 1 || a == b ? ' from $b' : ' from $a to $b';
  }
  final them = n == 1 ? 'it' : 'them';
  return 'We found $what$range in the old folder. Keep $them, or delete $them? '
      'Your own manual backups are never touched.';
}

String leftoverKeepLabel(int n) => n == 1 ? 'Keep it' : 'Keep them';
String leftoverDeleteLabel(int n) => 'Delete ${_n(n, 'file', 'files')}';
String leftoverContinueKeep(int n) => 'Keep ${_n(n, 'file', 'files')}';
const kLeftoverWhatToDo = 'What to do with the old files';

const kOldFolderTitle = 'Stop using the old folder?';
const kOldFolderBody =
    'mmogo now saves backups in the new folder only. If you stop using the old one, mmogo gives up its '
    'permission to it. Files in it stay where they are.';
const kStopUsingIt = 'Stop using it';
const kKeepAccess = 'Keep access';
const kKeepAccessHint = 'Keep access: mmogo can still reach the old folder, but saves no new backups there.';
const kOldFolderGroup = 'Old folder permission';

/// Toasts (A11). Nothing when the listing failed.
String keptToast(int n) => 'Kept ${_n(n, 'file', 'files')}.';
String deletedToast(int n) => 'Deleted ${_n(n, 'file', 'files')}.';
String deletedPartlyToast(int deleted, int failed) => 'Deleted $deleted. $failed could not be deleted.';

const kFolderWorking = 'Working...';
