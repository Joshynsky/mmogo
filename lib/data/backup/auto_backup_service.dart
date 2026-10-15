import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart' show SnackBar, Text;

import '../../platform/storage_bridge.dart';
import '../../ui/shell/app_messenger.dart';
import '../db/app_database.dart';
import '../prefs/backup_prefs.dart';
import '../updates/updates_inbox.dart';
import 'auto_backup_leftovers.dart';
import 'backup_service.dart';

export 'auto_backup_leftovers.dart';

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
/// - Every bridge call goes through [_call] (30 s timeout), and a whole run
///   has a deadline ([runDeadline]) with a generation token: a run that hangs
///   is written off as a failed write, and when it wakes up later it writes
///   nothing (S10a, A1a).
/// - Leftover automatic files in a folder the user stops using are found by
///   NAME PATTERN in a fresh listing and deleted only after the user said so
///   (CB9, A4a). Nothing here logs or returns a file name or a URI.
/// - A lost folder permission pauses auto-backup until the user picks a
///   folder again; two failed writes in a row pause it too.
class AutoBackupService {
  AutoBackupService({
    StorageBridge Function()? bridge,
    Future<Uint8List> Function()? export,
    DateTime Function()? now,
    void Function(String message)? notify,
    UpdatesInbox? inbox,
    Duration? bridgeTimeout,
    Duration? runDeadline,
  })  : _runDeadline = runDeadline ?? AutoBackupService.runDeadline,
        _bridge = bridge ?? (() => StorageBridge.instance),
        _export = export ?? _defaultExport,
        _now = now ?? DateTime.now,
        _notify = notify ?? _snackbar,
        _inbox = inbox ?? UpdatesInbox.instance,
        _timeout = bridgeTimeout ?? AutoBackupService.bridgeTimeout;

  /// The one the app uses; `AddScreen._save` calls it.
  static AutoBackupService instance = AutoBackupService();

  /// Shown once when auto-backup pauses itself.
  static const pausedMessage =
      'Auto-backup is paused: mmogo can no longer use your backup folder. Open Backup and restore to choose a folder again.';

  /// Two failed writes in a row pause auto-backup.
  static const failuresBeforePause = 2;

  /// A bridge call or export that takes longer counts as a failed write, so
  /// one that never returns cannot leave a run stuck.
  static const bridgeTimeout = Duration(seconds: 30);

  /// A whole run (grant check, export, create, list, prune) that takes longer
  /// is written off as a failed write. Below [quiesceBound] (35 s) on purpose,
  /// so Delete data never waits for a hung run.
  static const runDeadline = Duration(seconds: 32);

  /// Names this service writes (and the only names it may prune), with the
  /// optional ` (n)` a provider adds to avoid a clash.
  static final autoFileName = RegExp(r'^mmogo-auto-(\d{8})-(\d{6})(?: \((\d+)\))?\.json$');

  final StorageBridge Function() _bridge;
  final Future<Uint8List> Function() _export;
  final DateTime Function() _now;
  final void Function(String message) _notify;
  final UpdatesInbox _inbox;
  final Duration _timeout;
  final Duration _runDeadline;

  bool _running = false;
  int _queued = 0;

  /// Bumped for every run and when the watchdog writes a run off: a run whose
  /// token is no longer current stops and writes nothing.
  int _generation = 0;

  /// 0.1.2 S9b-1 (Delete data): true between [quiesce] and [resume]. While it
  /// is set [onEntrySaved] does nothing at all (no run, no count, no queue).
  bool _blocked = false;

  /// Completed when the run in progress (and the counting of the entries
  /// queued behind it) is over; null when idle.
  Completer<void>? _idle;

  /// Longest [quiesce] waits for a run in progress.
  static const quiesceBound = Duration(seconds: 35);

  /// True while Delete data holds this service still.
  bool get isBlocked => _blocked;

  /// Stops new runs and waits (at most [bound]) for the one in progress.
  /// True = quiet: nothing is running and nothing will start until [resume].
  /// False = the run outlasted the bound: the caller must touch nothing, call
  /// [resume] and report "busy" (or "not finished" at step database).
  Future<bool> quiesce({Duration bound = quiesceBound}) async {
    _blocked = true;
    final idle = _idle;
    if (idle == null) return true;
    try {
      await idle.future.timeout(bound);
      return true;
    } catch (_) {
      _blocked = false;
      return false;
    }
  }

