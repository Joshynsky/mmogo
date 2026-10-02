import 'package:flutter/material.dart';

import '../../../data/prefs/update_prefs.dart';
import '../../../data/updates/updates_inbox.dart';
import '../../copy/data_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_format.dart';
import 'settings_widgets.dart';

/// Settings "Updates and feedback" group. One "Updates" row opens the Updates
/// page, where the switch, "Check for updates now" and "Last checked" live
/// (PM, B28 redefined). The row's subtitle says whether checking is on and
/// when it last worked, or that a new version is out; a red dot shows while
/// any notice is unread. It re-reads when the Updates page is closed.
/// Send feedback arrives with B33.
class UpdatesSection extends StatefulWidget {
  const UpdatesSection({super.key, required this.palette, this.inbox});

  final AppPalette palette;

  /// Test seam (defaults to the app's inbox).
  final UpdatesInbox? inbox;

  @override
  State<UpdatesSection> createState() => _UpdatesSectionState();
}

class _UpdatesSectionState extends State<UpdatesSection> {
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
    final newVersion = _inbox.notices.any((n) => !n.read && !n.welcome);
    if (newVersion) return kSettingsUpdatesNewVersion;
    if (!_enabled) return kSettingsUpdatesOff;
    final last = _lastChecked;
    return settingsUpdatesOn(last == null ? null : formatBackupDay(last));
  }

  Future<void> _open() async {
    await Navigator.of(context).pushNamed(Routes.updates);
    if (mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel('Updates and feedback', palette: palette),
        SettingsCard(
          palette: palette,
          child: SettingsLink(
            palette: palette,
            icon: Icons.notifications_none_rounded,
            label: kUpdatesTitle,
            subtitle: _subtitle,
            first: true,
            unreadDot: _inbox.unreadCount.value > 0,
            onTap: _open,
          ),
        ),
      ],
    );
  }
}
