import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app_constants.dart';
import '../../../app_info.dart';
import '../../../data/prefs/update_prefs.dart';
import '../../../data/updates/update_check_service.dart';
import '../../../data/updates/updates_inbox.dart';
import '../../../platform/storage_bridge.dart';
import '../../copy/data_copy.dart';
import '../../copy/whats_new_pager_copy.dart';
import '../../shell/routes.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_format.dart';
import '../settings/settings_widgets.dart';
import '../../whats_new/whats_new_entry.dart';
import '../../whats_new/whats_new_pager.dart';
import 'notice_card.dart';

/// The Updates page (B27; it replaced the "Coming soon" notifications page).
/// Top: the update-check switch, "Check for updates now" and "Last checked"
/// (PM design decision: they live here, not in Settings). Below: the notices
/// newest first, or an empty state. Notices are marked read when the page is
/// left, so the bell and Settings dots clear after a visit.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({
    super.key,
    this.inbox,
    this.service,
    this.readSeenVersion,
    this.writeSeenVersion,
    this.installedVersionName,
    this.openSettings,
    this.openBackup,
  });

  /// Test seams (default to the app's singletons).
  final UpdatesInbox? inbox;
  final UpdateCheckService? service;

  /// What's-new entry seams (S11a): the stored seen version, its writer, the
  /// installed version, and the openers of the pager's two buttons.
  final Future<String?> Function()? readSeenVersion;
  final Future<void> Function(String versionName)? writeSeenVersion;
  final String? installedVersionName;
  final VoidCallback? openSettings;
  final VoidCallback? openBackup;

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
  late final UpdatesInbox _inbox = widget.inbox ?? UpdatesInbox.instance;
  late final UpdateCheckService _service = widget.service ?? UpdateCheckService.instance;

  bool _enabled = UpdatePrefs.defaultEnabled;
  DateTime? _lastChecked;
  bool _checking = false;
  String? _checkMessage;

  /// The stored What's-new seen version; the NEW pill waits until it is read.
  String? _seen;
  bool _seenLoaded = false;

  @override
  void initState() {
    super.initState();
    _inbox.unreadCount.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _inbox.unreadCount.removeListener(_refresh);
    // Leaving the page clears the entry's NEW pill for this process (S11a).
    WhatsNewProcess.pillCleared = true;
    // Leaving the page is what marks the notices read (the "New" markers stay
    // visible for the whole visit).
    unawaited(_inbox.markAllRead());
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final enabled = await UpdatePrefs.readEnabled();
    final last = await UpdatePrefs.readLastCheckAt();
    String? seen;
    try {
      seen = await (widget.readSeenVersion ?? UpdatePrefs.readWhatsNewSeenVersion)();
    } catch (_) {}
    await _inbox.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _lastChecked = last;
      _seen = seen;
      _seenLoaded = true;
    });
  }

  /// The NEW pill: while the stored version is not the pager's version and it
  /// was not cleared in this process. No key of its own.
  bool get _showNew => _seenLoaded && !WhatsNewProcess.pillCleared && _seen != kWhatsNewPagerVersion;

  Future<void> _openPager() async {
    final installed = widget.installedVersionName ?? AppInfo.versionName;
    final gotIt = await showWhatsNewPager(
      context,
      onOpenSettings: widget.openSettings ?? () => Navigator.of(context).pushNamed(Routes.settings),
      onOpenBackup: widget.openBackup ?? () => Navigator.of(context).pushNamed(Routes.backup),
    );
    if (!gotIt) return;
    WhatsNewProcess.pillCleared = true;
    writeSeenQuietly(widget.writeSeenVersion ?? (v) async => await UpdatePrefs.writeWhatsNewSeenVersion(v), installed);
    if (mounted) setState(() {});
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _enabled = value;
      _checkMessage = null;
    });
    final ok = await UpdatePrefs.writeEnabled(value);
    // A write that failed puts the switch back (nothing was saved).
    if (!ok && mounted) setState(() => _enabled = !value);
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _checkMessage = null;
    });
    final result = await _service.checkNow();
    final last = await UpdatePrefs.readLastCheckAt();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _lastChecked = last;
      _checkMessage = switch (result) {
        CheckNowResult.newVersion => kCheckNowNewVersion,
        CheckNowResult.upToDate => kCheckNowUpToDate,
        CheckNowResult.failed => kCheckNowFailed,
      };
    });
  }

  Future<void> _seeWhatsNew() async {
    var opened = false;
    try {
      opened = await StorageBridge.instance.openUrl(AppConstants.siteUrl);
    } catch (_) {}
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(kUpdatesCouldNotOpen)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final notices = _inbox.notices;
    return SecondaryScaffold(
      title: kUpdatesTitle,
      followPalette: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          _controls(palette),
          const SizedBox(height: 14),
          for (final n in notices)
            NoticeCard(
              notice: n,
              onSeeWhatsNew: _seeWhatsNew,
              onOpenBackup: () => Navigator.of(context).pushNamed(Routes.backup),
            ),
          // The one synthetic What's-new entry: always there, even with no notices.
          WhatsNewEntryCard(showNew: _showNew, onOpen: _openPager),
          if (notices.isEmpty) _empty(palette),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              kUpdatesFootnote,
              key: const Key('updatesFootnote'),
              style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
            ),
          ),
        ],
      ),
    );
  }

  bool get _checkFailed => _checkMessage == kCheckNowFailed;

  /// The mock's error text colour (tokens.css --err-text), light and dark.
  Color _errInk(AppPalette palette) =>
      palette.brightness == Brightness.dark ? const Color(0xFFFF8A8E) : const Color(0xFFB3261E);

  Widget _controls(AppPalette palette) {
    final last = _lastChecked;
    return SettingsCard(
      palette: palette,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsToggle(
            key: const Key('updateSwitch'),
            palette: palette,
            icon: Icons.refresh_rounded,
            label: kUpdatesSwitchTitle,
            subtitle: updatesSwitchSubtitle(on: _enabled, lastChecked: last == null ? null : formatBackupDay(last)),
            value: _enabled,
            onChanged: _setEnabled,
            first: true,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44, // S11b: was 42; 44 is the hit-area floor
                  child: OutlinedButton.icon(
                    key: const Key('checkNowButton'),
                    onPressed: _checking ? null : _checkNow,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(_checking ? kUpdatesCheckingLabel : kUpdatesCheckNowLabel),
                    style: OutlinedButton.styleFrom(foregroundColor: palette.primary),
                  ),
                ),
                // Only while the automatic switch is off (Q2): the button still
                // goes online once, and this says so. Hidden mid-check.
                if (!_enabled && !_checking)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      kUpdatesCheckNowOffCaption,
                      key: const Key('checkNowOffCaption'),
                      style: TextStyle(fontSize: 12, height: 1.45, color: palette.mutedInk),
                    ),
                  ),
                if (_checkMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Semantics(
                      liveRegion: true,
                      child: _checkFailed
                          // Error pattern A (C-B2/C-B10b): red text + warning icon, no timer.
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 16, color: _errInk(palette)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _checkMessage!,
                                    key: const Key('checkNowResult'),
                                    style: TextStyle(
                                        fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: _errInk(palette)),
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              _checkMessage!,
                              key: const Key('checkNowResult'),
                              style: TextStyle(fontSize: 13, height: 1.4, color: palette.softInk),
                            ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(AppPalette palette) {
    return Padding(
      key: const Key('updatesEmpty'),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: palette.tint, shape: BoxShape.circle),
            child: Icon(Icons.notifications_none_rounded, color: palette.tintInk, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            kUpdatesEmptyTitle,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: palette.ink),
          ),
          const SizedBox(height: 8),
          Text(
            _enabled ? kUpdateCheckCadence : kUpdatesEmptyOff,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }
}