  /// Lets [onEntrySaved] work again and forgets entries counted as queued
  /// (they belong to a state that was just deleted or reset).
  void resume() {
    _blocked = false;
    _queued = 0;
  }

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
      if (_blocked) return; // Delete data holds the service still
      if (_running) {
        _queued++;
        return;
      }
      _running = true;
      final gen = ++_generation;
      final idle = _idle = Completer<void>();
      try {
        try {
          await _run(gen).timeout(_runDeadline, onTimeout: () async {
            // Watchdog: a run that hangs (a bridge that never answers) is a
            // failed write; the run itself is made stale so it writes nothing
            // if it ever wakes up.
            if (gen != _generation) return;
            _generation++;
            _log('run deadline');
            await _failed();
          });
        } finally {
          _running = false;
        }
        await _countQueued();
      } finally {
        _idle = null;
        idle.complete();
      }
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

  /// Throws [_StaleRun] when the watchdog wrote this run off.
  void _alive(int gen) {
    if (gen != _generation) throw const _StaleRun();
  }

  /// The ONE place a storage bridge call is made (guard test: no other
  /// bridge access in this file). Every call has the timeout.
  Future<T> _call<T>(Future<T> Function(StorageBridge b) f) async =>
      await f(_bridge()).timeout(_timeout);

  /// Debug builds only; codes and counts, never a name or a URI.
  static void _log(String code) {
    if (kDebugMode) debugPrint('[auto-backup] $code');
  }

  Future<void> _run(int gen) async {
    if (!await BackupPrefs.readEnabled()) return;
    final folder = await BackupPrefs.readFolderUri();
    if (folder == null) return; // switched on, no folder chosen yet
    if (await BackupPrefs.readPaused()) return; // only "choose folder again" clears this

    final count = (await BackupPrefs.readSinceCount()) + 1;
    await BackupPrefs.writeSinceCount(count);
    if (count < await BackupPrefs.readEveryN()) return;

    try {
      if (!await _call((b) => b.hasWriteGrant(folder))) {
        _alive(gen);
        await _pause();
        return;
      }
      _alive(gen);
      final startedAt = _now();
      final bytes = await _export().timeout(_timeout);
      _alive(gen);
      final created = await _call((b) => b.createFile(folder, fileNameFor(startedAt), bytes));
      _alive(gen);
      final files = await _listOrNull(folder);
      final mine = files?.where((f) => f.uri == created);
      if (mine != null && mine.isNotEmpty && mine.first.size != bytes.length) {
        await _deleteQuietly(created);
        throw const StorageException(StorageErrorCode.io, 'size mismatch');
      }
      _alive(gen);
      final written = [...await BackupPrefs.readWrittenUris(), created];
      await BackupPrefs.writeSinceCount(0);
      await BackupPrefs.writeFailCount(0);
      await BackupPrefs.writeLastAt(startedAt);
      await BackupPrefs.writeWrittenUris(written);
      if (files != null) await _prune(files, created, written, gen);
    } on _StaleRun {
      _log('stale run stopped');
    } on StorageException catch (e) {
      if (gen != _generation) return;
      if (e.code == StorageErrorCode.grantLost) {
        await _pause();
      } else {
        await _failed();
      }
    } catch (_) {
      if (gen != _generation) return;
      await _failed();
    }
  }

