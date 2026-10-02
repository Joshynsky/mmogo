import 'dart:typed_data';

import 'package:flutter/material.dart' show SnackBar, Text;

import '../../platform/storage_bridge.dart';
import '../../ui/shell/app_messenger.dart';
import '../db/app_database.dart';
import '../prefs/backup_prefs.dart';
import 'backup_service.dart';

/// Automatic backup (architecture D6, WBS B20). After every N newly saved
/// entries one NEW file `mmogo-auto-YYYYMMDD-HHMMSS.json` is created in the
/// folder the user picked, then older automatic files beyond K are deleted.
///
/// Rules this class keeps (each has a test):
/// - [onEntrySaved] never throws, is inert when auto-backup is off, and a run
///   in progress is never started twice (`_running`); entries saved meanwhile
///   are counted afterwards.
/// - A file is only ever CREATED (never opened for writing again), so a
///   failed write cannot damage an older backup.
/// - Pruning deletes only files whose name matches [autoFileName] AND that
///   this app wrote itself (their URIs are on a list in prefs). The bridge
///   cannot read a listed file, so the "app marker in the first 256 bytes"
///   check of the Lead ruling is replaced by this stricter list; a manual
///   `mmogo-backup-...` file or any other file is never touched.
/// - A lost folder permission pauses auto-backup until the user picks a
///   folder again; two failed writes in a row pause it too.
class AutoBackupService {
  AutoBackupService({
    StorageBridge Function()? bridge,
    Future<Uint8List> Function()? export,
    DateTime Function()? now,
    void Function(String message)? notify,
  })  : _bridge = bridge ?? (() => StorageBridge.instance),
        _export = export ?? _defaultExport,
        _now = now ?? DateTime.now,
        _notify = notify ?? _snackbar;

  /// The one the app uses; `AddScreen._save` calls it.
  static AutoBackupService instance = AutoBackupService();

  /// Shown once when auto-backup pauses itself.
  static const pausedMessage =
      'Auto-backup is paused: mmogo can no longer use your backup folder. Open Backup and restore to choose a folder again.';

  /// Two failed writes in a row pause auto-backup.
  static const failuresBeforePause = 2;

  /// Names this service writes (and the only names it may prune), with the
  /// optional ` (n)` a provider adds to avoid a clash.
  static final autoFileName = RegExp(r'^mmogo-auto-(\d{8})-(\d{6})(?: \((\d+)\))?\.json$');

  final StorageBridge Function() _bridge;
  final Future<Uint8List> Function() _export;
  final DateTime Function() _now;
  final void Function(String message) _notify;

  bool _running = false;
  int _queued = 0;

  static Future<Uint8List> _defaultExport() =>
      BackupService(db: () => AppDatabase.instance.database).exportToBytes();

