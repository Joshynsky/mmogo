import 'package:flutter/material.dart';

import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// Settings "Your data" section: Manage classifications, Recently deleted,
/// Export CSV, Backup and restore (B14). State (export subtitle/enabled, handler) is owned by the
/// Settings shell; [tourKey] is its coach-tour anchor.
class DataSection extends StatelessWidget {
  const DataSection({
    super.key,
    required this.palette,
    required this.tourKey,
    required this.exportSubtitle,
    required this.exportEnabled,
    required this.onExport,
    this.backupSubtitle = 'Never backed up',
    this.onBackup,
  });

  final AppPalette palette;
  final GlobalKey tourKey;
  final String exportSubtitle;
  final bool exportEnabled;
  final VoidCallback onExport;

  /// `Never backed up` or `Last backup <date>`.
  final String backupSubtitle;

  /// Opens the Backup and restore page (defaults to the named route).
  final VoidCallback? onBackup;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel('Your data', palette: palette),
        KeyedSubtree(
          key: tourKey,
          child: SettingsCard(
            palette: palette,
            child: Column(
              children: [
                SettingsLink(
                  palette: palette,
                  icon: Icons.category_outlined,
                  label: 'Manage classifications',
                  subtitle: 'Create, rename, delete and restore',
                  first: true,
                  onTap: () => Navigator.of(context).pushNamed(Routes.manageClassifications),
                ),
                SettingsLink(
                  palette: palette,
                  icon: Icons.restore_from_trash_outlined,
                  label: 'Recently deleted',
                  subtitle: 'Restore transactions you removed',
                  onTap: () => Navigator.of(context).pushNamed(Routes.recentlyDeleted),
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
                  icon: Icons.backup_outlined,
                  label: 'Backup and restore',
                  subtitle: backupSubtitle,
                  onTap: onBackup ?? () => Navigator.of(context).pushNamed(Routes.backup),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
