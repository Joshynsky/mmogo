import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/backup/backup_counts.dart';
import '../../../data/backup/restore_service.dart';
import '../../../data/db/app_database.dart';
import '../../../data/prefs/app_prefs.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../shell/primary_shell.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette_scope.dart';
import 'auto_backup_card.dart';
import 'auto_backup_flow.dart';
import 'auto_backup_state.dart';
import 'backup_export_flow.dart';
import 'backup_format.dart';
import 'backup_section.dart';
import 'restore_flow.dart';

/// Settings > Your data > Backup and restore (Lead ruling F2: a dedicated
/// page). B14 builds "Back up now"; Restore (B17), Auto-backup (B21) and the
/// Privacy row (B32) are added to this page by later tasks.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    super.key,
    this.db,
    this.loadCounts,
    this.flow,
    this.restoreFlow,
    this.restoreService,
    this.autoFlow,
  });

  /// Test seam: the Auto-backup card's actions (defaults to the real ones,
  /// which use the app's `AutoBackupService` and `StorageBridge`).
  final AutoBackupFlow? autoFlow;

  /// Test seam: a database to count rows in (defaults to the app database).
  final Database? db;

  /// Test seam replacing the count query.
  final Future<BackupCounts> Function()? loadCounts;

  /// Test seam: the export/share/record steps (defaults to the real ones).
  final BackupExportFlow? flow;

  /// Test seam: the Restore flow (defaults to the real one, which refreshes
  /// the app's screens, palette and name after a restore).
  final RestoreFlow? restoreFlow;

  /// Test seam: the restore service the default flow uses (the file picker is
  /// `StorageBridge.instance`).
  final RestoreService Function()? restoreService;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupCounts? _counts;
  bool _countsFailed = false;
  DateTime? _lastManual;
  bool _busy = false;
  String? _result;
  bool _restoring = false;
  AutoBackupState _auto = const AutoBackupState();
  late final AutoBackupFlow _autoFlow = widget.autoFlow ?? AutoBackupFlow(onChanged: _reloadAuto);
  late final BackupExportFlow _flow = widget.flow ?? BackupExportFlow();
  late final RestoreFlow _restoreFlow =
      widget.restoreFlow ?? RestoreFlow(service: widget.restoreService, onDataChanged: _refreshApp);

  /// After a restore or Undo: every live data page re-queries (Home, Analytics,
  /// Paid to, Profile; Settings re-reads when this page closes), the saved
  /// palette is applied at once, the display name is re-read, and this page's
  /// own numbers are refreshed.
  Future<void> _refreshApp() async {
    PrimaryShell.active?.dataChanged();
    AppPrefs.userDisplayNameRevision.value++;
    final palette = AppPaletteScope.maybeOf(context);
    if (palette != null) await palette.load();
    if (mounted) await _load();
  }

  Future<void> _restore() async {
    if (_restoring || _busy) return;
    setState(() {
      _restoring = true;
      _result = null;
    });
    try {
      await _restoreFlow.run(context);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// Re-reads the auto-backup prefs (after a change here, or when the service
  /// pauses itself while this page is open).
  Future<void> _reloadAuto() async {
    final s = await AutoBackupState.load();
    if (mounted) setState(() => _auto = s);
  }

  @override
  void initState() {
    super.initState();
    BackupPrefs.pausedNotifier.addListener(_reloadAuto);
    _load();
  }

  @override
  void dispose() {
    BackupPrefs.pausedNotifier.removeListener(_reloadAuto);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _counts = null;
      _countsFailed = false;
    });
    final last = await BackupPrefs.readLastManualAt();
    final auto = await AutoBackupState.load();
    BackupCounts? counts;
    try {
      final loader = widget.loadCounts;
      counts = loader != null
          ? await loader()
          : await BackupCounts.read(widget.db ?? await AppDatabase.instance.database);
    } catch (_) {
      counts = null;
    }
    if (!mounted) return;
    setState(() {
      _lastManual = last;
      _auto = auto;
      _counts = counts;
      _countsFailed = counts == null;
    });
  }

  Future<void> _backUp() async {
    if (_busy) return;
    if (!await BackupExportFlow.confirm(context)) return;
    if (!mounted) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final outcome = await _flow.execute();
    if (!mounted) return;
    switch (outcome) {
      case BackupShared(:final export, :final at):
        setState(() {
          _busy = false;
          _lastManual = at;
          _result = backupResultMessage(export);
        });
        _refreshCounts();
      case BackupNotShared():
        setState(() {
          _busy = false;
          _result = 'The share sheet was closed. No backup was saved.';
        });
      case BackupFailed():
        setState(() => _busy = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Could not create the backup'),
            content: const Text(kBackupFailedMessage),
            actions: [FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK'))],
          ),
        );
      case BackupCancelled():
        setState(() => _busy = false);
    }
  }

  /// Counts can change under a backup run (an entry added while sharing).
  Future<void> _refreshCounts() async {
    try {
      final loader = widget.loadCounts;
      final c = loader != null
          ? await loader()
          : await BackupCounts.read(widget.db ?? await AppDatabase.instance.database);
      if (mounted) setState(() => _counts = c);
    } catch (_) {
      // Keep the numbers already on screen.
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SecondaryScaffold(
      title: 'Backup and restore',
      followPalette: true,
      body: ListView(
        key: const Key('backupScroll'),
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 32),
        children: [
          BackupSection(
            palette: palette,
            counts: _counts,
            countsFailed: _countsFailed,
            lastManual: _lastManual,
            busy: _busy,
            resultText: _result,
            onBackUp: _backUp,
            onRetry: _load,
            onRestore: _restore,
            restoring: _restoring,
            lastAuto: _auto.lastForLine,
          ),
          const SizedBox(height: 14),
          AutoBackupCard(
            palette: palette,
            state: _auto,
            onToggle: (on) => _autoFlow.toggle(context, on, hasFolder: _auto.hasFolder),
            onChooseFolder: () => _autoFlow.chooseFolder(context),
            onEveryN: _autoFlow.stepEveryN,
            onKeepK: _autoFlow.stepKeepK,
          ),
        ],
      ),
    );
  }
}