  Future<List<FolderFile>?> _listOrNull(String folder) async {
    try {
      return await _call((b) => b.listFiles(folder));
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteQuietly(String uri) async {
    try {
      await _call((b) => b.deleteFile(uri));
    } catch (_) {}
  }

  Future<void> _pause() async {
    await BackupPrefs.writePaused(true);
    _notify(pausedMessage);
    try {
      await _inbox.add(Notice(
        tag: Notice.backupPausedTag,
        notes: '',
        receivedAt: _now(),
        backupPaused: true,
      ));
    } catch (_) {
      // The notice is a courtesy; it never blocks saving an entry.
    }
  }

  Future<void> _clearNotice() async {
    try {
      await _inbox.remove(Notice.backupPausedTag);
    } catch (_) {}
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
  Future<void> _prune(List<FolderFile> listing, String justWritten, List<String> written, int gen) async {
    try {
      final keepK = await BackupPrefs.readKeepK();
      final mine = written.toSet();
      final eligible = listing.where((f) => mine.contains(f.uri) && autoFileName.hasMatch(f.name)).toList()
        ..sort((a, b) => _sortKey(b.name).compareTo(_sortKey(a.name)));
      final gone = <String>{};
      for (final f in eligible.skip(keepK)) {
        if (f.uri == justWritten) continue;
        _alive(gen);
        try {
          await _call((b) => b.deleteFile(f.uri));
          gone.add(f.uri);
        } on _StaleRun {
          rethrow;
        } catch (_) {}
      }
      // Forget files that are gone, whether we deleted them or the user did.
      final present = listing.map((f) => f.uri).toSet();
      _alive(gen);
      await BackupPrefs.writeWrittenUris([
        for (final u in written)
          if (present.contains(u) && !gone.contains(u)) u,
      ]);
    } on _StaleRun {
      rethrow;
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
  /// Returns false if a pref could not be written (or the service was busy).
  /// With [decide] this is [changeFolder]'s full flow.
  Future<bool> useFolder(PickedFolder folder, {LeftoverDecider? decide}) async {
    final r = await changeFolder(folder, decide: decide);
    return r.ok && !r.busy;
  }

  /// Turns auto-backup off: releases the folder permission and clears the
  /// folder keys (enabled, paused, counter included). Files already written
  /// stay where they are unless [decide] answers delete.
  Future<bool> turnOff({LeftoverDecider? decide}) async {
    final r = await switchOff(decide: decide);
    return r.ok && !r.busy;
  }

  /// CB9 order, Choose folder. FIRST read the old folder URI, the old grant and
  /// the written list. Then, when [decide] is given and the old folder is
  /// another one: list it (fresh); a failed listing skips the question and
  /// keeps today's quiet release; otherwise ask ONCE (leftovers when there
  /// are any, and always the permission). Only then, with the service quiet,
  /// delete if asked to, write the new URI, clear the written list, set enabled
  /// and release the old grant (only if the answer says release, or the
  /// listing failed, or [decide] is null). Back, outside tap, null and a thrown
  /// callback are [LeftoverDecision.cancel]: nothing is deleted or released and
  /// the change goes on. The same URI as the old one asks nothing, deletes
  /// nothing and releases nothing.
  Future<FolderChangeResult> changeFolder(PickedFolder folder, {LeftoverDecider? decide}) async {
    final old = await BackupPrefs.readFolderUri();
    final written = await BackupPrefs.readWrittenUris();
    final other = old != null && old != folder.uri;

    var asked = false;
    var listingFailed = false;
    var decision = LeftoverDecision.cancel;
    LeftoverScan? scan;
    if (other && decide != null) {
      final grantHeld = await _hasGrantQuietly(old);
      scan = grantHeld ? await findLeftovers(old, writtenCount: written.length) : null;
      if (scan == null) {
        listingFailed = true;
      } else {
        asked = true;
        decision = await _ask(
          decide,
          LeftoverPrompt(leftovers: scan.count > 0 ? scan : null, askGrant: true, switchingOff: false),
        );
      }
    }

    if (!await _holdStill()) {
      return FolderChangeResult(ok: false, busy: true, writtenCount: written.length);
    }
    try {
      LeftoverDeleteResult? deleted;
      if (asked && scan!.count > 0 && decision.leftover == LeftoverChoice.delete) {
        deleted = await deleteLeftovers(old!, consented: true);
      }
      var ok = await BackupPrefs.writeFolderUri(folder.uri);
      ok = await BackupPrefs.writeFolderName(folder.name) && ok;
      ok = await BackupPrefs.writeSinceCount(0) && ok;
      ok = await BackupPrefs.writeFailCount(0) && ok;
      ok = await BackupPrefs.writeWrittenUris(const []) && ok;
      ok = await BackupPrefs.writePaused(false) && ok;
      ok = await BackupPrefs.writeEnabled(true) && ok;
      var released = false;
      if (other && (decide == null || listingFailed || decision.grant == GrantChoice.release)) {
        await _releaseQuietly(old);
        released = true;
      }
      await _clearNotice();
      _log('changeFolder asked=$asked found=${scan?.count ?? 0} released=$released');
      return FolderChangeResult(
        ok: ok,
        asked: asked,
        decision: decision,
        found: scan?.count ?? 0,
        deleted: deleted,
        grantReleased: released,
        listingFailed: listingFailed,
        writtenCount: written.length,
      );
    } finally {
      resume();
    }
  }

  /// CB9 order, switch-off. Reads the old URI and the written list first; asks
  /// the leftover question ONLY (no permission field) and only when [decide] is
  /// given and the old folder holds matching files (a failed listing or no
  /// files: no question); then, with the service quiet, deletes if asked to,
  /// clears the folder keys and releases the permission as today (also after a
  /// cancel).
  Future<FolderChangeResult> switchOff({LeftoverDecider? decide}) async {
    final old = await BackupPrefs.readFolderUri();
    final written = await BackupPrefs.readWrittenUris();

    var asked = false;
    var listingFailed = false;
    var decision = LeftoverDecision.cancel;
    LeftoverScan? scan;
    if (old != null && decide != null) {
      final grantHeld = await _hasGrantQuietly(old);
      scan = grantHeld ? await findLeftovers(old, writtenCount: written.length) : null;
      if (scan == null) {
        listingFailed = true;
      } else if (scan.count > 0) {
        asked = true;
        decision = await _ask(
          decide,
          LeftoverPrompt(leftovers: scan, askGrant: false, switchingOff: true),
        );
      }
    }

    if (!await _holdStill()) {
      return FolderChangeResult(ok: false, busy: true, writtenCount: written.length);
    }
    try {
      LeftoverDeleteResult? deleted;
      if (asked && decision.leftover == LeftoverChoice.delete) {
        deleted = await deleteLeftovers(old!, consented: true);
      }
      final ok = await BackupPrefs.clearAutoBackup();
      if (old != null) await _releaseQuietly(old);
      await _clearNotice();
      _log('switchOff asked=$asked found=${scan?.count ?? 0}');
      return FolderChangeResult(
        ok: ok,
        asked: asked,
        decision: decision,
        found: scan?.count ?? 0,
        deleted: deleted,
        grantReleased: old != null,
        listingFailed: listingFailed,
        writtenCount: written.length,
      );
    } finally {
      resume();
    }
  }

  /// Lists [folderUri] (fresh) and counts the files whose WHOLE name matches
  /// [autoFileName]. A manual `mmogo-backup-...` name or any other name is
  /// never counted; the written list is not an exclusion. Null = the folder
  /// could not be listed (grant lost, provider error, timeout).
  Future<LeftoverScan?> findLeftovers(String folderUri, {int writtenCount = 0}) async {
    final files = await _listOrNull(folderUri);
    if (files == null) return null;
    final mine = _matching(files);
    final dates = _dates(mine);
    return LeftoverScan(
      count: mine.length,
      oldest: dates.$1,
      newest: dates.$2,
      writtenCount: writtenCount,
    );
  }

  /// Deletes the leftovers of [folderUri] when [consented] is true, and does
  /// NOTHING (no bridge call) when it is false. It lists the folder again at
  /// delete time and deletes only the URIs of freshly listed files whose whole
  /// name matches [autoFileName]. One file failing does not stop the rest.
  Future<LeftoverDeleteResult> deleteLeftovers(String folderUri, {required bool consented}) async {
    if (!consented) return LeftoverDeleteResult.none;
    final files = await _listOrNull(folderUri);
    if (files == null) return const LeftoverDeleteResult(listingFailed: true);
    final mine = _matching(files);
    var deleted = 0;
    var failed = 0;
    for (final f in mine) {
      try {
        await _call((b) => b.deleteFile(f.uri));
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    final dates = _dates(mine);
    _log('deleteLeftovers deleted=$deleted failed=$failed');
    return LeftoverDeleteResult(deleted: deleted, failed: failed, oldest: dates.$1, newest: dates.$2);
  }

  List<FolderFile> _matching(List<FolderFile> files) =>
      [for (final f in files) if (autoFileName.hasMatch(f.name)) f];

  /// Oldest and newest date in the NAMES (local time).
  (DateTime?, DateTime?) _dates(List<FolderFile> files) {
    DateTime? oldest;
    DateTime? newest;
    for (final f in files) {
      final m = autoFileName.firstMatch(f.name);
      if (m == null) continue;
      final d = m.group(1)!;
      final t = m.group(2)!;
      final at = DateTime(
        int.parse(d.substring(0, 4)),
        int.parse(d.substring(4, 6)),
        int.parse(d.substring(6, 8)),
        int.parse(t.substring(0, 2)),
        int.parse(t.substring(2, 4)),
        int.parse(t.substring(4, 6)),
      );
      if (oldest == null || at.isBefore(oldest)) oldest = at;
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    return (oldest, newest);
  }

  Future<LeftoverDecision> _ask(LeftoverDecider decide, LeftoverPrompt prompt) async {
    try {
      return await decide(prompt) ?? LeftoverDecision.cancel;
    } catch (_) {
      return LeftoverDecision.cancel;
    }
  }

  Future<bool> _hasGrantQuietly(String uri) async {
    try {
      return await _call((b) => b.hasWriteGrant(uri));
    } catch (_) {
      return false;
    }
  }

  /// Holds the service still for the final write and release steps only (not
  /// across the user's dialog). False = another operation holds it or a run
  /// outlasted the bound; nothing is changed then.
  Future<bool> _holdStill() async {
    if (_blocked) return false;
    return quiesce();
  }

  Future<void> _releaseQuietly(String uri) async {
    try {
      await _call((b) => b.releaseGrant(uri));
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

/// Thrown inside a run the watchdog already wrote off.
class _StaleRun implements Exception {
  const _StaleRun();
}
