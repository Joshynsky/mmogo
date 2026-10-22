import 'package:flutter/material.dart';

import '../../../data/prefs/update_prefs.dart';
import '../../../data/updates/updates_inbox.dart';
import '../../../app_constants.dart';
import '../../../platform/storage_bridge.dart';
import '../../../autoread/autoread_feature.dart' show kAutoReadCompiled;
import '../../copy/data_copy.dart';
import '../../copy/other_version_copy.dart';
import '../../copy/privacy_copy.dart';
import '../../copy/settings_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_format.dart';
import 'settings_widgets.dart';

/// Settings ABOUT card (0.1.2 S9a, mock M9: Privacy and your data, Updates, Send
/// feedback, in one card; was the "Privacy and security" group and the
/// "Updates and feedback" group). One "Updates" row opens the Updates
/// page, where the switch, "Check for updates now" and "Last checked" live
/// (PM, B28 redefined). The row's subtitle says whether checking is on and
/// when it last worked, or that a new version is out; a red dot shows while
/// any notice is unread. It re-reads when the Updates page is closed.
/// "Send feedback" (B33) opens the GitHub issues page in the browser.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, required this.palette, this.inbox, this.otherVersionRow = !kAutoReadCompiled});

  final AppPalette palette;

  /// Test seam (defaults to the app's inbox).
  final UpdatesInbox? inbox;

  /// The permanent Other version of mmogo row: standard build only (test seam).
  final bool otherVersionRow;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  late final UpdatesInbox _inbox = widget.inbox ?? UpdatesInbox.instance;
  bool _enabled = UpdatePrefs.defaultEnabled;
  DateTime? _lastChecked;

  @override
  void initState() {
    super.initState();
    _inbox.unreadCount.addListener(_onInbox);
    _reload();
  }

  @override
  void dispose() {
    _inbox.unreadCount.removeListener(_onInbox);
    super.dispose();
  }

  void _onInbox() {
    if (mounted) setState(() {});
  }

  Future<void> _reload() async {
    final enabled = await UpdatePrefs.readEnabled();
    final last = await UpdatePrefs.readLastCheckAt();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _lastChecked = last;
    });
  }

  String get _subtitle {
    // The welcome notice is unread too, but it is not "a new version".
    final newVersion = _inbox.notices.any((n) => !n.read && !n.welcome && !n.otherVersion && !n.whatsNew);
    if (newVersion) return kSettingsUpdatesNewVersion;
    if (!_enabled) return kSettingsUpdatesOff;
    final last = _lastChecked;
    return settingsUpdatesOn(last == null ? null : formatBackupDay(last));
  }

  Future<void> _open() async {
    await Navigator.of(context).pushNamed(Routes.updates);
    if (mounted) await _reload();
  }

  /// B33: opens the issues page through the bridge, which only accepts the
  /// [AppConstants] URLs. A refusal or failure shows a short message.
  Future<void> _sendFeedback() async {
    var opened = false;
    try {
      opened = await StorageBridge.instance.openUrl(AppConstants.issuesUrl);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kSendFeedbackCouldNotOpen)));
    }
  }

  /// Opens the mmogo page (a constant) in the browser; the same link as the
  /// Notifications item. A refusal or failure shows a short message.
  Future<void> _otherVersion() async {
    var opened = false;
    try {
      opened = await StorageBridge.instance.openUrl(AppConstants.siteUrl);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kOtherVersionCouldNotOpen)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSettingsAboutGroup, palette: palette),
        SettingsCard(
          palette: palette,
          child: Column(
            children: [
              SettingsLink(
                palette: palette,
                icon: Icons.shield_outlined,
                label: kPrivacyTitle,
                subtitle: kSettingsPrivacySubtitle,
                first: true,
                onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
              ),
              SettingsLink(
                palette: palette,
                icon: Icons.notifications_none_rounded,
                label: kUpdatesTitle,
                subtitle: _subtitle,
                unreadDot: _inbox.unreadCount.value > 0,
                onTap: _open,
              ),
              if (widget.otherVersionRow)
                SettingsLink(
                  palette: palette,
                  icon: Icons.devices_other_rounded,
                  label: kOtherVersionSettingsLabel,
                  subtitle: kOtherVersionSettingsSubtitle,
                  trailingIcon: Icons.open_in_new_rounded,
                  onTap: _otherVersion,
                ),
              SettingsLink(
                palette: palette,
                icon: Icons.chat_bubble_outline_rounded,
                label: kSendFeedbackLabel,
                subtitle: kSendFeedbackSubtitle,
                trailingIcon: Icons.open_in_new_rounded,
                onTap: _sendFeedback,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
