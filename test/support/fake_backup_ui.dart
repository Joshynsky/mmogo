// S10b (A12): the guard for tests that pump the Backup page. After
// useFakeBackupUi() any DEFAULT that would reach the real restore service, the
// real backup export, the share sheet or the temp-file directory throws, the
// storage bridge is a FakeStorageBridge, and the auto-backup singleton is a
// service built on that bridge (mock prefs: the test sets them). Same idea as
// useFakeDeleteData().
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/screens/backup/backup_ui_seams.dart';

import 'fake_storage_bridge.dart';

class FakeBackupUi {
  FakeBackupUi(this.bridge, this.auto, this.notices);

  final FakeStorageBridge bridge;
  final AutoBackupService auto;
  final List<String> notices;
}

/// Call in `setUp`. Undone in a tearDown.
FakeBackupUi useFakeBackupUi() {
  final bridge = FakeStorageBridge();
  final oldBridge = StorageBridge.instance;
  final oldAuto = AutoBackupService.instance;
  final notices = <String>[];
  final auto = AutoBackupService(
    bridge: () => bridge,
    export: () async => Uint8List.fromList([123, 125]),
    notify: notices.add,
    inbox: UpdatesInbox(installedVersion: () => '0.1.2'),
  );
  StorageBridge.instance = bridge;
  AutoBackupService.instance = auto;
  BackupUiSeams.guarded = true;
  addTearDown(() {
    BackupUiSeams.guarded = false;
    StorageBridge.instance = oldBridge;
    AutoBackupService.instance = oldAuto;
  });
  return FakeBackupUi(bridge, auto, notices);
}
