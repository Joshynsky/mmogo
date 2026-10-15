// S10a (A2a, A2d, addendum A-D, G): Replace never loses rows silently. Real
// in-memory database, a SafetyCopyStore in a TEMP folder (or the fake), a
// DataOpGate of its own, mock prefs. Nothing here touches the real database,
// prefs or safety folder.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_writer.dart' show ExpectedRows;
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/maintenance/data_op_gate.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/fake_timer.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

const _secretLabel = 'SECRETSHOP';

class _Env {
  _Env(this.db, this.tmp, this.log) {
    store = SafetyCopyStore(baseDir: () async => tmp);
  }
  final Database db;
  final Directory tmp;
  final List<Stmt> log;
  late final SafetyCopyStore store;
  final gate = DataOpGate();

  RestoreService svc({
    SafetyCopyStore? safety,
    BackupService? backup,
    RestoreTimerFactory? timer,
  }) =>
      RestoreService(
        db: () async => db,
        backup: backup ?? backupOf(db),
        safety: safety ?? store,
        settings: BackupSettings(prefs: SharedPreferences.getInstance),
        validateInIsolate: false,
        gate: gate,
        timer: timer,
      );

  int writesSince(int mark) => log.sublist(mark).where((s) => s.isWrite).length;

  Future<int> n(String sql) async => (await db.rawQuery(sql)).first['n']! as int;

  /// One live entry the exporter must skip (amount over the file cap).
  Future<int> addUnreadable({String code = 'BIG1111111', int at = t0 + 40}) async =>
      addTx(db,
          code: code,
          source: 'BUY_GOODS',
          classId: await seedId(db, 'BUY_GOODS:groceries'),
          amount: 99999999999,
          label: _secretLabel,
          createdAt: at);

  /// A built-in whose name is unusable, with a saved receiver on it: the
  /// category is skipped and its entries and receiver go with it.
  Future<void> addSkippedCategoryWithCascade() async {
    await db.update('classifications', {'name': '\u0001'},
        where: 'seed_key = ?', whereArgs: ['BUY_GOODS:shopping']);
    await addMap(db, 'BUY_GOODS', 'DUKA', await seedId(db, 'BUY_GOODS:shopping'));
  }
}

Future<_Env> _env() async {
  SharedPreferences.setMockInitialValues({});
  final tmp = await Directory.systemTemp.createTemp('mmogo_s10a_replace_');
  final log = <Stmt>[];
  final db = await openTestDb(log: log);
  await populate(db);
  return _Env(db, tmp, log);
}

Future<void> _close(_Env e) async {
  await e.db.close();
  await e.tmp.delete(recursive: true);
}

Uint8List _replacement() => fileBytes(fileJson(
      classes: [...seedRows(), cls(20, 'BUY_GOODS', 'Kiosk')],
      txs: [
        tx(1, 'NEW1111111', 'SEND_MONEY', 2, label: 'MAMA', phone: '0700000001'),
        tx(2, 'NEW2222222', 'BUY_GOODS', 20),
      ],
      map: [mapRow('SEND_MONEY', '0700000001', 2)],
    ));

Matcher _fails(RestoreFailReason r) =>
    throwsA(isA<RestoreFailed>().having((e) => e.reason, 'reason', r));