  static void _snackbar(String message) {
    appMessengerKey.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  /// `mmogo-auto-YYYYMMDD-HHMMSS.json` from the local fields of [t]. Only a
  /// timestamp: no name, phone number or device name.
  static String fileNameFor(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final d = '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}';
    return 'mmogo-auto-$d-${two(t.hour)}${two(t.minute)}${two(t.second)}.json';
  }

  /// Call once per NEW entry, after `TransactionDao.insert` succeeded (not for
  /// edits, deletes, undo or restore). Never throws; returns when done, so
  /// callers should not await it on the save path.
  Future<void> onEntrySaved() async {
    try {
      if (_running) {
        _queued++;
        return;
      }
      _running = true;
      try {
        await _run();
      } finally {
        _running = false;
      }
      await _countQueued();
    } catch (_) {
      // Failure never blocks saving an entry.
    }
  }

  Future<void> _countQueued() async {
    final q = _queued;
    _queued = 0;
    if (q == 0) return;
    if (!await BackupPrefs.readEnabled() || await BackupPrefs.readFolderUri() == null) return;
    if (await BackupPrefs.readPaused()) return;
    await BackupPrefs.writeSinceCount(await BackupPrefs.readSinceCount() + q);
  }

  Future<void> _run() async {
    if (!await BackupPrefs.readEnabled()) return;
    final folder = await BackupPrefs.readFolderUri();
    if (folder == null) return; // switched on, no folder chosen yet
    if (await BackupPrefs.readPaused()) return; // only "choose folder again" clears this

    final count = (await BackupPrefs.readSinceCount()) + 1;
    await BackupPrefs.writeSinceCount(count);
    if (count < await BackupPrefs.readEveryN()) return;

    final bridge = _bridge();
    try {
      if (!await bridge.hasWriteGrant(folder)) {
        await _pause();
        return;
      }
      final startedAt = _now();
      final bytes = await _export();
      final created = await bridge.createFile(folder, fileNameFor(startedAt), bytes);
      final files = await _listOrNull(bridge, folder);
      final mine = files?.where((f) => f.uri == created);
      if (mine != null && mine.isNotEmpty && mine.first.size != bytes.length) {
        await _deleteQuietly(bridge, created);
        throw const StorageException(StorageErrorCode.io, 'size mismatch');
      }
      final written = [...await BackupPrefs.readWrittenUris(), created];
      await BackupPrefs.writeSinceCount(0);
      await BackupPrefs.writeFailCount(0);
      await BackupPrefs.writeLastAt(startedAt);
      await BackupPrefs.writeWrittenUris(written);
      if (files != null) await _prune(bridge, files, created, written);
    } on StorageException catch (e) {
      if (e.code == StorageErrorCode.grantLost) {
        await _pause();
      } else {
        await _failed();
      }
    } catch (_) {
      await _failed();
    }
  }

  Future<List<FolderFile>?> _listOrNull(StorageBridge bridge, String folder) async {
    try {
      return await bridge.listFiles(folder);
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteQuietly(StorageBridge bridge, String uri) async {
    try {
      await bridge.deleteFile(uri);
    } catch (_) {}
  }

  Future<void> _pause() async {
    await BackupPrefs.writePaused(true);
    _notify(pausedMessage);
  }

  /// A failed write keeps the counter (so the next saved entry retries); the
  /// second failure in a row pauses.
  Future<void> _failed() async {
    final fails = (await BackupPrefs.readFailCount()) + 1;
    await BackupPrefs.writeFailCount(fails);
    if (fails >= failuresBeforePause) await _pause();
  }

  /// Keeps the newest K of this app's own automatic files. [listing] already
  /// contains [justWritten], which is never deleted. Errors are ignored: an
  /// extra file is harmless.
  Future<void> _prune(StorageBridge bridge, List<FolderFile> listing, String justWritten, List<String> written) async {
    try {
      final keepK = await BackupPrefs.readKeepK();
      final mine = written.toSet();
      final eligible = listing.where((f) => mine.contains(f.uri) && autoFileName.hasMatch(f.name)).toList()
        ..sort((a, b) => _sortKey(b.name).compareTo(_sortKey(a.name)));
      final gone = <String>{};
      for (final f in eligible.skip(keepK)) {
        if (f.uri == justWritten) continue;
        try {
          await bridge.deleteFile(f.uri);
          gone.add(f.uri);
        } catch (_) {}
      }
      // Forget files that are gone, whether we deleted them or the user did.
      final present = listing.map((f) => f.uri).toSet();
      await BackupPrefs.writeWrittenUris([
        for (final u in written)
          if (present.contains(u) && !gone.contains(u)) u,
      ]);
    } catch (_) {}
  }

  /// Timestamp in the NAME, then the provider's ` (n)` suffix.
  static String _sortKey(String name) {
    final m = autoFileName.firstMatch(name);
    if (m == null) return '';
    return '${m.group(1)}${m.group(2)}${(int.tryParse(m.group(3) ?? '0') ?? 0).toString().padLeft(6, '0')}';
  }

  /// The user picked (and accepted) [folder]: starts or restarts auto-backup
  /// there. Clears paused, the counter, the failure count and the written
  /// list; releases the previous folder's permission if it was another one.
  /// Returns false if a pref could not be written.
  Future<bool> useFolder(PickedFolder folder) async {
    final old = await BackupPrefs.readFolderUri();
    var ok = await BackupPrefs.writeFolderUri(folder.uri);
    ok = await BackupPrefs.writeFolderName(folder.name) && ok;
    ok = await BackupPrefs.writeSinceCount(0) && ok;
    ok = await BackupPrefs.writeFailCount(0) && ok;
    ok = await BackupPrefs.writeWrittenUris(const []) && ok;
    ok = await BackupPrefs.writePaused(false) && ok;
    ok = await BackupPrefs.writeEnabled(true) && ok;
    if (old != null && old != folder.uri) await _releaseQuietly(old);
    return ok;
  }

  /// Turns auto-backup off: releases the folder permission and clears the
  /// folder keys (enabled, paused, counter included). Files already written
  /// stay where they are.
  Future<bool> turnOff() async {
    final old = await BackupPrefs.readFolderUri();
    final ok = await BackupPrefs.clearAutoBackup();
    if (old != null) await _releaseQuietly(old);
    return ok;
  }

  Future<void> _releaseQuietly(String uri) async {
    try {
      await _bridge().releaseGrant(uri);
    } catch (_) {}
  }

  /// Releases a permission the user got from the picker but then declined
  /// (for example "Choose another folder" at the cloud notice), unless it is
  /// the folder already in use.
  Future<void> releaseUnused(PickedFolder folder) async {
    if (await BackupPrefs.readFolderUri() == folder.uri) return;
    await _releaseQuietly(folder.uri);
  }
}
