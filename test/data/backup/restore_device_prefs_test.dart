// S10a: F3 (Replace and Undo leave the remembered recipients alone; a restore
// file cannot carry them) and the CA11 `_noteKeyRewrite` edge (a re-keyed
// saved receiver that collides with an existing one is counted as lost and
// needs the user's consent, so Replace never loses it silently). Temp
// folder, in-memory database, mock prefs.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/safety_copy_store.dart';
import 'package:mmogo/data/maintenance/data_op_gate.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

class _Env {
  _Env(this.db, this.tmp) {
    store = SafetyCopyStore(baseDir: () async => tmp);
  }
  final Database db;
  final Directory tmp;
  late final SafetyCopyStore store;
  final gate = DataOpGate();

  RestoreService svc() => RestoreService(
        db: () async => db,
        backup: backupOf(db),
        safety: store,
        settings: BackupSettings(prefs: SharedPreferences.getInstance),
        validateInIsolate: false,
        gate: gate,
      );
}

Future<_Env> _env() async {
  final tmp = await Directory.systemTemp.createTemp('mmogo_s10a_prefs_');
  final db = await openTestDb();
  await populate(db);
  return _Env(db, tmp);
}

Future<void> _close(_Env e) async {
  await e.db.close();
  await e.tmp.delete(recursive: true);
}

Uint8List _file({Map<String, Object?> prefs = const {}}) => fileBytes(fileJson(
      classes: seedRows(),
      txs: [tx(1, 'NEW1111111', 'SEND_MONEY', 2, label: 'MAMA', phone: '0700000001')],
      map: [mapRow('SEND_MONEY', '0700000001', 2)],
      prefs: prefs,
    ));

void main() {
  group('F3: remembered recipients are a phone preference', () {
    test('Replace and Undo leave the stored value byte for byte; a file cannot carry it', () async {
      SharedPreferences.setMockInitialValues({});
      final memory = RecipientMemory(prefs: SharedPreferences.getInstance, nowMs: () => 1790000000000);
      expect(await memory.remember('MAMA MBOGA', SmsSourceType.pochi, recordDetailsOn: true),
          RememberResult.saved);
      expect(await memory.remember('BABA JOHN', SmsSourceType.sendMoney, recordDetailsOn: true),
          RememberResult.saved);
      final prefs = await SharedPreferences.getInstance();
      final mine = prefs.getString(RecipientMemory.prefsKey)!;

      final e = await _env();
      final svc = e.svc();
      // The file tries to plant its own value for the key.
      await svc.restore(_file(prefs: {RecipientMemory.prefsKey: '{"planted":{"t":"POCHI_LA_BIASHARA","at":1}}'}),
          RestoreMode.replace);
      expect(prefs.getString(RecipientMemory.prefsKey), mine, reason: 'after Replace');
      await svc.undoLastReplace();
      expect(prefs.getString(RecipientMemory.prefsKey), mine, reason: 'after Undo');
      expect((await memory.lookup('MAMA MBOGA'))!.type, SmsSourceType.pochi);
      await _close(e);
    });

    test('a phone with no remembered recipients stays without the key after Replace and Undo', () async {
      SharedPreferences.setMockInitialValues({});
      final e = await _env();
      final svc = e.svc();
      await svc.restore(_file(prefs: {RecipientMemory.prefsKey: 'planted'}), RestoreMode.replace);
      await svc.undoLastReplace();
      expect((await SharedPreferences.getInstance()).containsKey(RecipientMemory.prefsKey), isFalse);
      await _close(e);
    });

    test('the copy constant is prose only: no key name, and it says what S10b must say', () {
      expect(kRememberedRecipientsNotInBackup.contains('recipient_types'), isFalse);
      expect(kRememberedRecipientsNotInBackup, contains('not part of a backup'));
      expect(kRememberedRecipientsNotInBackup, contains('Replace and Undo leave them alone'));
      expect(kRememberedRecipientsNotInBackup, contains('Delete data clears them'));
    });

    test('lib/data/backup never names the key (the existing guard still holds)', () {
      for (final f in Directory('lib/data/backup').listSync().whereType<File>()) {
        expect(f.readAsStringSync().contains('recipient_types'), isFalse, reason: f.path);
      }
    });
  });

  group('CA11: the _noteKeyRewrite edge', () {
    test('a re-keyed saved receiver that collides with an existing one is counted, needs consent, '
        'and is not lost silently', () async {
      SharedPreferences.setMockInitialValues({});
      final e = await _env();
      final groceries = await seedId(e.db, 'BUY_GOODS:groceries');
      // An old entry whose label has a stray control character (the export
      // repairs the COPY), a clean entry of the same shop, and a learned
      // receiver for each spelling.
      await addTx(e.db, code: 'KEY1111111', source: 'BUY_GOODS', classId: groceries,
          label: 'DU\u0001KA', createdAt: t0 + 50);
      await addTx(e.db, code: 'KEY2222222', source: 'BUY_GOODS', classId: groceries,
          label: 'DUKA', createdAt: t0 + 51);
      await addMap(e.db, 'BUY_GOODS', 'DU\u0001KA', groceries);
      await addMap(e.db, 'BUY_GOODS', 'DUKA', groceries);

      final svc = e.svc();
      final pv = await svc.previewReplace();
      expect(pv.skippedCount, 1, reason: 'one of the two saved receivers cannot go into the copy');
      expect(pv.identity.counterpartyMap.skipped, 1);
      expect(pv.identity.holds, isTrue);
      expect(pv.skipped.shown.single.kind, SkipKind.savedReceiver);

      final before = await fullDump(e.db);
      await expectLater(
        svc.restore(_file(), RestoreMode.replace),
        throwsA(isA<RestoreFailed>().having((x) => x.reason, 'reason', RestoreFailReason.skippedChanged)),
      );
      expect(await fullDump(e.db), before, reason: 'refused rather than lose data');

      final r = await svc.restore(_file(), RestoreMode.replace, acceptedSkipped: 1);
      expect(r.lostCount, 1);
      await _close(e);
    });
  });
}
