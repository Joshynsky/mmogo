import 'package:flutter/material.dart';

import '../../../data/backup/backup_counts.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'backup_format.dart';
import 'backup_widgets.dart';

/// The two cards at the top of the Backup page: why back up (with the last
/// backup line) and "Back up now". Stateless: [BackupScreen] owns the state.
/// The Restore button, the Auto-backup card and the Privacy row are added by
/// later tasks (B17, B21, B32).
class BackupSection extends StatelessWidget {
  const BackupSection({
    super.key,
    required this.palette,
    required this.counts,
    required this.countsFailed,
    required this.lastManual,
    required this.busy,
    required this.resultText,
    required this.onBackUp,
    required this.onRetry,
    required this.onRestore,
    this.restoring = false,
    this.lastAuto,
  });

  /// The last automatic backup, shown after the manual one (null unless
  /// auto-backup is on, has a folder and is not paused).
  final DateTime? lastAuto;

  final AppPalette palette;

  /// Null while loading (or when [countsFailed]).
  final BackupCounts? counts;
  final bool countsFailed;
  final DateTime? lastManual;

  /// A backup is being prepared.
  final bool busy;

  /// What the last successful run reported; null before any run.
  final String? resultText;
  final VoidCallback onBackUp;
  final VoidCallback onRetry;

  /// Starts the Restore flow (B17).
  final VoidCallback onRestore;

  /// The Restore flow is running (the button is off so it cannot start twice).
  final bool restoring;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final empty = c != null && c.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BackupCard(
          palette: palette,
          children: [
            Row(
              children: [
                Icon(Icons.save_alt_rounded, size: 22, color: palette.tintInk),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your data lives only on this phone',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3, color: palette.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BackupPara(kUninstallErasesNotice, palette: palette),
            BackupPara(kPhoneTransferNotice, palette: palette),
            Text(
              lastBackupLine(lastManual, auto: lastAuto),
              key: const Key('backupLastLine'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.mutedInk),
            ),
          ],
        ),
        const SizedBox(height: 14),
        BackupCard(
          palette: palette,
          children: [
            Text(
              'BACK UP NOW',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: palette.mutedInk,
              ),
            ),
            const SizedBox(height: 8),
            ..._summary(c, empty),
            BackupWarning(palette: palette, text: kBackupFileWarning),
            FilledButton(
              key: const Key('backUpNowButton'),
              onPressed: (empty || busy) ? null : onBackUp,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: palette.primary,
                foregroundColor: palette.onPrimary,
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child: Text(busy ? 'Preparing your backup...' : 'Back up now'),
            ),
            if (busy)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(key: const Key('backupProgress'), color: palette.primary),
              ),
            if (resultText != null && !busy)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    resultText!,
                    key: const Key('backupResult'),
                    style: TextStyle(fontSize: 13, height: 1.5, color: palette.ink),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        BackupCard(
          palette: palette,
          children: [
            Text(
              'RESTORE',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: palette.mutedInk,
              ),
            ),
            const SizedBox(height: 8),
            BackupPara(kRestoreIntro, palette: palette),
            OutlinedButton(
              key: const Key('restoreButton'),
              onPressed: (busy || restoring) ? null : onRestore,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: palette.primary,
                side: BorderSide(color: palette.primary, width: 1.5),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              child: const Text(kRestoreButtonLabel),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _summary(BackupCounts? c, bool empty) {
    if (countsFailed) {
      return [
        BackupPara('Could not read your data.', palette: palette, bold: true, bottom: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetry, child: const Text('Retry')),
        ),
      ];
    }
    if (c == null) return [BackupPara('Reading your data...', palette: palette)];
    if (empty) {
      return [
        BackupPara(
          'Nothing to back up yet. Add a transaction first. You can still restore a backup from another phone.',
          palette: palette,
          bold: true,
        ),
      ];
    }
    return [
      BackupPara(
        'A backup holds your ${_n(c.transactions, 'transaction', 'transactions')}, '
        '${_n(c.userClassifications, 'classification you made', 'classifications you made')}, '
        '${_n(c.receivers, 'saved receiver', 'saved receivers')} and your settings, in one file.',
        palette: palette,
        key: const Key('backupCountsLine'),
      ),
      if (c.deletedLeftOut > 0)
        BackupPara(notIncludedLine(c.deletedLeftOut), palette: palette, key: const Key('backupNotIncluded')),
    ];
  }

  static String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';
}
