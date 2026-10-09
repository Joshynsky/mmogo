import 'package:flutter/material.dart';

import '../../copy/data_copy.dart';
import '../../copy/privacy_copy.dart';
import '../../shell/routes.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_widgets.dart';
import '../settings/settings_widgets.dart';

/// B32: Settings > Privacy and security > Privacy and your data. Static text
/// only (no data read, no network): what is stored on the phone, what leaves
/// it, the backup-file warning (W1), the cloud-sync warning (W2) and a link
/// row to Backup and restore. All wording is in `ui/copy/`.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: kPrivacyTitle,
      followPalette: true,
      body: ListView(
        key: const Key('privacyScroll'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
            child: Text(
              kPrivacySentenceStandard,
              key: const Key('privacySentenceStandard'),
              style: TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w800, color: palette.ink),
            ),
          ),
          _Section(
            palette: palette,
            icon: Icons.folder_outlined,
            title: kPrivacyStoredTitle,
            children: [
              _Para(palette, kPrivacyStoredBody),
              _Para(palette, kPrivacyStoredReceiverDetails),
              _Para(palette, kPrivacyStoredAgentNumber),
              _Para(palette, kPrivacyStoredRememberedAnswers),
              _Para(palette, '$kUninstallErasesNotice $kPhoneTransferNotice'),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.cloud_outlined,
            title: kPrivacyLeavesTitle,
            children: [
              _Para(palette, kNetworkDisclosure),
              _Para(palette, kPrivacyLeavesBody),
              _Para(palette, kPrivacyCheckNowOnce, bold: true),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.description_outlined,
            title: kPrivacyBackupFilesTitle,
            children: [
              _Para(palette, kPrivacyBackupFilesBody),
              BackupWarning(palette: palette, text: kBackupFileWarning, bottomGap: 0),
            ],
          ),
          _Section(
            palette: palette,
            icon: Icons.sync_problem_outlined,
            title: kPrivacyCloudTitle,
            children: [_Para(palette, kCloudSyncNotice)],
          ),
          SettingsCard(
            palette: palette,
            child: SettingsLink(
              palette: palette,
              icon: Icons.backup_outlined,
              label: kPrivacyBackupRowTitle,
              subtitle: kPrivacyBackupRowSubtitle,
              first: true,
              onTap: () => Navigator.of(context).pushNamed(Routes.backup),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 2, 0),
            child: BackupCard(palette: palette, children: [_Para(palette, kIndependenceFull, key: const Key('privacyIndependence'))]),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.palette, required this.icon, required this.title, required this.children});

  final AppPalette palette;
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: BackupCard(
        palette: palette,
        children: [
          Row(
            children: [
              SettingsRowIcon(icon: icon, palette: palette),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.ink)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Para extends StatelessWidget {
  const _Para(this.palette, this.text, {this.bold = false, super.key});

  final AppPalette palette;
  final String text;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: palette.ink,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      ),
    ),
  );
}