void main() {
  tearDown(() => SharedPreferences.setMockInitialValues({}));

  group('identity: included + skipped = live, per table', () {
    test('plain phone: nothing skipped, identity holds and equals the SQL counts', () async {
      final e = await _env();
      final pv = await e.svc().previewReplace();
      expect(pv.skippedCount, 0);
      expect(pv.identity.holds, isTrue);
      expect(pv.identity.transactions.live,
          await e.n('SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL'));
      expect(pv.identity.classifications.live, await e.n('SELECT COUNT(*) AS n FROM classifications'));
      expect(pv.identity.counterpartyMap.live,
          await e.n('SELECT COUNT(*) AS n FROM counterparty_classification_map'));
      await _close(e);
    });

    test('a skipped built-in category with a cascade: identity holds per table', () async {
      final e = await _env();
      await e.addUnreadable();
      await e.addSkippedCategoryWithCascade();
      final pv = await e.svc().previewReplace();
      final id = pv.identity;

      expect(id.classifications.skipped, 1, reason: 'the category with the unusable name');
      expect(id.transactions.skipped, greaterThanOrEqualTo(2),
          reason: 'the over-cap entry and the entry that went with its category');
      expect(id.counterpartyMap.skipped, greaterThanOrEqualTo(1), reason: 'the receiver cascaded');
      expect(id.holds, isTrue);
      // The live side is read from the database, not derived from the sums.
      expect(id.transactions.live,
          await e.n('SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL'));
      expect(id.classifications.live, await e.n('SELECT COUNT(*) AS n FROM classifications'));
      expect(id.counterpartyMap.live,
          await e.n('SELECT COUNT(*) AS n FROM counterparty_classification_map'));
      expect(pv.skippedCount, id.skippedTotal, reason: 'N is the skipped count exactly');
      expect(pv.phoneRecentlyDeleted, 1, reason: 'the recently deleted entry is a separate count');
      await _close(e);
    });
  });

  group('consent (addendum A)', () {
    test('consent 0 with 1 skipped refuses before any write; null refuses too', () async {
      final e = await _env();
      await e.addUnreadable();
      final before = await fullDump(e.db);
      final mark = e.log.length;
      for (final accepted in <int?>[0, null]) {
        await expectLater(
          e.svc().restore(_replacement(), RestoreMode.replace, acceptedSkipped: accepted),
          _fails(RestoreFailReason.skippedChanged),
        );
      }
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      expect(await e.store.exists(), isFalse, reason: 'no safety copy was written either');
      expect(e.gate.isHeld, isFalse);
      await _close(e);
    });

    test('consent equal to the real count proceeds; the lost rows are carried and described',
        () async {
      final e = await _env();
      await e.addUnreadable();
      final svc = e.svc();
      final pv = await svc.previewReplace();
      expect(pv.skippedCount, 1);
      final r = await svc.restore(_replacement(), RestoreMode.replace, acceptedSkipped: 1);
      expect(r.lostCount, 1);
      expect(r.lost.shown.single.kind, SkipKind.entry);
      expect(r.lost.shown.single.type, 'BUY_GOODS');
      expect(r.identity!.holds, isTrue);
      expect(r.safetyCopyKept, isTrue);
      expect(await e.n('SELECT COUNT(*) AS n FROM transactions'), 2, reason: 'the file\'s rows');
      await _close(e);
    });

    test('consent above the real count proceeds', () async {
      final e = await _env();
      await e.addUnreadable();
      await e.svc().restore(_replacement(), RestoreMode.replace, acceptedSkipped: 5);
      expect(await e.n('SELECT COUNT(*) AS n FROM transactions'), 2);
      await _close(e);
    });

    test('nothing skipped: no consent needed', () async {
      final e = await _env();
      final r = await e.svc().restore(_replacement(), RestoreMode.replace);
      expect(r.lostCount, 0);
      expect(r.lost.shown, isEmpty);
      await _close(e);
    });

    test('a row that becomes unreadable between preview and run refuses', () async {
      final e = await _env();
      await e.addUnreadable();
      final svc = e.svc();
      final pv = await svc.previewReplace();
      expect(pv.skippedCount, 1);
      await e.addUnreadable(code: 'BIG2222222', at: t0 + 41); // now 2
      final before = await fullDump(e.db);
      final mark = e.log.length;
      await expectLater(
        svc.restore(_replacement(), RestoreMode.replace, acceptedSkipped: pv.skippedCount),
        _fails(RestoreFailReason.skippedChanged),
      );
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      await _close(e);
    });

    test('Merge never asks for consent and never has lost rows', () async {
      final e = await _env();
      await e.addUnreadable();
      final r = await e.svc().restore(_replacement(), RestoreMode.merge);
      expect(r.lostCount, 0);
      expect(r.identity, isNull);
      await _close(e);
    });
  });

  group('the live check uses LIVE counts, the safety copy INCLUDED counts (addendum B)', () {
    test('Replace with a cascade completes: the transaction found included + skipped', () async {
      final e = await _env();
      await e.addUnreadable();
      await e.addSkippedCategoryWithCascade();
      final n = (await e.svc().previewReplace()).skippedCount;
      final r = await e.svc().restore(_replacement(), RestoreMode.replace, acceptedSkipped: n);
      expect(r.lostCount, n);
      // Everything the file holds is there, nothing the cascade skipped came back.
      expect(await e.n('SELECT COUNT(*) AS n FROM transactions'), 2);
      // The safety copy holds only the INCLUDED rows.
      final copy = (await e.store.readLatest())!;
      final v = _count(copy);
      expect(v.$1, r.identity!.transactions.included);
      expect(v.$2, r.identity!.classifications.included);
      expect(v.$3, r.identity!.counterpartyMap.included);
      await _close(e);
    });

    test('FakeSafetyCopyStore mirrors the split: it refuses the LIVE counts', () async {
      final e = await _env();
      await e.addUnreadable();
      final id = (await e.svc().previewReplace()).identity;
      final bytes = await backupOf(e.db).exportToBytes();
      final fake = FakeSafetyCopyStore([]);
      await fake.write(bytes, expect: ExpectedRows(
        transactions: id.transactions.included,
        classifications: id.classifications.included,
        counterpartyMap: id.counterpartyMap.included,
      ));
      await expectLater(
        fake.write(bytes, expect: ExpectedRows(
          transactions: id.transactions.live,
          classifications: id.classifications.live,
          counterpartyMap: id.counterpartyMap.live,
        )),
        throwsA(isA<SafetyCopyError>()),
      );
      await _close(e);
    });

    test('data that changes after the read-back still refuses (LIVE count differs)', () async {
      final e = await _env();
      await e.addUnreadable();
      final sneaky = _SneakyAfterWrite(e.db);
      await expectLater(
        e.svc(safety: sneaky).restore(_replacement(), RestoreMode.replace, acceptedSkipped: 1),
        _fails(RestoreFailReason.dataChangedMeanwhile),
      );
      await _close(e);
    });
  });

  group('failure injection: nothing is written before the copy is proven', () {
    test('the live rows cannot be read back (export fails): refuses, no live write', () async {
      final e = await _env();
      final before = await fullDump(e.db);
      final mark = e.log.length;
      final tiny = BackupService(
          db: () async => e.db,
          settings: BackupSettings(prefs: SharedPreferences.getInstance),
          maxBytes: 100);
      await expectLater(
        e.svc(backup: tiny).restore(_replacement(), RestoreMode.replace),
        _fails(RestoreFailReason.safetyCopyFailed),
      );
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      await _close(e);
    });

    test('the safety copy cannot be written (real store, folder blocked): refuses, no live write',
        () async {
      final e = await _env();
      // A FILE where the "safety" folder must be: creating it fails.
      await File(p.join(e.tmp.path, SafetyCopyStore.folderName)).writeAsString('x');
      final before = await fullDump(e.db);
      final mark = e.log.length;
      await expectLater(
        e.svc().restore(_replacement(), RestoreMode.replace),
        _fails(RestoreFailReason.safetyCopyFailed),
      );
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      await _close(e);
    });

    test('the copy reads back wrong (fake unreadable): refuses, no live write', () async {
      final e = await _env();
      final before = await fullDump(e.db);
      final mark = e.log.length;
      await expectLater(
        e.svc(safety: FakeSafetyCopyStore([], unreadable: true))
            .restore(_replacement(), RestoreMode.replace),
        _fails(RestoreFailReason.safetyCopyFailed),
      );
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      await _close(e);
    });
  });

  group('Undo, gate and v2 file into v3', () {
    test('Undo restores everything except the lost rows, removes the copy and says so', () async {
      final e = await _env();
      await e.addUnreadable();
      final before = await contentDump(e.db);
      final svc = e.svc();
      final r = await svc.restore(_replacement(), RestoreMode.replace, acceptedSkipped: 1);
      expect(r.safetyCopyStillThere, isFalse);
      expect(await svc.canUndo(), isTrue);

      final u = await svc.undoLastReplace();
      expect(u.transactions.added, r.identity!.transactions.included);
      expect(u.safetyCopyStillThere, isFalse);
      expect(await svc.canUndo(), isFalse);
      final after = await contentDump(e.db);
      expect(after['transactions'], hasLength(before['transactions']!.length - 1),
          reason: 'all but the one lost entry');
      expect(after['transactions']!.any((t) => t.contains('BIG1111111')), isFalse);
      await _close(e);
    });

    test('Undo whose copy cannot be removed carries safetyCopyStillThere', () async {
      final e = await _env();
      final fake = FakeSafetyCopyStore([], failClearVerified: true);
      final svc = e.svc(safety: fake);
      await svc.restore(_replacement(), RestoreMode.replace);
      final u = await svc.undoLastReplace();
      expect(u.safetyCopyStillThere, isTrue);
      expect(await svc.canUndo(), isTrue);
      await _close(e);
    });

    test('a held gate: restore and Undo are busy; previewReplace still works (no gate)', () async {
      final e = await _env();
      final svc = e.svc();
      await svc.restore(_replacement(), RestoreMode.replace);
      expect(e.gate.tryAcquire(), isTrue);
      final mark = e.log.length;
      await expectLater(svc.restore(_replacement(), RestoreMode.replace), _fails(RestoreFailReason.busy));
      await expectLater(svc.undoLastReplace(), _fails(RestoreFailReason.busy));
      final pv = await svc.previewReplace();
      expect(pv.identity.holds, isTrue);
      expect(e.writesSince(mark), 0);
      expect(e.gate.isHeld, isTrue, reason: 'the holder\'s gate is not released by the refused calls');
      e.gate.release();
      await _close(e);
    });

    test('previewReplace writes nothing and validates the file when bytes are given', () async {
      final e = await _env();
      await e.addUnreadable();
      final before = await fullDump(e.db);
      final mark = e.log.length;
      final pv = await e.svc().previewReplace(_replacement());
      expect(e.writesSince(mark), 0);
      expect(await fullDump(e.db), before);
      expect(pv.fileTransactions, 2);
      expect(pv.fileClassifications, seedRows().length + 1, reason: 'the built-ins plus Kiosk');
      expect(pv.phoneUserClassifications, 3);
      expect(await e.store.exists(), isFalse);
      await expectLater(e.svc().previewReplace(Uint8List.fromList([1, 2, 3])),
          throwsA(isA<RestoreRejected>()));
      await _close(e);
    });

    test('a v2 file Replaces into a v3 phone that has a lost row (consent given)', () async {
      final e = await _env();
      await e.addUnreadable();
      final fixture = File('test/fixtures/backup_v2_anonymised.json').readAsBytesSync();
      final r = await e.svc().restore(fixture, RestoreMode.replace, acceptedSkipped: 1);
      expect(r.lostCount, 1);
      expect(await e.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await _close(e);
    });
  });

  group('step events (BP2)', () {
    test('Replace emits validating, safetyCopy, writing in order, each started then done',
        () async {
      final e = await _env();
      final events = <RestoreStepEvent>[];
      await e.svc().restore(_replacement(), RestoreMode.replace, onStep: events.add);
      expect([for (final x in events) '${x.step.name}:${x.phase.name}'], [
        'validating:started', 'validating:done',
        'safetyCopy:started', 'safetyCopy:done',
        'writing:started', 'writing:done',
      ]);
      await _close(e);
    });

    test('Merge has no safetyCopy step; Undo has validating and writing', () async {
      final e = await _env();
      final events = <RestoreStepEvent>[];
      await e.svc().restore(_replacement(), RestoreMode.merge, onStep: events.add);
      expect(events.map((x) => x.step).toSet(), {RestoreStep.validating, RestoreStep.writing});
      final svc = e.svc();
      await svc.restore(_replacement(), RestoreMode.replace);
      events.clear();
      await svc.undoLastReplace(onStep: events.add);
      expect(events.map((x) => x.step).toSet(), {RestoreStep.validating, RestoreStep.writing});
      await _close(e);
    });

    test('a failing step emits failed and the later steps never start', () async {
      final e = await _env();
      final events = <RestoreStepEvent>[];
      await expectLater(
        e.svc(safety: FakeSafetyCopyStore([], failWrite: true))
            .restore(_replacement(), RestoreMode.replace, onStep: events.add),
        _fails(RestoreFailReason.safetyCopyFailed),
      );
      expect(events.last.step, RestoreStep.safetyCopy);
      expect(events.last.phase, RestoreStepPhase.failed);
      expect(events.any((x) => x.step == RestoreStep.writing), isFalse);
      await _close(e);
    });

    test('a callback that throws never breaks the restore', () async {
      final e = await _env();
      final r = await e.svc().restore(_replacement(), RestoreMode.replace,
          onStep: (_) => throw StateError('ui bug'));
      expect(r.safetyCopyKept, isTrue);
      await _close(e);
    });

    test('the slow marker: a 10 s timer is armed per step, fires into a slow event, is cancelled',
        () async {
      final e = await _env();
      final timers = <FakeTimer>[];
      final events = <RestoreStepEvent>[];
      final slowStore = _FiringSafety(timers);
      await e
          .svc(safety: slowStore, timer: (d, f) {
            final t = FakeTimer(d, f);
            timers.add(t);
            return t;
          })
          .restore(_replacement(), RestoreMode.replace, onStep: events.add);
      expect(timers.map((t) => t.after), everyElement(const Duration(seconds: 10)));
      expect(timers, hasLength(3));
      expect(timers.every((t) => t.cancelled), isTrue);
      final slow = events.where((x) => x.phase == RestoreStepPhase.slow).toList();
      expect(slow.map((x) => x.step), [RestoreStep.safetyCopy],
          reason: 'only the step that was still running when the timer fired');
      await _close(e);
    });
  });
}

/// (transactions, classifications, map) row counts of a backup file.
(int, int, int) _count(Uint8List bytes) {
  final v = BackupValidator.validate(bytes);
  return (v.transactions.length, v.classifications.length, v.counterpartyMap.length);
}

/// Adds an entry right after the copy is made: the LIVE counts then differ.
class _SneakyAfterWrite extends FakeSafetyCopyStore {
  _SneakyAfterWrite(this.db) : super([]);
  final Database db;

  @override
  Future<File> write(Uint8List data,
      {required ExpectedRows expect,
      Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups}) async {
    final f = await super.write(data, expect: expect, enabledGroupCodes: enabledGroupCodes);
    await addTx(db, code: 'LATE111111', source: 'SEND_MONEY', classId: await seedId(db, 'SEND_MONEY:rent'));
    return f;
  }
}

/// Fires the newest timer while the safety copy is being written (that step is
/// then "slow").
class _FiringSafety extends FakeSafetyCopyStore {
  _FiringSafety(this.timers) : super([]);
  final List<FakeTimer> timers;

  @override
  Future<File> write(Uint8List data,
      {required ExpectedRows expect,
      Set<String> enabledGroupCodes = BackupValidator.defaultEnabledGroups}) {
    timers.last.fire();
    return super.write(data, expect: expect, enabledGroupCodes: enabledGroupCodes);
  }
}
