// B20: AutoBackupService against FakeStorageBridge (an in-memory folder that
// can revoke its grant and fail writes) and in-memory shared_preferences.
// Plain test(), no widgets, no real database (the export is a fake).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_storage_bridge.dart';

const _tree = 'content://tree/mmogo-backups';
const _picked = PickedFolder(uri: _tree, name: 'Documents / mmogo-backups');

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// A listing that reports a wrong size for every file (a provider that wrote
/// fewer bytes than it was given).
class _ShortWriteBridge extends FakeStorageBridge {
  @override
  Future<List<FolderFile>> listFiles(String treeUri) async => [
        for (final f in await super.listFiles(treeUri))
          FolderFile(name: f.name, uri: f.uri, size: f.size - 1, lastModified: f.lastModified),
      ];
}

class _NoDeleteBridge extends FakeStorageBridge {
  @override
  Future<void> deleteFile(String docUri) async => throw const StorageException(StorageErrorCode.io);
}

class _Env {
  _Env(this.bridge) {
    service = AutoBackupService(
      bridge: () => bridge,
      export: () async {
        exports++;
        final gate = exportGate;
        if (gate != null) await gate.future;
        if (exportError != null) throw exportError!;
        return _bytes('{"app":"mmogo","run":$exports}');
      },
      now: () => clock = clock.add(const Duration(seconds: 1)),
      notify: notices.add,
    );
  }

  final FakeStorageBridge bridge;
  late final AutoBackupService service;
  final notices = <String>[];
  int exports = 0;
  Object? exportError;
  Completer<void>? exportGate;
  DateTime clock = DateTime(2026, 9, 25, 9, 0, 0);

  List<FolderFile> get files => (bridge.folders[_tree] ?? {}).values.toList()..sort((a, b) => a.name.compareTo(b.name));
  List<String> get names => files.map((f) => f.name).toList();
  int get creates => bridge.calls.where((c) => c.startsWith('createFile')).length;

  Future<void> save([int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await service.onEntrySaved();
    }
  }
}

