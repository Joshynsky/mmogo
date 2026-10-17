import 'package:flutter/material.dart';

import '../../../data/backup/backup_counts.dart';
import '../../../data/backup/backup_service.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';
import 'backup_format.dart';
import 'backup_shared_sheet.dart';
import 'backup_widgets.dart';

/// The cards of the Backup page, in the order [BackupScreen] stacks them
/// (S10b, BP2; F3 order from the approved mock backup-help.html): the header
/// (why back up, W3, last backup line), Back up now, then (in the screen)
/// Auto-backup, Restore (with the D7 line above its button), and the Privacy
/// link. The phone-to-phone sentence is in the page's "?" sheet only.
/// All stateless: [BackupScreen] owns the state.

/// "Your data lives only on this phone", W3 (uninstall erases your data; stays
/// visible, F3) and the last backup line.
class BackupHeaderCard extends StatelessWidget {
  const BackupHeaderCard({super.key, required this.palette, required this.lastManual, this.lastAuto});

  final AppPalette palette;
  final DateTime? lastManual;

  /// The last automatic backup, shown after the manual one (null unless
  /// auto-backup is on, has a folder and is not paused).
  final DateTime? lastAuto;

  @override
  Widget build(BuildContext context) {
    return BackupCard(
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
        Text(
          lastBackupLine(lastManual, auto: lastAuto),
          key: const Key('backupLastLine'),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.mutedInk),
        ),
      ],
    );
  }
}

/// The Back up now card: counts, the short not-encrypted line (F3: the ONLY
/// place the warning is on this page), the button, the short not-shared line,
/// and the left-out note kept from the last backup.
class BackUpNowCard extends StatelessWidget {
  const BackUpNowCard({
    super.key,
    required this.palette,
    required this.counts,
    required this.countsFailed,
    required this.busy,
    required this.notSharedText,
    required this.leftOut,
    required this.onBackUp,
    required this.onRetry,
  });

  final AppPalette palette;

  /// Null while loading (or when [countsFailed]).
  final BackupCounts? counts;
  final bool countsFailed;

  /// A backup is being prepared.
  final bool busy;

  /// "The share sheet was closed. No backup was saved." or null.
  final String? notSharedText;

  /// The last shared backup, when rows were left out of it (A3); kept until
  /// the next Back up now.
  final BackupExport? leftOut;
  final VoidCallback onBackUp;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = counts;
    final empty = c != null && c.isEmpty;
    return BackupCard(
      palette: palette,
      children: [
        Text(
          'BACK UP NOW',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 8),
        ..._summary(c, empty),
        BackupWarning(
          key: const Key('backupNotEncrypted'),
          palette: palette,
          text: kBackupNotEncryptedShort,
          stripe: false,
        ),
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
        if (notSharedText != null && !busy)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                notSharedText!,
                key: const Key('backupResult'),
                style: TextStyle(fontSize: 13, height: 1.5, color: palette.ink),
              ),
            ),
          ),
        if (leftOut != null && !busy)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: BackupLeftOutNote(key: ValueKey(leftOut), palette: palette, export: leftOut!),
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
          child: TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(minimumSize: const Size(kMinTapTarget, kMinTapTarget)),
            child: const Text('Retry'),
          ),
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
        '${_n(c.userClassifications, 'category you made', 'categories you made')}, '
        '${_n(c.receivers, 'saved receiver', 'saved receivers')} and your settings.',
        palette: palette,
        key: const Key('backupCountsLine'),
      ),
      if (c.deletedLeftOut > 0)
        BackupPara(notIncludedLine(c.deletedLeftOut), palette: palette, key: const Key('backupNotIncluded')),
    ];
  }

  static String _n(int n, String one, String many) => '$n ${n == 1 ? one : many}';
}

/// The Restore card: the D7 line directly above the button (F3, from the
/// mock), the button, then one line.
class RestoreCard extends StatelessWidget {
  const RestoreCard({
    super.key,
    required this.palette,
    required this.busy,
    required this.restoring,
    required this.onRestore,
  });

  final AppPalette palette;
  final bool busy;

  /// The Restore flow is running (the button is off so it cannot start twice).
  final bool restoring;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return BackupCard(
      palette: palette,
      children: [
        Text(
          'RESTORE',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.4, color: palette.mutedInk),
        ),
        const SizedBox(height: 8),
        Container(
          key: const Key('backupD7Line'),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(12)),
          child: Text(
            kBackupNotRestorableByOlder,
            style: TextStyle(fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w600, color: palette.tintInk),
          ),
        ),
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
        const SizedBox(height: 9),
        BackupPara(kRestoreIntro, palette: palette, bottom: 0),
      ],
    );
  }
}
