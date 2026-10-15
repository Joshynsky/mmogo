// S10a (A4a, CB9, addendum E/F/G): leftover automatic backups in a folder the
// user stops using. FakeStorageBridge (in memory) and mock prefs only: no real
// folder, no real prefs. Every deleteFile is checked on `fake.calls`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_storage_bridge.dart';

const _old = 'content://tree/old';
const _new = 'content://tree/new';
const _newFolder = PickedFolder(uri: _new, name: 'New folder');

const _a1 = 'mmogo-auto-20260901-101500.json';
const _a2 = 'mmogo-auto-20260903-081000.json';
const _a3 = 'mmogo-auto-20260902-090000 (1).json';
const _manual = 'mmogo-backup-20260901-101500.json';
const _other = 'notes.txt';
const _nearMisses = [
  'mmogo-auto-20260901-101500.json.bak',
  'x-mmogo-auto-20260901-101500.json',
  'mmogo-auto-2026-101500.json',
  'MMOGO-AUTO-20260901-101500.json',
];

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

StorageBridge? _savedBridge;
AutoBackupService? _savedService;

class _E {
  _E(this.bridge) {
    service = AutoBackupService(
      bridge: () => bridge,
      export: () async => _b('{"app":"mmogo"}'),
      notify: (_) {},
      bridgeTimeout: const Duration(seconds: 5),
    );
  }
  final FakeStorageBridge bridge;
  late final AutoBackupService service;
  final uris = <String, String>{}; // name -> doc uri in the old folder

  List<String> get deletes => bridge.calls.where((c) => c.startsWith('deleteFile')).toList();
  List<String> get releases => bridge.calls.where((c) => c.startsWith('releaseGrant')).toList();
  List<String> namesIn(String tree) => [for (final f in (bridge.folders[tree] ?? {}).values) f.name];
}

