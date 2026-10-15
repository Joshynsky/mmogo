import 'package:flutter/material.dart';

import '../../../data/maintenance/delete_data_service.dart';
import '../../copy/delete_data_copy.dart';
import '../../restart_scope.dart';
import '../../theme/app_colors.dart';
import '../backup/backup_export_flow.dart';
import 'delete_data_factory.dart';
import 'delete_data_run_sheet.dart';
import 'delete_data_sheet.dart';
import 'settings_widgets.dart';

/// §SETTINGS.DELETE_ROW — the "Delete data" row, last in Your data (0.1.2
/// S9b-2, DD2 + CB6). Owns the peek that sets its subtitle, opens the Delete
/// data sheet, then the run sheet, and peeks again when everything closes.
///
/// [deleteData], [restart] and [backupFlow] are seams (A1, A2, A9): the real
/// service comes from `DeleteDataServices.create()` (the one factory), the
/// real restart is `RestartScope.restart`.
class DeleteDataRow extends StatefulWidget {
  const DeleteDataRow({super.key, required this.palette, this.deleteData, this.restart, this.backupFlow});

  final AppPalette palette;
  final DeleteDataService? deleteData;
  final Future<bool> Function(BuildContext)? restart;
  final BackupExportFlow? backupFlow;

  @override
  State<DeleteDataRow> createState() => _DeleteDataRowState();
}

class _DeleteDataRowState extends State<DeleteDataRow> {
  late final DeleteDataService _service = widget.deleteData ?? DeleteDataServices.create();
  final _focus = FocusNode(debugLabel: 'deleteDataRow');
  DeleteDataPeek? _peek;

  @override
  void initState() {
    super.initState();
    _readPeek();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Never throws: a failed peek leaves the default subtitle.
  Future<DeleteDataPeek?> _readPeek() async {
    DeleteDataPeek? p;
    try {
      p = await _service.peek();
    } catch (_) {
      p = null;
    }
    if (mounted) setState(() => _peek = p);
    return p;
  }

  String get _subtitle {
    final p = _peek;
    if (p == null) return kDeleteRowSubtitle;
    if (p.nothingLeftAtLevel2) return kDeleteRowSubtitleNothing;
    if (p.nothingLeftToDeleteAtLevel1) return kDeleteRowSubtitleLevel1Done;
    return kDeleteRowSubtitle;
  }

  bool get _active => !(_peek?.nothingLeftAtLevel2 ?? false);

  Future<void> _open() async {
    final level = await showDeleteDataSheet(
      context,
      peek: _service.peek,
      initialPeek: _peek,
      flow: widget.backupFlow,
    );
    if (level != null && mounted) {
      await showDeleteRunSheet(
        context,
        service: _service,
        level: level,
        restart: widget.restart ?? RestartScope.restart,
      );
    }
    if (!mounted) return;
    _focus.requestFocus();
    await _readPeek(); // the subtitle is current after ANY close path
  }

  @override
  Widget build(BuildContext context) {
    return SettingsLink(
      palette: widget.palette,
      icon: Icons.delete_outline,
      label: kDeleteDataTitle,
      subtitle: _subtitle,
      redTag: kDeletePermanentTag,
      focusNode: _focus,
      onTap: _active ? _open : null,
    );
  }
}