/// A set-up env: folder chosen through useFolder, [n] and [k] stored.
Future<_Env> _env({int n = 1, int k = 5, bool enabled = true, FakeStorageBridge? bridge}) async {
  SharedPreferences.setMockInitialValues({});
  final env = _Env(bridge ?? FakeStorageBridge());
  env.bridge.folderPicks.add(_picked);
  await env.bridge.pickFolder();
  await env.service.useFolder(_picked);
  await BackupPrefs.writeEveryN(n);
  await BackupPrefs.writeKeepK(k);
  if (!enabled) await BackupPrefs.writeEnabled(false);
  env.bridge.calls.clear();
  return env;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('disabled_is_inert: no counter, no bridge call, no export', () async {
    final env = await _env(enabled: false);
    await env.save(5);
    expect(await BackupPrefs.readSinceCount(), 0);
    expect(env.bridge.calls, isEmpty);
    expect(env.exports, 0);
  });

  test('switched_on_without_a_folder_is_inert', () async {
    SharedPreferences.setMockInitialValues({});
    final env = _Env(FakeStorageBridge());
    await BackupPrefs.writeEnabled(true);
    await env.save(3);
    expect(await BackupPrefs.readSinceCount(), 0);
    expect(env.bridge.calls, isEmpty);
    expect(env.exports, 0);
  });

  test('counter_waits_for_n_then_resets_and_records_last_good', () async {
    final env = await _env(n: 3);
    await env.save(2);
    expect(await BackupPrefs.readSinceCount(), 2);
    expect(env.creates, 0);
    expect(await BackupPrefs.readLastAt(), isNull);
    await env.save();
    expect(env.creates, 1);
    expect(await BackupPrefs.readSinceCount(), 0);
    expect(await BackupPrefs.readLastAt(), isNotNull);
    await env.save(3);
    expect(env.creates, 2);
  });

  test('n_saves_make_n_new_files (every entry, N = 1)', () async {
    final env = await _env(n: 1, k: 20);
    await env.save(4);
    expect(env.files.length, 4);
    expect(env.names.toSet().length, 4);
  });

  test('filename_pattern_no_personal_data', () async {
    final env = await _env(n: 1);
    await env.save();
    expect(env.names.single, matches(RegExp(r'^mmogo-auto-\d{8}-\d{6}\.json$')));
    expect(env.names.single, 'mmogo-auto-20260925-090001.json');
    expect(AutoBackupService.fileNameFor(DateTime(2026, 1, 2, 3, 4, 5)), 'mmogo-auto-20260102-030405.json');
  });

  test('never_opens_existing_file_for_write: a clash is renamed by the provider, both files keep their bytes', () async {
    final env = await _env(n: 1, k: 20);
    // Same second twice: the fake (like SAF) renames the second to "(1)".
    env.clock = DateTime(2026, 9, 25, 9, 0, 0).subtract(const Duration(seconds: 1));
    final fixed = DateTime(2026, 9, 25, 9, 0, 0);
    final service = AutoBackupService(
      bridge: () => env.bridge,
      export: () async => _bytes('{"app":"mmogo","n":${env.exports++}}'),
      now: () => fixed,
      notify: env.notices.add,
    );
    final old = env.bridge.seed(_tree, 'old-file.txt', _bytes('keep me'));
    await service.onEntrySaved();
    await service.onEntrySaved();
    expect(env.names, containsAll(['mmogo-auto-20260925-090000.json', 'mmogo-auto-20260925-090000 (1).json']));
    expect(env.bridge.bytesOf(old), _bytes('keep me'));
    // Only createFile ever writes: no other write-capable call exists on the bridge.
    expect(env.bridge.calls.where((c) => c.startsWith('createFile')).length, 2);
    final contents = env.files.where((f) => f.name.startsWith('mmogo-auto')).map((f) => utf8.decode(env.bridge.bytesOf(f.uri)!));
    expect(contents.toSet().length, 2);
  });

  test('prune_keeps_k_newest_matching_only', () async {
    final env = await _env(n: 1, k: 2);
    await env.save(5);
    expect(env.names, ['mmogo-auto-20260925-090004.json', 'mmogo-auto-20260925-090005.json']);
  });

  test('create_then_prune_order: the new file exists before anything is deleted', () async {
    final env = await _env(n: 1, k: 2);
    await env.save(2);
    env.bridge.calls.clear();
    await env.save();
    final firstCreate = env.bridge.calls.indexWhere((c) => c.startsWith('createFile'));
    final firstDelete = env.bridge.calls.indexWhere((c) => c.startsWith('deleteFile'));
    expect(firstCreate, greaterThanOrEqualTo(0));
    expect(firstDelete, greaterThan(firstCreate));
  });

  test('prune_ignores_other_files_and_unmarked_names', () async {
    final env = await _env(n: 1, k: 2);
    final foreign = env.bridge.seed(_tree, 'notes.txt', _bytes('hello'));
    // Looks like an auto file by NAME but this app never wrote it.
    final lookalike = env.bridge.seed(_tree, 'mmogo-auto-20200101-000000.json', _bytes('{"app":"other"}'));
    final nearMiss = env.bridge.seed(_tree, 'mmogo-auto-2026.json', _bytes('x'));
    await env.save(5);
    expect(env.bridge.bytesOf(foreign), _bytes('hello'));
    expect(env.bridge.bytesOf(lookalike), isNotNull);
    expect(env.bridge.bytesOf(nearMiss), isNotNull);
    expect(env.names.where((n) => RegExp(r'^mmogo-auto-2026092').hasMatch(n)).length, 2);
  });

  test('prune_never_deletes_manual_mmogo_backup_files (even with the marker, older than everything)', () async {
    final env = await _env(n: 1, k: 2);
    final manual = env.bridge.seed(
      _tree,
      'mmogo-backup-20200101-000000.json',
      _bytes('{"app":"mmogo","format_version":1}'),
      modified: DateTime(2020),
    );
    await env.save(6);
    expect(env.bridge.bytesOf(manual), isNotNull);
    expect(env.bridge.calls.where((c) => c == 'deleteFile:$manual'), isEmpty);
  });

  test('prune_sorts_by_timestamp_in_the_name_not_by_modified_time', () async {
    final env = await _env(n: 1, k: 2);
    await env.save(2);
    // Make the oldest-named file look the most recently modified.
    final oldest = env.files.first;
    env.bridge.folders[_tree]![oldest.uri] =
        FolderFile(name: oldest.name, uri: oldest.uri, size: oldest.size, lastModified: DateTime(2099));
    await env.save();
    expect(env.names, ['mmogo-auto-20260925-090002.json', 'mmogo-auto-20260925-090003.json']);
  });

  test('files_of_a_previous_folder_or_a_deleted_file_are_never_pruned_later', () async {
    final env = await _env(n: 1, k: 2);
    await env.save(2);
    // The user deletes one of our files by hand; the next prune copes.
    await env.bridge.deleteFile(env.files.first.uri);
    await env.save(2);
    expect(env.files.length, 2);
  });

  test('prune_error_is_ignored: a failing delete does not fail the backup', () async {
    final env = await _env(n: 1, k: 2, bridge: _NoDeleteBridge());
    await env.save(4);
    expect(env.files.length, 4, reason: 'nothing could be pruned; an extra file is harmless');
    expect(await BackupPrefs.readFailCount(), 0);
    expect(await BackupPrefs.readPaused(), isFalse);
    expect(await BackupPrefs.readSinceCount(), 0);
  });

  test('prune_after_create_never_reduces_count_on_failure: a failed write deletes nothing', () async {
    final env = await _env(n: 1, k: 2);
    await env.save(2);
    final before = env.names;
    env.bridge.failWrites = true;
    await env.save();
    expect(env.names, before);
    expect(env.bridge.calls.where((c) => c.startsWith('deleteFile')), isEmpty);
  });

  test('failed_write_keeps_count_then_pauses_after_two', () async {
    final env = await _env(n: 1);
    env.bridge.failWrites = true;
    await env.save();
    expect(await BackupPrefs.readSinceCount(), 1, reason: 'the count is kept so the next entry retries');
    expect(await BackupPrefs.readFailCount(), 1);
    expect(await BackupPrefs.readPaused(), isFalse);
    expect(await BackupPrefs.readLastAt(), isNull, reason: 'last good backup only after a verified write');
    expect(env.notices, isEmpty);
    await env.save();
    expect(await BackupPrefs.readSinceCount(), 2);
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(env.notices, [AutoBackupService.pausedMessage]);
    final callsAfterPause = env.bridge.calls.length;
    await env.save(3);
    expect(env.bridge.calls.length, callsAfterPause, reason: 'paused: no retry, no bridge call');
    expect(env.notices.length, 1, reason: 'the snackbar is shown once');
  });

  test('a_success_resets_the_failure_count (failures must be consecutive)', () async {
    final env = await _env(n: 1);
    env.bridge.failWrites = true;
    await env.save();
    env.bridge.failWrites = false;
    await env.save();
    expect(await BackupPrefs.readFailCount(), 0);
    expect(await BackupPrefs.readSinceCount(), 0);
    env.bridge.failWrites = true;
    await env.save();
    expect(await BackupPrefs.readPaused(), isFalse);
  });

  test('export_failure_counts_like_a_write_failure', () async {
    final env = await _env(n: 1);
    env.exportError = StateError('db busy');
    await env.save();
    expect(await BackupPrefs.readFailCount(), 1);
    expect(env.creates, 0);
    expect(await BackupPrefs.readSinceCount(), 1);
  });

  test('revoked_grant_sets_paused_and_writes_nothing', () async {
    final env = await _env(n: 1);
    env.bridge.revokeGrant(_tree);
    final seen = <bool>[];
    BackupPrefs.pausedNotifier.addListener(() => seen.add(BackupPrefs.pausedNotifier.value));
    await env.save();
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(env.creates, 0);
    expect(env.exports, 0);
    expect(env.notices, [AutoBackupService.pausedMessage]);
    expect(seen, contains(true));
    BackupPrefs.pausedNotifier.value = false;
  });

  test('grant_lost_during_the_write_also_pauses', () async {
    final env = await _env(n: 1);
    env.exportGate = Completer<void>();
    final run = env.service.onEntrySaved();
    await Future<void>.delayed(Duration.zero);
    while (env.exports == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    env.bridge.revokeGrant(_tree); // revoked after the grant check, before createFile
    env.exportGate!.complete();
    await run;
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(env.files, isEmpty);
  });

  test('a_size_mismatch_after_the_write_is_a_failure: file removed, no last good, count kept', () async {
    final env = await _env(n: 1, bridge: _ShortWriteBridge());
    await env.save();
    expect(env.files, isEmpty);
    expect(await BackupPrefs.readLastAt(), isNull);
    expect(await BackupPrefs.readSinceCount(), 1);
    expect(await BackupPrefs.readFailCount(), 1);
  });

  test('failure_isolation: onEntrySaved never throws, whatever goes wrong', () async {
    final env = await _env(n: 1);
    env.exportError = const FileSystemException('disk full');
    await env.service.onEntrySaved();
    env.exportError = null;
    final angry = AutoBackupService(
      bridge: () => throw StateError('no bridge'),
      export: () async => throw StateError('no export'),
    );
    await angry.onEntrySaved(); // must complete normally
  });

  test('running_guard: an entry saved during a run is counted afterwards, not run twice', () async {
    final env = await _env(n: 1);
    env.exportGate = Completer<void>();
    final first = env.service.onEntrySaved();
    while (env.exports == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    await env.service.onEntrySaved(); // returns at once: a run is in progress
    expect(env.exports, 1);
    env.exportGate!.complete();
    await first;
    expect(env.creates, 1);
    expect(await BackupPrefs.readSinceCount(), 1, reason: 'the second entry counts toward the next backup');
  });

  test('useFolder_starts_fresh: clears paused, counters and the written list; releases the old folder', () async {
    final env = await _env(n: 5);
    await BackupPrefs.writePaused(true);
    await BackupPrefs.writeSinceCount(4);
    await BackupPrefs.writeFailCount(2);
    env.bridge.folderPicks.add(const PickedFolder(uri: 'content://tree/other', name: 'Other'));
    final other = (await env.bridge.pickFolder())!;
    final ok = await env.service.useFolder(other);
    expect(ok, isTrue);
    expect(await BackupPrefs.readFolderUri(), 'content://tree/other');
    expect(await BackupPrefs.readFolderName(), 'Other');
    expect(await BackupPrefs.readPaused(), isFalse);
    expect(await BackupPrefs.readSinceCount(), 0);
    expect(await BackupPrefs.readFailCount(), 0);
    expect(await BackupPrefs.readWrittenUris(), isEmpty);
    expect(await BackupPrefs.readEnabled(), isTrue);
    expect(env.bridge.calls, contains('releaseGrant:$_tree'));
  });

  test('useFolder_with_the_same_folder_keeps_its_grant', () async {
    final env = await _env(n: 5);
    await env.service.useFolder(_picked);
    expect(env.bridge.calls.where((c) => c.startsWith('releaseGrant')), isEmpty);
  });

  test('turning_off_releases_grant_and_clears_the_folder_keys but keeps N, K and the files', () async {
    final env = await _env(n: 1, k: 7);
    await env.save(2);
    final before = env.names;
    await env.service.turnOff();
    expect(env.bridge.calls, contains('releaseGrant:$_tree'));
    expect(await BackupPrefs.readEnabled(), isFalse);
    expect(await BackupPrefs.readFolderUri(), isNull);
    expect(await BackupPrefs.readFolderName(), isNull);
    expect(await BackupPrefs.readPaused(), isFalse);
    expect(await BackupPrefs.readSinceCount(), 0);
    expect(await BackupPrefs.readWrittenUris(), isEmpty);
    expect(await BackupPrefs.readKeepK(), 7);
    expect(env.names, before);
  });

  test('releaseUnused_gives_back_a_declined_folder_but_never_the_one_in_use', () async {
    final env = await _env(n: 5);
    await env.service.releaseUnused(const PickedFolder(uri: 'content://tree/declined', name: 'x'));
    expect(env.bridge.calls, contains('releaseGrant:content://tree/declined'));
    env.bridge.calls.clear();
    await env.service.releaseUnused(_picked);
    expect(env.bridge.calls, isEmpty);
  });

  test('entry_edit_delete_undo_restore_do_not_count / counter_incremented_from_add_save_not_from_dao_insert', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('onEntrySaved')) hits.add(f.path.replaceAll(r'\', '/'));
    }
    hits.sort();
    expect(hits, ['lib/data/backup/auto_backup_service.dart', 'lib/ui/screens/add/add_screen.dart']);
    final add = File('lib/ui/screens/add/add_screen.dart').readAsStringSync();
    expect(add.indexOf('onEntrySaved'), greaterThan(add.indexOf('await TransactionDao.insert(db, input)')));
    expect(File('lib/data/db/transaction_dao.dart').readAsStringSync(), isNot(contains('AutoBackup')));
  });
}
