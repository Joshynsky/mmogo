// B52: pausing auto-backup tells the user in the Updates inbox, picking a
// folder again (or turning it off) removes that notice, and a bridge call that
// never returns counts as a failed write instead of leaving the run stuck.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_storage_bridge.dart';

const _tree = 'content://tree/mmogo-backups';
const _picked = PickedFolder(uri: _tree, name: 'Documents / mmogo-backups');

/// A bridge whose createFile never answers.
class _HangingBridge extends FakeStorageBridge {
  @override
  Future<String> createFile(String treeUri, String name, Uint8List bytes) => Completer<String>().future;
}

Future<(AutoBackupService, FakeStorageBridge, UpdatesInbox)> _rig([FakeStorageBridge? b]) async {
  SharedPreferences.setMockInitialValues({});
  final bridge = b ?? FakeStorageBridge();
  final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
  final service = AutoBackupService(
    bridge: () => bridge,
    export: () async => Uint8List.fromList(utf8.encode('{"app":"mmogo"}')),
    now: () => DateTime(2026, 10, 2, 9, 0, 0),
    notify: (_) {},
    inbox: inbox,
    bridgeTimeout: const Duration(milliseconds: 50),
  );
  bridge.folderPicks.add(_picked);
  await bridge.pickFolder();
  await service.useFolder(_picked);
  await BackupPrefs.writeEveryN(1);
  return (service, bridge, inbox);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a lost grant pauses and adds one unread backup-paused notice', () async {
    final (service, bridge, inbox) = await _rig();
    bridge.revokeGrant(_tree);
    await service.onEntrySaved();
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(inbox.notices.map((n) => n.tag), [Notice.backupPausedTag]);
    expect(inbox.notices.single.backupPaused, isTrue);
    expect(inbox.notices.single.read, isFalse);
    expect(inbox.unreadCount.value, 1);
  });

  test('useFolder removes the notice', () async {
    final (service, bridge, inbox) = await _rig();
    bridge.revokeGrant(_tree);
    await service.onEntrySaved();
    expect(inbox.notices, hasLength(1));
    bridge.revoked.clear();
    await service.useFolder(_picked);
    expect(inbox.notices, isEmpty);
    expect(inbox.unreadCount.value, 0);
  });

  test('turnOff removes the notice', () async {
    final (service, bridge, inbox) = await _rig();
    bridge.revokeGrant(_tree);
    await service.onEntrySaved();
    await service.turnOff();
    expect(inbox.notices, isEmpty);
  });

  test('a pause that fails to add the notice still pauses and never throws', () async {
    final (service, bridge, _) = await _rig();
    final broken = AutoBackupService(
      bridge: () => bridge,
      notify: (_) {},
      inbox: _ThrowingInbox(),
    );
    bridge.revokeGrant(_tree);
    await broken.onEntrySaved();
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(service, isNotNull);
  });

  test('a bridge call that never returns counts as a failed write; two in a row pause', () async {
    final (service, _, inbox) = await _rig(_HangingBridge());
    await service.onEntrySaved();
    expect(await BackupPrefs.readFailCount(), 1);
    expect(await BackupPrefs.readPaused(), isFalse);
    expect(inbox.notices, isEmpty);
    await service.onEntrySaved(); // the run is not stuck: it ran again
    expect(await BackupPrefs.readPaused(), isTrue);
    expect(inbox.notices.single.backupPaused, isTrue);
  });
}

class _ThrowingInbox extends UpdatesInbox {
  @override
  Future<bool> add(Notice notice) => throw StateError('boom');

  @override
  Future<bool> remove(String tag) => throw StateError('boom');
}
