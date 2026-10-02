import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/backup/backup_counts.dart';
import '../../../data/db/app_database.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../shell/secondary_scaffold.dart';
import '../../theme/app_colors.dart';
import 'backup_export_flow.dart';
import 'backup_format.dart';
import 'backup_section.dart';

/// Settings > Your data > Backup and restore (Lead ruling F2: a dedicated
/// page). B14 builds "Back up now"; Restore (B17), Auto-backup (B21) and the
/// Privacy row (B32) are added to this page by later tasks.
class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, this.db, this.loadCounts, this.flow});

  /// Test seam: a database to count rows in (defaults to the app database).
  final Database? db;

  /// Test seam replacing the count query.
  final Future<BackupCounts> Function()? loadCounts;

  /// Test seam: the export/share/record steps (defaults to the real ones).
  final BackupExportFlow? flow;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  BackupCounts? _counts;
  bool _countsFailed = false;
  DateTime? _lastManual;
  bool _busy = false;
  String? _result;
  late final BackupExportFlow _flow = widget.flow ?? BackupExportFlow();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _counts = null;
      _countsFailed = false;
    });
    final last = await BackupPrefs.readLastManualAt();
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
          ),
        ],
      ),
    );
  }
}