/// The old folder is in use (prefs say so), holds [names], and [written] of
/// them are on the app's written list.
Future<_E> _env(List<String> names, {List<String> written = const [], bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({});
  final e = _E(FakeStorageBridge());
  e.bridge.folders[_old] = {};
  e.bridge.folders[_new] = {};
  for (final n in names) {
    e.uris[n] = e.bridge.seed(_old, n, _b('x'));
  }
  await BackupPrefs.writeFolderUri(_old);
  await BackupPrefs.writeFolderName('Old folder');
  await BackupPrefs.writeEnabled(enabled);
  await BackupPrefs.writeWrittenUris([for (final n in written) e.uris[n]!]);
  e.bridge.calls.clear();
  return e;
}

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

  group('findLeftovers (name pattern only, fresh listing)', () {
    test('counts only whole-name matches; manual, other and near-miss names never', () async {
      final e = await _env([_a1, _a2, _a3, _manual, _other, ..._nearMisses]);
      final scan = await e.service.findLeftovers(_old);
      expect(scan!.count, 3);
      expect(scan.oldest, DateTime(2026, 9, 1, 10, 15, 0));
      expect(scan.newest, DateTime(2026, 9, 3, 8, 10, 0));
      expect(e.deletes, isEmpty);
    });

    test('the written list is NOT an exclusion (and not a filter) but is carried', () async {
      final e = await _env([_a1, _a2, _manual], written: [_a1, _manual]);
      final written = await BackupPrefs.readWrittenUris();
      final scan = await e.service.findLeftovers(_old, writtenCount: written.length);
      expect(scan!.count, 2, reason: 'a1 and a2, whether or not a1 is on the written list');
      expect(scan.writtenCount, 2);
    });

    test('no matching file: count 0, no dates', () async {
      final e = await _env([_manual, _other]);
      final scan = await e.service.findLeftovers(_old);
      expect(scan!.count, 0);
      expect(scan.oldest, isNull);
    });

    test('a failed listing is null (not zero)', () async {
      final e = await _env([_a1]);
      e.bridge.failOn.add('listFiles');
      expect(await e.service.findLeftovers(_old), isNull);
    });
  });

  group('deleteLeftovers', () {
    test('not consented: no bridge call at all', () async {
      final e = await _env([_a1, _a2]);
      final r = await e.service.deleteLeftovers(_old, consented: false);
      expect(r.attempted, 0);
      expect(e.bridge.calls, isEmpty);
      expect(e.namesIn(_old), hasLength(2));
    });

    test('consented: re-lists first, deletes only fresh matching files, keeps manual and others',
        () async {
      final e = await _env([_a1, _a2, _manual, _other, ..._nearMisses]);
      final scanned = await e.service.findLeftovers(_old);
      expect(scanned!.count, 2);
      // The folder changes after the question: one leftover goes, a new one comes.
      e.bridge.folders[_old]!.remove(e.uris[_a1]);
      final late = e.bridge.seed(_old, 'mmogo-auto-20260910-120000.json', _b('y'));
      e.bridge.calls.clear();

      final r = await e.service.deleteLeftovers(_old, consented: true);
      expect(r.deleted, 2, reason: 'a2 and the one that arrived later');
      expect(r.failed, 0);
      expect(r.listingFailed, isFalse);
      expect(r.oldest, DateTime(2026, 9, 3, 8, 10, 0));
      expect(r.newest, DateTime(2026, 9, 10, 12, 0, 0));
      expect(e.bridge.calls.first, startsWith('listFiles'), reason: 'fresh list before any delete');
      expect(e.deletes, unorderedEquals(['deleteFile:${e.uris[_a2]}', 'deleteFile:$late']));
      expect(e.namesIn(_old), unorderedEquals([_manual, _other, ..._nearMisses]));
    });

    test('a manual backup whose URI is on the written list is still never deleted', () async {
      final e = await _env([_a1, _manual], written: [_manual]);
      await e.service.deleteLeftovers(_old, consented: true);
      expect(e.namesIn(_old), [_manual]);
    });

    test('one file failing: counted, the rest still deleted', () async {
      final e = await _env([_a1, _a2, _a3]);
      e.bridge.failDeleteFor.add(e.uris[_a2]!);
      final r = await e.service.deleteLeftovers(_old, consented: true);
      expect(r.deleted, 2);
      expect(r.failed, 1);
      expect(e.namesIn(_old), [_a2]);
    });

    test('a failed listing at delete time: nothing deleted, flagged', () async {
      final e = await _env([_a1]);
      e.bridge.failOn.add('listFiles');
      final r = await e.service.deleteLeftovers(_old, consented: true);
      expect(r.listingFailed, isTrue);
      expect(r.attempted, 0);
      expect(e.deletes, isEmpty);
    });
  });

  group('changeFolder (Choose folder), CB9 order', () {
    test('the old URI, grant and written list are read BEFORE the callback; writes come after',
        () async {
      final e = await _env([_a1, _a2, _manual], written: [_a1]);
      String? uriDuringAsk;
      List<String>? writtenDuringAsk;
      bool? enabledDuringAsk;
      var callsDuringAsk = <String>[];
      LeftoverPrompt? seen;
      final r = await e.service.changeFolder(_newFolder, decide: (p) async {
        seen = p;
        uriDuringAsk = await BackupPrefs.readFolderUri();
        writtenDuringAsk = await BackupPrefs.readWrittenUris();
        enabledDuringAsk = await BackupPrefs.readEnabled();
        callsDuringAsk = List.of(e.bridge.calls);
        expect(e.service.isBlocked, isFalse, reason: 'not held across the user\'s dialog');
        return const LeftoverDecision(leftover: LeftoverChoice.delete, grant: GrantChoice.release);
      });

      expect(uriDuringAsk, _old, reason: 'the new URI is not written yet');
      expect(writtenDuringAsk, hasLength(1), reason: 'the written list is not cleared yet');
      expect(enabledDuringAsk, isTrue);
      expect(callsDuringAsk.where((c) => c.startsWith('deleteFile') || c.startsWith('releaseGrant')), isEmpty,
          reason: 'nothing deleted or released before the answer');
      expect(callsDuringAsk.any((c) => c.startsWith('hasWriteGrant:$_old')), isTrue);
      expect(seen!.leftovers!.count, 2);
      expect(seen!.leftovers!.writtenCount, 1);
      expect(seen!.askGrant, isTrue);
      expect(seen!.switchingOff, isFalse);

      expect(r.ok, isTrue);
      expect(r.asked, isTrue);
      expect(r.deleted!.deleted, 2);
      expect(await BackupPrefs.readFolderUri(), _new);
      expect(await BackupPrefs.readWrittenUris(), isEmpty);
      expect(await BackupPrefs.readEnabled(), isTrue);
      final del = e.bridge.calls.lastIndexWhere((c) => c.startsWith('deleteFile'));
      final rel = e.bridge.calls.indexWhere((c) => c == 'releaseGrant:$_old');
      expect(del, isNonNegative);
      expect(rel, greaterThan(del), reason: 'Delete runs before the release');
      expect(e.namesIn(_old), [_manual]);
      expect(r.grantReleased, isTrue);
    });

    test('Keep (default) + release: no delete, grant released', () async {
      final e = await _env([_a1, _a2]);
      final r = await e.service.changeFolder(_newFolder,
          decide: (p) async => const LeftoverDecision(leftover: LeftoverChoice.keep, grant: GrantChoice.release));
      expect(e.deletes, isEmpty);
      expect(e.releases, ['releaseGrant:$_old']);
      expect(r.kept, 2);
      expect(r.deleted, isNull);
      expect(e.namesIn(_old), hasLength(2));
    });

    test('Delete + keep access: files deleted, nothing released', () async {
      final e = await _env([_a1, _a2]);
      final r = await e.service.changeFolder(_newFolder,
          decide: (p) async => const LeftoverDecision(leftover: LeftoverChoice.delete, grant: GrantChoice.keepAccess));
      expect(e.deletes, hasLength(2));
      expect(e.releases, isEmpty);
      expect(r.grantReleased, isFalse);
    });

    for (final cancel in <String, LeftoverDecider>{
      'null (outside tap / Back)': (p) async => null,
      'LeftoverDecision.cancel': (p) async => LeftoverDecision.cancel,
      'a thrown callback': (p) async => throw StateError('dialog crashed'),
    }.entries) {
      test('cancel path "${cancel.key}": keep + keep access, no delete, no release, the change continues',
          () async {
        final e = await _env([_a1, _a2]);
        final r = await e.service.changeFolder(_newFolder, decide: cancel.value);
        expect(e.deletes, isEmpty);
        expect(e.releases, isEmpty);
        expect(e.namesIn(_old), hasLength(2));
        expect(r.ok, isTrue);
        expect(r.decision, LeftoverDecision.cancel);
        expect(await BackupPrefs.readFolderUri(), _new, reason: 'the folder change goes on');
        expect(await BackupPrefs.readEnabled(), isTrue);
        expect(await BackupPrefs.readWrittenUris(), isEmpty);
      });
    }

    test('the same URI: no question, no list, no delete, no release', () async {
      final e = await _env([_a1]);
      var asked = false;
      final r = await e.service.changeFolder(const PickedFolder(uri: _old, name: 'Old folder'),
          decide: (p) async {
        asked = true;
        return null;
      });
      expect(asked, isFalse);
      expect(e.bridge.calls.where((c) => c.startsWith('deleteFile') || c.startsWith('releaseGrant') || c.startsWith('listFiles')),
          isEmpty);
      expect(r.ok, isTrue);
      expect(r.asked, isFalse);
    });

    test('zero leftovers: the leftover part is skipped, the permission question is still asked',
        () async {
      final e = await _env([_manual, _other]);
      LeftoverPrompt? seen;
      await e.service.changeFolder(_newFolder, decide: (p) async {
        seen = p;
        return const LeftoverDecision(leftover: LeftoverChoice.keep, grant: GrantChoice.release);
      });
      expect(seen, isNotNull);
      expect(seen!.leftovers, isNull);
      expect(seen!.askGrant, isTrue);
      expect(e.deletes, isEmpty);
      expect(e.releases, ['releaseGrant:$_old']);
    });

    test('a failed listing skips the question and keeps today\'s quiet release', () async {
      final e = await _env([_a1]);
      e.bridge.failOn.add('listFiles');
      var asked = false;
      final r = await e.service.changeFolder(_newFolder, decide: (p) async {
        asked = true;
        return LeftoverDecision.cancel;
      });
      expect(asked, isFalse);
      expect(r.listingFailed, isTrue);
      expect(e.deletes, isEmpty);
      expect(e.releases, ['releaseGrant:$_old']);
      expect(await BackupPrefs.readFolderUri(), _new);
    });

    test('a lost old grant is a failed listing: quiet release, no question', () async {
      final e = await _env([_a1]);
      e.bridge.revokeGrant(_old);
      var asked = false;
      final r = await e.service.changeFolder(_newFolder, decide: (p) async {
        asked = true;
        return null;
      });
      expect(asked, isFalse);
      expect(r.listingFailed, isTrue);
      expect(await BackupPrefs.readFolderUri(), _new);
    });

    test('without a callback it is today\'s behaviour (quiet release, no listing)', () async {
      final e = await _env([_a1, _a2]);
      expect(await e.service.useFolder(_newFolder), isTrue);
      expect(e.bridge.calls.any((c) => c.startsWith('listFiles')), isFalse);
      expect(e.deletes, isEmpty);
      expect(e.releases, ['releaseGrant:$_old']);
    });

    test('busy: held by another operation, nothing is changed and nothing is deleted', () async {
      final e = await _env([_a1]);
      expect(await e.service.quiesce(), isTrue);
      final r = await e.service.changeFolder(_newFolder,
          decide: (p) async => const LeftoverDecision(leftover: LeftoverChoice.delete, grant: GrantChoice.release));
      expect(r.busy, isTrue);
      expect(r.ok, isFalse);
      expect(e.deletes, isEmpty);
      expect(await BackupPrefs.readFolderUri(), _old);
      expect(e.service.isBlocked, isTrue, reason: 'the other holder keeps its hold');
      e.service.resume();
    });
  });

  group('switchOff (turn off), CB9', () {
    test('asks the leftover question only (no grant field); Delete runs before the release', () async {
      final e = await _env([_a1, _a2, _manual]);
      LeftoverPrompt? seen;
      String? uriDuringAsk;
      final r = await e.service.switchOff(decide: (p) async {
        seen = p;
        uriDuringAsk = await BackupPrefs.readFolderUri();
        return const LeftoverDecision(leftover: LeftoverChoice.delete, grant: GrantChoice.keepAccess);
      });
      expect(seen!.askGrant, isFalse);
      expect(seen!.switchingOff, isTrue);
      expect(seen!.leftovers!.count, 2);
      expect(uriDuringAsk, _old, reason: 'the folder is cleared after the answer');
      expect(r.deleted!.deleted, 2);
      expect(e.namesIn(_old), [_manual]);
      expect(await BackupPrefs.readFolderUri(), isNull);
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(e.releases, ['releaseGrant:$_old'], reason: 'released as today; the grant field is ignored');
      final del = e.bridge.calls.lastIndexWhere((c) => c.startsWith('deleteFile'));
      expect(e.bridge.calls.indexOf('releaseGrant:$_old'), greaterThan(del));
    });

    test('Keep and every cancel path: files stay, switch-off goes on and releases as today', () async {
      for (final answer in <LeftoverDecider>[
        (p) async => const LeftoverDecision(leftover: LeftoverChoice.keep, grant: GrantChoice.release),
        (p) async => null,
        (p) async => throw StateError('x'),
      ]) {
        final e = await _env([_a1, _a2]);
        final r = await e.service.switchOff(decide: answer);
        expect(e.deletes, isEmpty);
        expect(e.namesIn(_old), hasLength(2));
        expect(r.ok, isTrue);
        expect(await BackupPrefs.readFolderUri(), isNull);
        expect(e.releases, ['releaseGrant:$_old']);
      }
    });

    test('no leftovers, a failed listing, or no callback: no question', () async {
      var asked = 0;
      Future<LeftoverDecision?> counting(LeftoverPrompt p) async {
        asked++;
        return null;
      }

      var e = await _env([_manual]);
      await e.service.switchOff(decide: counting);
      e = await _env([_a1]);
      e.bridge.failOn.add('listFiles');
      final r = await e.service.switchOff(decide: counting);
      expect(r.listingFailed, isTrue);
      e = await _env([_a1]);
      expect(await e.service.turnOff(), isTrue);
      expect(asked, 0);
      expect(e.deletes, isEmpty);
    });

    test('turnOff with no folder chosen is quiet', () async {
      SharedPreferences.setMockInitialValues({});
      final e = _E(FakeStorageBridge());
      expect(await e.service.turnOff(decide: (p) async => fail('no question without a folder')), isTrue);
      expect(e.bridge.calls, isEmpty);
    });
  });
}
