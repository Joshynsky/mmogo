import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/backup/backup_service.dart';
import '../../../data/db/app_database.dart';
import '../../../data/prefs/backup_prefs.dart';
import '../../copy/data_copy.dart';
import '../../theme/app_colors.dart';
import 'backup_widgets.dart';
import '../../widgets/palette_alert_dialog.dart';

/// Builds the backup (the real [BackupService.export] by default).
typedef BackupExporter = Future<BackupExport> Function();

/// Hands the file at [path] to the OS share sheet. Returns false only when the
/// user is known to have dismissed the sheet without sharing.
typedef BackupSharer = Future<bool> Function(String path, String fileName);

/// The temp file the share sheet reads. A seam so widget tests (which cannot
/// do real file IO) can fake it.
abstract interface class BackupTempFiles {
  /// Writes [bytes] as [name] in a temp location and returns its path.
  Future<String> write(String name, Uint8List bytes);

  /// Removes the file; never throws.
  Future<void> delete(String path);
}

/// The real thing: `getTemporaryDirectory()` plus `dart:io`.
class DeviceTempFiles implements BackupTempFiles {
  const DeviceTempFiles();

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  @override
  Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Nothing more to do: the OS clears its temp directory.
    }
  }
}

/// How a "Back up now" run ended.
sealed class BackupOutcome {
  const BackupOutcome();
}

/// The user backed out of the warning dialog; nothing was built.
class BackupCancelled extends BackupOutcome {
  const BackupCancelled();
}

/// The file reached the share sheet and was not dismissed.
class BackupShared extends BackupOutcome {
  const BackupShared(this.export, this.at);
  final BackupExport export;
  final DateTime at;
}

/// The share sheet was closed without sharing; `backup_last_manual_at` is NOT
/// written.
class BackupNotShared extends BackupOutcome {
  const BackupNotShared();
}

/// Building, writing or sharing failed. Carries nothing: no row content.
class BackupFailed extends BackupOutcome {
  const BackupFailed();
}

/// The Back up now flow: warning dialog, export, temp file, share, cleanup,
/// "last backup" write. Every platform step is an injected seam (like the CSV
/// export's), so widget tests use fakes.
class BackupExportFlow {
  BackupExportFlow({
    BackupExporter? export,
    BackupSharer? share,
    BackupTempFiles? files,
    DateTime Function()? now,
    Future<bool> Function(DateTime when)? recordLastBackup,
  }) : _export = export ?? _defaultExport,
       _share = share ?? _defaultShare,
       _files = files ?? const DeviceTempFiles(),
       _now = now ?? DateTime.now,
       _record = recordLastBackup ?? BackupPrefs.writeLastManualAt;

  final BackupExporter _export;
  final BackupSharer _share;
  final BackupTempFiles _files;
  final DateTime Function() _now;
  final Future<bool> Function(DateTime when) _record;

  static Future<BackupExport> _defaultExport() async {
    final db = await AppDatabase.instance.database;
    return BackupService(db: () async => db).export();
  }

  static Future<bool> _defaultShare(String path, String fileName) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/json', name: fileName)],
        subject: 'mmogo backup',
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }

  /// The warning dialog. `true` only when the user taps "Share backup".
  static Future<bool> confirm(BuildContext context) async {
    final palette = AppPalette.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => PaletteAlertDialog(
        title: const Text('Before you back up'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BackupWarning(palette: palette, text: kBackupFileWarning, bottomGap: 10),
              const Text("The next screen is Android's share sheet. Pick where the file goes."),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Share backup')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Everything after the dialog: build, write the temp file, share, delete the
  /// temp file (always), then write `backup_last_manual_at`.
  Future<BackupOutcome> execute() async {
    String? tempPath;
    try {
      final export = await _export();
      final when = _now();
      final name = _fileName(when);
      tempPath = await _files.write(name, export.bytes);
      final shared = await _share(tempPath, name);
      if (!shared) return const BackupNotShared();
      // A failed prefs write only means the "Last backup" line is stale; the
      // backup itself went out, so it is not reported as a failure.
      await _record(when);
      return BackupShared(export, when);
    } catch (_) {
      return const BackupFailed();
    } finally {
      if (tempPath != null) await _files.delete(tempPath);
    }
  }

  /// `mmogo-backup-YYYYMMDD-HHMMSS.json` (the format [BackupService] pins).
  static String _fileName(DateTime now) =>
      BackupService(db: () => Future<Database>.error(StateError('unused'))).suggestedFileName(now);

  /// For tests: the same name the flow gives the shared file.
  static String fileNameFor(DateTime now) => _fileName(now);
}
