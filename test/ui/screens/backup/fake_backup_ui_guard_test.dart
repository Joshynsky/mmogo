// 0.1.2 S10b (A12): useFakeBackupUi() makes every DEFAULT that would reach a
// real service throw, and no test pumps the Backup page without it. The scans
// read the test sources; the guard tests run the defaults under the guard.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/backup_ui_seams.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/backup_page_harness.dart';
import '../../../support/fake_backup_ui.dart';
import '../../../support/fake_delete_data.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    useFakeDeleteData();
  });

  group('under the guard', () {
    test('the guard is off outside a test that asks for it, and on after useFakeBackupUi()', () {
      expect(BackupUiSeams.guarded, isFalse);
      final ui = useFakeBackupUi();
      expect(BackupUiSeams.guarded, isTrue);
      expect(StorageBridge.instance, same(ui.bridge));
      expect(AutoBackupService.instance, same(ui.auto));
    });

    test('the real export, the share sheet and the temp files are blocked', () async {
      useFakeBackupUi();
      // The default export / share / temp directory would touch the real database, the OS and the disk.
      expect(await BackupExportFlow().execute(), isA<BackupFailed>());
      await expectLater(const DeviceTempFiles().write('x.json', Uint8List.fromList([1, 2, 3])), throwsStateError);
      expect(() => BackupUiSeams.ensureReal('anything'), throwsStateError);
    });

    testWidgets('a Backup page with no injected restore flow cannot restore for real: Restore ends in the failure dialog', (t) async {
      final ui = useFakeBackupUi();
      ui.bridge.filePicks.add(PickedFile(name: 'b.json', bytes: Uint8List.fromList([1, 2, 3])));
      await pumpBackupPage(t); // no restoreFlow, no restoreService: the defaults
      await tapKey(t, 'restoreButton');
      expect(find.byKey(const Key('restoreFailedDialog')), findsOneWidget, reason: 'the real RestoreService was not built');
      expect(find.byKey(const Key('restoreMergeDialog')), findsNothing);
    });

    test('the guard is switched off again after the test (tearDown)', () {
      expect(BackupUiSeams.guarded, isFalse);
    });
  });

  group('scans of the test sources', () {
    List<File> testFiles() => [
      for (final f in Directory('test').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];
    bool isSelf(File f) => f.path.replaceAll('\\', '/').endsWith('backup/fake_backup_ui_guard_test.dart');

    test('every test that pumps the Backup page (BackupScreen or pumpBackupPage) also calls useFakeBackupUi()', () {
      final bad = <String>[];
      for (final f in testFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (isSelf(f) || p.endsWith('support/backup_page_harness.dart') || p.endsWith('support/fake_backup_ui.dart')) continue;
        final src = f.readAsStringSync();
        final pumps = RegExp(r'\bBackupScreen\(|\bpumpBackupPage\(').hasMatch(src);
        if (pumps && !src.contains('useFakeBackupUi(')) bad.add(p);
      }
      expect(bad, isEmpty, reason: 'pump the Backup page without the guard: $bad');
    });

    test('no test constructs the real RestoreService or a SafetyCopyStore without a folder', () {
      final bad = <String>[];
      for (final f in testFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p.startsWith('test/data/') || isSelf(f) || p.endsWith('static/s10a_test_safety_scan_test.dart')) continue;
        final src = f.readAsStringSync();
        if (RegExp(r'\bRestoreService\(').hasMatch(src)) bad.add('$p: RestoreService constructed');
        if (RegExp(r'\bSafetyCopyStore\(\s*\)').hasMatch(src)) bad.add('$p: bare SafetyCopyStore');
      }
      expect(bad, isEmpty, reason: '$bad');
    });

    test('no UI test builds an AutoBackupService without an injected bridge', () {
      final bad = <String>[];
      for (final f in testFiles()) {
        final p = f.path.replaceAll('\\', '/');
        if (p.startsWith('test/data/') || isSelf(f) || p.endsWith('static/s10a_test_safety_scan_test.dart')) continue;
        for (final m in RegExp(r'\bAutoBackupService\(([^)]*)\)').allMatches(f.readAsStringSync())) {
          if (!m.group(1)!.contains('bridge:')) bad.add('$p: ${m.group(0)}');
        }
      }
      // restart_scope_test builds one with notify only and never runs a folder operation on it (S9b-1).
      expect(bad.where((b) => !b.startsWith('test/ui/restart_scope_test.dart')), isEmpty, reason: '$bad');
    });
  });
}
