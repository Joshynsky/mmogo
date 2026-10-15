import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../app_info.dart';
import '../../../data/db/app_database.dart';
import '../../../data/db/export_dao.dart';
import '../../../data/maintenance/delete_data_service.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../../domain/analytics/chart_blocks.dart' show MonthChartStyle, WhereItWentStyle, YearViewAmounts;
import '../../copy/data_copy.dart';
import '../../copy/settings_copy.dart';
import '../../shell/primary_shell.dart';
import '../../shell/routes.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette_scope.dart';
import '../../widgets/coach_tour.dart';
import '../backup/backup_export_flow.dart';
import '../backup/backup_format.dart';
import 'about_section.dart';
import 'adding_section.dart';
import 'data_section.dart';
import 'look_section.dart';

/// Settings' coach-tour page id (the seen flag is `tour_seen_settings`).
const settingsTourId = 'settings';

/// B48: a secondary page opened from Profile's "Settings" row (it was the
/// fifth bottom-nav tab until then). T2's original routing scope for this screen:
/// the two links that hand off to secondary pages (Manage Classifications,
/// Recently Deleted) and back. T8 wired the "Manage Classifications" link to
/// its real page. T10 wired "Export CSV" to the real `ExportDao` query +
/// `share_plus` share sheet (CSV export has no table of its own). T18 wired the "Auto-recognize classifications" toggle to
/// `AppPrefs`' real read/write pair. T23 reworked the page to the T23 draft
/// mock (seamless top bar, palette tokens only, a working colour palette).
/// 0.1.2 S9a (ST1, signed mock M9): sections LOOK, ADDING ENTRIES, YOUR DATA
/// (careful), ABOUT; the Look rows write the Look prefs explicitly and refresh
/// Home and Analytics through `PrimaryShell.active?.dataChanged()`; the
/// Appearance icons drive the whole app's light/dark (`AppPaletteController`).
/// S9b-2: the Delete data row is the last row of Your data (delete_data_row.dart).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.db, this.exportCsv, this.deleteData, this.restart, this.backupFlow});

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

  /// Delete data seams (S9b-2, A1/A2/A9). Null = the real service from the one
  /// factory (`DeleteDataServices.create`), `RestartScope.restart` and the real
  /// Back up now flow. Tests pass fakes (see `test/support/fake_delete_data.dart`).
  final DeleteDataService? deleteData;
  final Future<bool> Function(BuildContext)? restart;
  final BackupExportFlow? backupFlow;

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
  // The Look values, read in _bootstrap (the prefs' own defaults until then).
  int _firstDay = AppPrefs.defaultFirstDayOfWeek;
  MonthChartStyle _monthStyle = MonthChartStyle.weeks;
  YearViewAmounts _yearAmounts = YearViewAmounts.quarters;
  bool _showWithdrawals = false;
  WhereItWentStyle _whereStyle = WhereItWentStyle.button;
  String _backupSubtitle = 'Never backed up';
  bool _backupPaused = false;

  // Coach-tour anchors.
  final _paletteTourKey = GlobalKey();
  final _dataTourKey = GlobalKey();
  final _addingTourKey = GlobalKey();
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
    await _readLook();
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

  /// Reads the five Look values (also after Backup closes: a restore may have
  /// changed them). Does not call setState; the caller does.
  Future<void> _readLook() async {
    _firstDay = await AppPrefs.readFirstDayOfWeek();
    _monthStyle = await AppPrefs.readMonthChartStyle();
    _yearAmounts = await AppPrefs.readYearViewAmounts();
    _showWithdrawals = await AppPrefs.readShowWithdrawalsInChart();
    _whereStyle = await AppPrefs.readWhereItWentStyle();
  }

  /// After a Look write: Home and Analytics re-read their prefs at once (the
  /// same notifier Add and a restore use). Settings is pushed over the shell.
  void _lookChanged() => PrimaryShell.active?.dataChanged();

  void _setAppearance(String mode) {
    // Applies at once (the whole app), persists in the background. Device-only.
    AppPaletteScope.of(context).selectAppearance(mode);
  }

  Future<void> _pickFirstDay() async {
    final day = await showFirstDayDialog(context, current: _firstDay);
    if (day == null || !mounted) return; // Cancel, a tap outside or Back: nothing changes
    setState(() => _firstDay = day);
    await AppPrefs.writeFirstDayOfWeek(day);
    _lookChanged();
  }

  Future<void> _setMonthStyle(MonthChartStyle v) async {
    setState(() => _monthStyle = v);
    await AppPrefs.writeMonthChartStyle(v);
    _lookChanged();
  }

  Future<void> _setYearAmounts(YearViewAmounts v) async {
    setState(() => _yearAmounts = v);
    await AppPrefs.writeYearViewAmounts(v);
    _lookChanged();
  }

  Future<void> _setShowWithdrawals(bool v) async {
    setState(() => _showWithdrawals = v);
    await AppPrefs.writeShowWithdrawalsInChart(v);
    _lookChanged();
  }

  Future<void> _setWhereStyle(WhereItWentStyle v) async {
    setState(() => _whereStyle = v);
    await AppPrefs.writeWhereItWentStyle(v);
    _lookChanged();
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
    await _readLook();
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

  List<CoachStep> _tourSteps() => [
    CoachStep(
      target: _paletteTourKey,
      text: 'Pick a colour palette, and choose light or dark under Appearance. The other choices here set how Home and Analytics look.',
    ),
    CoachStep(
      target: _addingTourKey,
      text: 'Suggest categories for repeat receivers, manage your categories, or review the names mmogo remembers.',
      onEnter: () => scrollIntoView(_addingTourKey),
      actionLabel: 'Open Manage categories',
      onAction: () async {
        // The tour pauses here; when Manage categories is closed, pick it up
        // at the next step.
        await Navigator.of(context).pushNamed(Routes.manageClassifications);
        if (mounted) {
          CoachTour.maybeStart(context, pageId: settingsTourId, steps: _tourSteps());
        }
      },
    ),
    CoachStep(
      target: _dataTourKey,
      text: 'Back up and restore, bring back deleted transactions, or share everything as a CSV.',
      onEnter: () => scrollIntoView(_dataTourKey),
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
      title: kSettingsTitle,
      followPalette: true,
      // No pull-to-refresh on Settings (PM direct decision, T23 draft):
      // nothing here changes from elapsed time the way Home/Analytics do.
      body: ListView(
        key: const Key('settingsScroll'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          LookSection(
            palette: palette,
            tourKey: _paletteTourKey,
            appearance: AppPaletteScope.of(context).appearance,
            onAppearance: _setAppearance,
            firstDay: _firstDay,
            onFirstDay: _pickFirstDay,
            monthStyle: _monthStyle,
            onMonthStyle: _setMonthStyle,
            yearAmounts: _yearAmounts,
            onYearAmounts: _setYearAmounts,
            showWithdrawals: _showWithdrawals,
            onShowWithdrawals: _setShowWithdrawals,
            whereStyle: _whereStyle,
            onWhereStyle: _setWhereStyle,
          ),
          const SizedBox(height: 14),
          AddingSection(
            palette: palette,
            tourKey: _addingTourKey,
            autoRecognize: _autoRecognize,
            onAutoRecognizeChanged: _loading ? null : _handleAutoRecognizeChanged,
          ),
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
            deleteData: widget.deleteData,
            restart: widget.restart,
            backupFlow: widget.backupFlow,
          ),
          const SizedBox(height: 14),
          AboutSection(palette: palette),
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
