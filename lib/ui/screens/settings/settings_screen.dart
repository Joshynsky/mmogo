import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../app_info.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/export_dao.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../copy/data_copy.dart';
import '../../shell/routes.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../widgets/coach_tour.dart';
import 'appearance_section.dart';
import '../backup/backup_format.dart';
import 'data_section.dart';
import 'preferences_section.dart';
import 'privacy_section.dart';
import 'updates_section.dart';

/// Settings' coach-tour page id (the seen flag is `tour_seen_settings`).
const settingsTourId = 'settings';

/// B48: a secondary page opened from Profile's "Settings" row (it was the
/// fifth bottom-nav tab until then). T2's original routing scope for this screen:
/// the two links that hand off to secondary pages (Manage Classifications,
/// Recently Deleted) and back. T8 wired the "Manage Classifications" link to
/// its real page. T10 wired "Export CSV" to the real `ExportDao` query +
/// `share_plus` share sheet (CSV export has no table of its own). T18 wired the "Auto-recognize classifications" toggle to
/// `AppPrefs`' real read/write pair. T23 (this dispatch) reworks the page
/// to the T23 draft mock: seamless top bar, followPhoneTheme, cards
/// regrouped under Appearance/Your data/Preferences, and a working colour
/// palette switch (`AppPaletteScope`) at the top — palette tokens only, no
/// `AppColors.muted`/`text` on this page.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.db, this.exportCsv});

  /// Test-only injection seam (defaults to `null` in real app usage, which
  /// resolves via `AppDatabase.instance.database` at bootstrap — same
  /// convention `manage_classifications_screen.dart`/
  /// `recently_deleted_screen.dart` already use). A real
  /// `sqflite_common_ffi` `Database` hangs indefinitely inside
  /// `testWidgets` in this environment, so widget tests drive this screen
  /// against a fake `Database` instead.
  final Database? db;

  /// Test-only injection seam for the write-temp-file + `share_plus`
  /// share-sheet side effect ([_defaultExportCsv]). `null` in real app
  /// usage resolves to the real implementation, which touches
  /// `path_provider`/`share_plus` platform channels not available inside
  /// `testWidgets` in this environment — widget tests inject a fake here to
  /// exercise the button's enabled/disabled state and success/failure
  /// SnackBar without a real platform channel, while `export_dao_test.dart`
  /// separately, authoritatively proves the real CSV content/row-count
  /// against a genuine in-memory sqlite3 database.
  final Future<void> Function(String csvContent, int transactionCount)? exportCsv;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Database? _db;
  bool _loading = true;
  int _activeCount = 0;
  bool _exporting = false;
  // Sane default while `_loading` is true: matches AppPrefs' own
  // documented default (ON) so the switch doesn't visibly flip from
  // off->on once the real read resolves in the common case.
  bool _autoRecognize = true;
  String _backupSubtitle = 'Never backed up';
  bool _backupPaused = false;

  // Coach-tour anchors.
  final _paletteTourKey = GlobalKey();
  final _dataTourKey = GlobalKey();
  final _prefsTourKey = GlobalKey();
  bool _tourOffered = false;

  @override
  void initState() {
    super.initState();
    BackupPrefs.pausedNotifier.addListener(_onPausedChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    BackupPrefs.pausedNotifier.removeListener(_onPausedChanged);
    super.dispose();
  }

  /// Shows the tour (or its unfinished rest) once the frame has painted.
  void _offerTour() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) CoachTour.maybeStart(context, pageId: settingsTourId, steps: _tourSteps());
    });
  }

  Future<void> _bootstrap() async {
    final db = widget.db ?? await AppDatabase.instance.database;
    if (!mounted) return;
    final count = await ExportDao.activeTransactionCount(db);
    final autoRecognize = await AppPrefs.readAutoRecognizeClassifications();
    final backupSubtitle = await _readBackupSubtitle();
    if (!mounted) return;
    setState(() {
      _db = db;
      _activeCount = count;
      _autoRecognize = autoRecognize;
      _backupSubtitle = backupSubtitle;
      _loading = false;
    });
    if (!_tourOffered) {
      _tourOffered = true;
      _offerTour();
    }
  }

  /// The newer of the manual and automatic backup times, or `Never backed up`;
  /// when auto-backup is paused the subtitle says so (and [_backupPaused]
  /// shows the warning dot).
  Future<String> _readBackupSubtitle() async {
    final paused = await BackupPrefs.readEnabled() && await BackupPrefs.readPaused();
    _backupPaused = paused;
    if (paused) return kAutoBackupPausedSubtitle;
    final manual = await BackupPrefs.readLastManualAt();
    final auto = await BackupPrefs.readLastAt();
    final last = (manual != null && auto != null) ? (manual.isAfter(auto) ? manual : auto) : (manual ?? auto);
    return backupRowSubtitle(last);
  }

  /// Auto-backup paused or resumed while this page is open.
  Future<void> _onPausedChanged() async {
    final subtitle = await _readBackupSubtitle();
    if (!mounted) return;
    setState(() => _backupSubtitle = subtitle);
  }

  /// Opens the Backup page and refreshes the row's subtitle when it closes.
  Future<void> _openBackup() async {
    await Navigator.of(context).pushNamed(Routes.backup);
    if (!mounted) return;
    // A restore on that page may have changed the data and the switches here.
    final db = _db;
    final count = db == null ? _activeCount : await ExportDao.activeTransactionCount(db);
    final autoRecognize = await AppPrefs.readAutoRecognizeClassifications();
    final subtitle = await _readBackupSubtitle();
    if (!mounted) return;
    setState(() {
      _activeCount = count;
      _autoRecognize = autoRecognize;
      _backupSubtitle = subtitle;
    });
  }

  /// Flips the switch immediately (never waits on the write) then persists
  /// in the background — same "update local state now, persist
  /// fire-and-forget" shape as [_handleExport]'s SnackBar-on-completion
  /// pattern, but without a SnackBar: a `Switch` gives its own instant
  /// visual feedback, so no extra confirmation UI is needed here.
  void _handleAutoRecognizeChanged(bool value) {
    setState(() => _autoRecognize = value);
    AppPrefs.writeAutoRecognizeClassifications(value);
  }

  /// Real (non-test) share-sheet implementation: writes the CSV to a temp
  /// file (needed because `share_plus`'s `ShareParams.files` wraps
  /// `Intent.ACTION_SEND` with a file attachment, not raw text) then hands
  /// it to the OS share sheet (the settled mechanism for export).
  static Future<void> _defaultExportCsv(String csvContent, int transactionCount) async {
    final dir = await getTemporaryDirectory();
    final fileName = 'mmogo-export-${DateTime.now().millisecondsSinceEpoch}.csv';
    final path = p.join(dir.path, fileName);
    await File(path).writeAsString(csvContent);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'text/csv', name: fileName)],
        subject: 'mmogo CSV export',
      ),
    );
  }

  Future<void> _handleExport() async {
    final db = _db;
    if (db == null || _activeCount == 0 || _exporting) return;
    setState(() => _exporting = true);
    try {
      final rows = await ExportDao.activeTransactions(db);
      final csv = ExportDao.toCsv(rows);
      final exportFn = widget.exportCsv ?? _defaultExportCsv;
      await exportFn(csv, rows.length);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported — ${rows.length} transaction${rows.length == 1 ? '' : 's'}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV export failed — please try again')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// Clears every page's "tour seen" flag. Pages already open in this session
  /// offer their tour again next launch (Add: next time it is opened); their
  /// header "?" replays one straight away.
  Future<void> _showTipsAgain() async {
    await AppPrefs.resetAllTours();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Tips reset. The guides will show again.')));
  }

  List<CoachStep> _tourSteps() => [
    CoachStep(target: _paletteTourKey, text: 'Pick a colour palette. It follows your phone’s light or dark mode.'),
    CoachStep(
      target: _dataTourKey,
      text: 'Manage your categories, restore deleted transactions, or share everything as a CSV.',
      onEnter: () => scrollIntoView(_dataTourKey),
      actionLabel: 'Open Manage classifications',
      onAction: () async {
        // The tour pauses here; when Manage classifications is closed, pick
        // it up at the next step.
        await Navigator.of(context).pushNamed(Routes.manageClassifications);
        if (mounted) {
          CoachTour.maybeStart(context, pageId: settingsTourId, steps: _tourSteps());
        }
      },
    ),
    CoachStep(
      target: _prefsTourKey,
      text: 'Suggest categories for repeat receivers. “Show tips again” replays these guides.',
      onEnter: () => scrollIntoView(_prefsTourKey),
    ),
  ];

  String get _exportSubtitle {
    if (_loading) return 'Loading…';
    if (_activeCount == 0) return 'No transactions to export yet';
    if (_exporting) return 'Preparing export…';
    return 'Share all $_activeCount transaction${_activeCount == 1 ? '' : 's'} as CSV';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final exportEnabled = !_loading && _activeCount > 0 && !_exporting;
    // B48: a secondary page opened from Profile (back button, no bottom bar).
    return SecondaryScaffold(
      title: 'Settings',
      followPalette: true,
      // No pull-to-refresh on Settings (PM direct decision, T23 draft):
      // nothing here changes from elapsed time the way Home/Analytics do.
      body: ListView(
        key: const Key('settingsScroll'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          AppearanceSection(palette: palette, tourKey: _paletteTourKey),
          const SizedBox(height: 14),
          DataSection(
            palette: palette,
            tourKey: _dataTourKey,
            exportSubtitle: _exportSubtitle,
            exportEnabled: exportEnabled,
            onExport: _handleExport,
            backupSubtitle: _backupSubtitle,
            onBackup: _openBackup,
            backupPaused: _backupPaused,
          ),
          const SizedBox(height: 14),
          PreferencesSection(
            palette: palette,
            tourKey: _prefsTourKey,
            autoRecognize: _autoRecognize,
            onAutoRecognizeChanged: _loading ? null : _handleAutoRecognizeChanged,
            onShowTipsAgain: _showTipsAgain,
          ),
          const SizedBox(height: 14),
          PrivacySection(palette: palette),
          const SizedBox(height: 14),
          UpdatesSection(palette: palette),
          const SizedBox(height: 14),
          Text(
            '${AppInfo.name} ${AppInfo.versionName} · your data stays on this phone',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: palette.mutedInk),
          ),
        ],
      ),
    );
  }
}
