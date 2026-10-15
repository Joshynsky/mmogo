// 0.1.2 S9b-1: AutoBackupService.quiesce / resume (Delete data holds the
// service still). Fake export and a fake bridge; no real database or folder.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_storage_bridge.dart';

const _tree = 'content://tree/invented';

void main() {
  late FakeStorageBridge bridge;
  late int exports;
  Completer<void>? hold;
  Object? exportError;

  AutoBackupService make() => AutoBackupService(
        bridge: () => bridge,
        export: () async {
          exports++;
          if (hold != null) await hold!.future;
          if (exportError != null) throw exportError!;
          return Uint8List.fromList([1, 2]);
        },
        notify: (_) {},
      );

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'auto_backup_enabled': true,
      'auto_backup_folder_uri': _tree,
      'auto_backup_every_n': 1,
      'auto_backup_since_count': 0,
    });
    bridge = FakeStorageBridge()..folders[_tree] = {};
    exports = 0;
    hold = null;
    exportError = null;
  });

  test('idle: quiesce is true at once; blocked until resume; onEntrySaved does nothing meanwhile', () async {
    final s = make();
    expect(await s.quiesce(), isTrue);
    expect(s.isBlocked, isTrue);
    await s.onEntrySaved();
    await s.onEntrySaved();
    expect(exports, 0);
    expect((await SharedPreferences.getInstance()).getInt('auto_backup_since_count'), 0);
    s.resume();
    expect(s.isBlocked, isFalse);
    await s.onEntrySaved();
    expect(exports, 1);
  });

  test('a run in flight: quiesce waits for it (true), the run is not cut short', () async {
    hold = Completer<void>();
    final s = make();
    final run = s.onEntrySaved();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    var quiet = false;
    final q = s.quiesce(bound: const Duration(seconds: 3)).then((v) => quiet = v);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(quiet, isFalse);
    hold!.complete();
    await run;
    expect(await q, isTrue);
    expect(bridge.folders[_tree]!.length, 1, reason: 'the run finished its file');
  });

  test('a run that outlasts the bound: quiesce is false and the service is not left blocked', () async {
    hold = Completer<void>();
    final s = make();
    final run = s.onEntrySaved();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await s.quiesce(bound: const Duration(milliseconds: 60)), isFalse);
    expect(s.isBlocked, isFalse);
    hold!.complete();
    await run;
  });

  test('a run that fails still ends the wait (the idle signal is never left hanging)', () async {
    exportError = StateError('disk');
    final s = make();
    await s.onEntrySaved();
    expect(await s.quiesce(bound: const Duration(milliseconds: 200)), isTrue);
  });

  test('resume forgets entries counted as queued', () async {
    hold = Completer<void>();
    final s = make();
    final run = s.onEntrySaved();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await s.onEntrySaved(); // queued behind the run
    s.resume();
    hold!.complete();
    await run;
    // The queued entry was forgotten by resume() before _countQueued ran.
    expect((await SharedPreferences.getInstance()).getInt('auto_backup_since_count'), 0);
  });

  test('the device-only keys are not in the backup allowlist', () {
    final inFile = kBackupSettingSpecs.map((s) => s.prefsKey).toSet();
    expect(inFile, hasLength(11));
    for (final k in [kPendingEntriesKey, kResetPendingKey, kPhoneMergeReportKey, 'recipient_types_v1']) {
      expect(inFile.contains(k), isFalse, reason: k);
    }
  });
}
