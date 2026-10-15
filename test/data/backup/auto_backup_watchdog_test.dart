// S10a (A1a, addendum H): a hanging bridge never leaves a run stuck. Every
// bridge call is wrapped, a whole run has a deadline with a generation token,
// the deadline also completes `_idle`, and a stale run writes nothing. The
// guard tests scan the source. FakeStorageBridge and mock prefs only.
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

const _tree = 'content://tree/watchdog';
const _picked = PickedFolder(uri: _tree, name: 'Folder');

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

StorageBridge? _savedBridge;
AutoBackupService? _savedService;

Future<(AutoBackupService, FakeStorageBridge)> _make({
  Duration bridgeTimeout = const Duration(milliseconds: 60),
  Duration runDeadline = const Duration(seconds: 30),
  Future<Uint8List> Function()? export,
}) async {
  SharedPreferences.setMockInitialValues({});
  final bridge = FakeStorageBridge();
  final service = AutoBackupService(
    bridge: () => bridge,
    export: export ?? () async => _b('{"app":"mmogo"}'),
    notify: (_) {},
    bridgeTimeout: bridgeTimeout,
    runDeadline: runDeadline,
  );
  bridge.folderPicks.add(_picked);
  await bridge.pickFolder();
  await service.useFolder(_picked);
  await BackupPrefs.writeEveryN(1);
  await BackupPrefs.writeKeepK(5);
  bridge.calls.clear();
  return (service, bridge);
}

String _stripComments(String src) => [
      for (final l in src.split('\n'))
        if (!l.trimLeft().startsWith('//')) l.replaceFirst(RegExp(r'\s//.*$'), ''),
    ].join('\n');

void main() {
  setUp(() {
    _savedBridge = StorageBridge.instance;
    _savedService = AutoBackupService.instance;
  });
  tearDown(() {
    StorageBridge.instance = _savedBridge!;
    AutoBackupService.instance = _savedService!;
    SharedPreferences.setMockInitialValues({});
  });

  group('a hanging bridge call clears _running (per-call timeout)', () {
    for (final method in ['hasWriteGrant', 'createFile', 'listFiles']) {
      test('hang on $method: the run ends and the next entry starts a new run', () async {
        final (service, bridge) = await _make();
        bridge.hangOn.add(method);
        await service.onEntrySaved().timeout(const Duration(seconds: 5));
        if (method == 'listFiles') {
          // A hung listing is a quiet miss (no prune), not a failed write.
          expect(await BackupPrefs.readFailCount(), 0);
        } else {
          expect(await BackupPrefs.readFailCount(), 1);
        }
        final before = bridge.calls.where((c) => c.startsWith('hasWriteGrant')).length;
        await service.onEntrySaved().timeout(const Duration(seconds: 5));
        expect(bridge.calls.where((c) => c.startsWith('hasWriteGrant')).length, before + 1,
            reason: '_running was cleared, a new run began');
        expect(await service.quiesce(bound: const Duration(seconds: 1)), isTrue);
        service.resume();
      });
    }

    test('hang on deleteFile (prune) and releaseGrant (change of folder) ends too', () async {
      final (service, bridge) = await _make();
      await BackupPrefs.writeKeepK(1);
      await service.onEntrySaved(); // file 1
      bridge.hangOn.add('deleteFile');
      await service.onEntrySaved().timeout(const Duration(seconds: 5));
      await service.onEntrySaved().timeout(const Duration(seconds: 5));
      bridge.hangOn
        ..clear()
        ..add('releaseGrant');
      bridge.folderPicks.add(const PickedFolder(uri: 'content://tree/other', name: 'Other'));
      final other = (await bridge.pickFolder())!;
      expect(await service.useFolder(other).timeout(const Duration(seconds: 5)), isTrue);
      expect(await BackupPrefs.readFolderUri(), other.uri);
    });
  });

  group('whole-run deadline with a generation token', () {
    test('the deadline fires although every call is below its own timeout, and completes _idle',
        () async {
      final (service, bridge) = await _make(
        bridgeTimeout: const Duration(hours: 1),
        runDeadline: const Duration(milliseconds: 80),
      );
      bridge.hangOn.add('hasWriteGrant');
      final sw = Stopwatch()..start();
      await service.onEntrySaved().timeout(const Duration(seconds: 5));
      expect(sw.elapsedMilliseconds, lessThan(3000));
      expect(await BackupPrefs.readFailCount(), 1, reason: 'a written-off run is a failed write');
      expect(await service.quiesce(bound: const Duration(seconds: 1)), isTrue,
          reason: '_idle was completed by the watchdog, quiesce is not kept waiting');
      service.resume();
    });

    test('a stale run that wakes up later writes nothing (no file, no prefs)', () async {
      final gate = Completer<Uint8List>();
      final (service, bridge) = await _make(
        bridgeTimeout: const Duration(hours: 1),
        runDeadline: const Duration(milliseconds: 80),
        export: () => gate.future,
      );
      await service.onEntrySaved().timeout(const Duration(seconds: 5));
      expect(await BackupPrefs.readFailCount(), 1);
      final sinceBefore = await BackupPrefs.readSinceCount();
      gate.complete(_b('{"app":"mmogo","late":true}'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(bridge.calls.where((c) => c.startsWith('createFile')), isEmpty,
          reason: 'the stale run stopped before creating a file');
      expect(await BackupPrefs.readWrittenUris(), isEmpty);
      expect(await BackupPrefs.readSinceCount(), sinceBefore);
      expect(await BackupPrefs.readFailCount(), 1, reason: 'the late wake-up did not count a second failure');
    });

    test('quiesceBound stays above the run deadline', () {
      expect(AutoBackupService.runDeadline, lessThan(AutoBackupService.quiesceBound));
    });
  });

  group('guards (source scans)', () {
    final src = _stripComments(File('lib/data/backup/auto_backup_service.dart').readAsStringSync());

    test('no bridge call outside _call(: one _bridge(), no `bridge.`, every bridge method inside _call', () {
      expect(RegExp(r'_bridge\(\)').allMatches(src).length, 1, reason: 'only inside _call');
      expect(RegExp(r'\bbridge\.').hasMatch(src), isFalse);
      for (final line in src.split('\n')) {
        if (RegExp(r'\bb\.(hasWriteGrant|releaseGrant|createFile|listFiles|deleteFile|pickFolder|pickFile|openUrl)\(')
            .hasMatch(line)) {
          expect(line.contains('_call('), isTrue, reason: 'bridge method outside _call: ${line.trim()}');
        }
      }
      expect(RegExp(r'StorageBridge\.instance').allMatches(src).length, 1, reason: 'the constructor default');
    });

    test('debug logging carries codes and counts only: no name, URI, folder or written list', () {
      final logs = [for (final l in src.split('\n')) if (l.contains('_log(')) l.trim()];
      expect(logs.length, greaterThan(3));
      const allowed = {'asked', 'released', 'scan?.count', 'deleted', 'failed'};
      for (final l in logs) {
        if (l.contains('void _log')) continue;
        for (final m in RegExp(r'\$\{?([A-Za-z_?.]+)').allMatches(l)) {
          expect(allowed.contains(m.group(1)), isTrue, reason: 'logged value not allowed: $l');
        }
        expect(RegExp(r'uri|\.name|written|folder\.', caseSensitive: false).hasMatch(l.replaceAll('changeFolder', '')),
            isFalse, reason: l);
      }
      expect(src.contains('if (kDebugMode) debugPrint'), isTrue, reason: 'debug builds only');
      expect(RegExp(r'\bprint\(').hasMatch(src), isFalse);
    });
  });
}
