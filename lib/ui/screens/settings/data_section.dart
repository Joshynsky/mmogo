import 'package:flutter/material.dart';

import '../../../data/maintenance/delete_data_service.dart';
import '../../copy/settings_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_export_flow.dart';
import 'delete_data_row.dart';
import 'settings_widgets.dart';

/// Settings "Your data, careful" section (0.1.2 S9a, mock M9): Backup and
/// restore, Export CSV, Recently deleted, then Delete data last (F4 R19: by
/// purpose, getting data out before removing it; Manage categories moved to
/// Adding entries). ST1. State (export subtitle/enabled, handler) is owned by the
/// Settings shell; [tourKey] is its coach-tour anchor.
class DataSection extends StatelessWidget {
  const DataSection({
    super.key,
    required this.palette,
    this.tourKey,
    required this.exportSubtitle,
    required this.exportEnabled,
    required this.onExport,
    this.backupSubtitle = 'Never backed up',
    this.onBackup,
    this.backupPaused = false,
    this.deleteData,
    this.restart,
    this.backupFlow,
  });

  final AppPalette palette;
  final GlobalKey? tourKey;
  final String exportSubtitle;
  final bool exportEnabled;
  final VoidCallback onExport;

  /// `Never backed up` or `Last backup <date>`.
  final String backupSubtitle;

  /// Opens the Backup and restore page (defaults to the named route).
  final VoidCallback? onBackup;

  /// Auto-backup is paused: the row shows a warning dot.
  final bool backupPaused;

  /// Delete data seams (A1, A2, A9). Null = the real service (the one
  /// factory), the real soft restart and the real Back up now flow.
  final DeleteDataService? deleteData;
  final Future<bool> Function(BuildContext)? restart;
  final BackupExportFlow? backupFlow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSettingsDataGroup, palette: palette, tag: kSettingsCarefulTag),
        KeyedSubtree(
          key: tourKey,
          child: SettingsCard(
            palette: palette,
            child: Column(
              children: [
                SettingsLink(
                  palette: palette,
                  icon: Icons.backup_outlined,
                  label: 'Backup and restore',
                  subtitle: backupSubtitle,
                  first: true,
                  warningDot: backupPaused,
                  onTap: onBackup ?? () => Navigator.of(context).pushNamed(Routes.backup),
                ),
                SettingsLink(
                  palette: palette,
                  icon: Icons.ios_share,
                  label: 'Export CSV',
                  subtitle: exportSubtitle,
                  onTap: exportEnabled ? onExport : null,
                ),
                SettingsLink(
                  palette: palette,
                  icon: Icons.restore_from_trash_outlined,
                  label: 'Recently deleted',
                  subtitle: 'Restore transactions you removed',
                  onTap: () => Navigator.of(context).pushNamed(Routes.recentlyDeleted),
                ),
                // S9b-2: the Delete data row is the LAST row of the card.
                DeleteDataRow(palette: palette, deleteData: deleteData, restart: restart, backupFlow: backupFlow),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
