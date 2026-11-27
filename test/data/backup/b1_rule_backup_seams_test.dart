// 0.2.2 item 2, slice B1: the rules are wired into backups and back out of them through ONE holder
// (RuleBackupSeams), both seams or neither. End to end on the real in-memory database, the real
// preferences rule store (AutoReadRuntime.ruleStore), the real RulesWiring (install + installBackupRules,
// as main.dart does) and the real Replace hook chain. Invented data only, no wording checked.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/levels/hard_rule_ports.dart' show debugAutoRecordUiOverride;
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart' show kReceiverDetailsPrefsKey;
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/runtime.dart';
import 'package:mmogo/autoread/wiring/rules_wiring.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:mmogo/data/backup/restore_trail_hook.dart';
import 'package:mmogo/data/backup/rule_backup_seams.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

final _at = DateTime.utc(2026, 11, 25);
DateTime _now() => DateTime.fromMillisecondsSinceEpoch(t0 + 999999);
const _sm = ReceiverType.sendMoney;
const _bg = ReceiverType.buyGoods;
const _po = ReceiverType.pochi;

BackupSettings _settings() => BackupSettings(prefs: SharedPreferences.getInstance);

BackupService _backup(Database db) => RuleBackupSeams.backupService(db: () async => db, now: _now, settings: _settings());

/// What the restore flow builds (a new service per step), with the test's db, safety store and the
/// real default afterReplace (the trail hook, which calls the chained RulesWiring hook).
RestoreService _restore(Database db, FakeSafetyCopyStore safety) => RuleBackupSeams.restoreService(
      db: () async => db,
      now: _now,
      settings: _settings(),
      safety: safety,
      validateInIsolate: false,
    );

Future<ReceiverRule?> _get(ReceiverType t, String k) => AutoReadRuntime.ruleStore.get(t, k);

Future<bool?> _paused() async {
  final p = await SharedPreferences.getInstance();
  await p.reload();
  return p.getBool(kHardPausedPrefsKey);
}

/// The phone's rules: Tim on Auto-record with a ceiling and a built-in category, Shop on Ask first with
/// a category, Jane (Pochi) on Suggested.
Future<void> _seedRules(Database db) async {
  final s = AutoReadRuntime.ruleStore;
  final rent = await seedId(db, 'SEND_MONEY:rent');
  final shopCat = (await categoriesOfGroup(db, 'BUY_GOODS')).first;
  expect(await s.setLevel(_sm, '0700000001', name: 'Tim', level: RuleLevel.autoRecord, categoryId: rent, ceilingCents: 50000, at: _at), isTrue);
  expect(await s.setLevel(_bg, '123456', name: 'Shop', level: RuleLevel.askFirst, categoryId: shopCat, at: _at), isTrue);
  expect(await s.setLevel(_po, 'JANE', name: 'Jane', level: RuleLevel.suggested, at: _at), isTrue);
}

Future<List<int>> categoriesOfGroup(Database db, String group) async => [
      for (final r in await db.rawQuery(
          'SELECT c.id FROM classifications c JOIN classification_groups g ON g.id = c.group_id '
          'WHERE g.code = ? AND c.active = 1 ORDER BY c.id',
          [group]))
        r['id']! as int,
    ];

Uint8List _file(List<Map<String, Object?>> rules, {int schema = 9}) =>
    fileBytes(fileJson(classes: seedRowsV5(), rules: rules, schemaVersion: schema));

void main() {
  late Database db;

  setUp(() async {
    // The pause notice sync switches a pause off when nobody is on Auto-record; with the screens live that would
    // change the pause under this test, which checks that backups never touch it. Keep the screens off here.
    debugAutoRecordUiOverride = false;
    SharedPreferences.setMockInitialValues({});
    db = await openTestDb();
    RulesWiring.database = () async => db;
  });

  tearDown(() {
    debugAutoRecordUiOverride = null;
    RulesWiring.uninstall();
    RuleBackupSeams.uninstall();
    AirtimeTrailRestoreHook.clearMemory = null;
  });

  /// As main.dart: RulesWiring.install, then installBackupRules, and the Replace hook chained onto the trail
  /// hook (initState in main.dart).
  void installLikeMain() {
    RulesWiring.install();
    RulesWiring.installBackupRules();
    AirtimeTrailRestoreHook.clearMemory = RulesWiring.restoreHook(prior: null, clearTrail: () {});
  }

  group('the holder: both seams or neither', () {
    test('nothing installed: no seam, no rule travels, the restore has no rules step (= before B1)', () async {
      expect(RuleBackupSeams.installed, isFalse);
      expect(RuleBackupSeams.source, isNull);
      expect(RuleBackupSeams.sink, isNull);
      await _seedRules(db);
      final viaHolder = await _backup(db).export();
      final plain = await BackupService(db: () async => db, now: _now, settings: _settings()).export();
      expect(viaHolder.receiverRules, 0);
      expect(viaHolder.bytes, plain.bytes, reason: 'null holder = exactly the old export');
      final r = await _restore(db, FakeSafetyCopyStore([])).restore(_file([ruleRow('SM', '9', lv: 1)]), RestoreMode.merge);
      expect(r.rules, isNull, reason: 'no sink: the restore never touches rules');
      expect(await _get(_sm, '9'), isNull);
    });

    test('install sets BOTH; RuleBackupSeams.uninstall and RulesWiring.uninstall clear BOTH; twice is safe', () {
      RulesWiring.installBackupRules();
      RulesWiring.installBackupRules();
      expect(RuleBackupSeams.installed, isTrue);
      expect(RuleBackupSeams.source, isNotNull);
      expect(RuleBackupSeams.sink, isNotNull);
      RuleBackupSeams.uninstall();
      expect([RuleBackupSeams.installed, RuleBackupSeams.source, RuleBackupSeams.sink], [false, null, null]);
      RulesWiring.install();
      RulesWiring.installBackupRules();
      RulesWiring.uninstall();
      expect([RuleBackupSeams.installed, RuleBackupSeams.source, RuleBackupSeams.sink], [false, null, null]);
    });

    test('every BackupService and RestoreService in lib/ is built by the holder (the four call sites)', () {
      // The only constructions allowed outside the holder: the service classes themselves and the
      // export flow's file-name helper (never exports, so it carries no rules).
      const allowed = {
        'lib/data/backup/backup_service.dart',
        'lib/data/backup/restore_service.dart',
        'lib/data/backup/rule_backup_seams.dart',
      };
      final ctor = RegExp(r'\b(BackupService|RestoreService)\(');
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final path = f.path.replaceAll('\\', '/');
        if (allowed.contains(path)) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('///') || line.trimLeft().startsWith('//')) continue;
          if (!ctor.hasMatch(line)) continue;
          if (path == 'lib/ui/screens/backup/backup_export_flow.dart' && line.contains('.suggestedFileName(')) continue;
          offenders.add('$path:${i + 1}: ${line.trim()}');
        }
      }
      expect(offenders, isEmpty, reason: 'build these through RuleBackupSeams');
      // and the four sites do use it
      bool uses(String p, String s) => File(p).readAsStringSync().contains(s);
      expect(uses('lib/data/backup/auto_backup_service.dart', 'RuleBackupSeams.backupService('), isTrue);
      expect(uses('lib/ui/screens/backup/backup_export_flow.dart', 'RuleBackupSeams.backupService('), isTrue);
      expect(uses('lib/ui/screens/backup/restore_flow.dart', 'RuleBackupSeams.restoreService('), isTrue);
      expect(uses('lib/main.dart', 'RulesWiring.installBackupRules()'), isTrue);
    });

    test('no file outside the holder passes rules: to a service (one seam alone is impossible)', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        final path = f.path.replaceAll('\\', '/');
        if (path == 'lib/data/backup/rule_backup_seams.dart') continue;
        if (RegExp(r'(BackupService|RestoreService)\([^;]*\brules:', multiLine: true, dotAll: true)
            .hasMatch(f.readAsStringSync().replaceAll(RegExp(r'//.*'), ''))) {
          offenders.add(path);
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('end to end (real DB, real prefs, real wiring)', () {
    test('export -> Replace: same levels, ceilings and categories; Auto-record back as Ask first + pending', () async {
      installLikeMain();
      await _seedRules(db);
      final exp = await _backup(db).export();
      expect(exp.receiverRules, 3);
      final f = BackupValidator.validate(exp.bytes);
      expect(f.receiverRules, hasLength(3));

      // the phone moves on: Tim forgotten, someone new
      await AutoReadRuntime.ruleStore.forget(_sm, '0700000001');
      await AutoReadRuntime.ruleStore.setLevel(_sm, '0799999999', name: 'New', level: RuleLevel.askFirst, at: _at);

      final r = await _restore(db, FakeSafetyCopyStore([])).restore(exp.bytes, RestoreMode.replace);
      expect(r.rules, isNotNull);
      expect(r.rules!.added, 3);
      expect(r.rules!.autoRecordAsAskFirst, 1);
      expect(r.rules!.failed, isFalse);

      expect(await _get(_sm, '0799999999'), isNull, reason: 'Replace: the phone\'s rules are the file\'s');
      final tim = (await _get(_sm, '0700000001'))!;
      expect(tim.level, RuleLevel.autoRecord);
      expect(tim.autoPending, isTrue);
      expect(tim.ceilingCents, 50000);
      expect(tim.categoryId, await seedId(db, 'SEND_MONEY:rent'));
      expect(tim.name, 'Tim');
      final shop = (await _get(_bg, '123456'))!;
      expect(shop.level, RuleLevel.askFirst);
      expect(shop.autoPending, isFalse);
      expect(shop.categoryId, (await categoriesOfGroup(db, 'BUY_GOODS')).first);
      final jane = (await _get(_po, 'JANE'))!;
      expect(jane.level, RuleLevel.suggested);
      expect([for (final x in await AutoReadRuntime.ruleStore.all()) if (x.level == RuleLevel.autoRecord) x.autoPending], [true],
          reason: 'everyone on Auto-record after a restore is pending (acts as Ask first)');
    });

    test('Merge adds only receivers with no rule; the phone\'s rules win', () async {
      installLikeMain();
      await AutoReadRuntime.ruleStore.setLevel(_sm, '0700000001', name: 'Tim', level: RuleLevel.suggested, at: _at);
      final r = await _restore(db, FakeSafetyCopyStore([])).restore(
          _file([
            ruleRow('SM', '0700000001', name: 'Tim', lv: 2, ceil: 900),
            ruleRow('BG', '555', name: 'Kiosk', lv: 1),
          ]),
          RestoreMode.merge);
      expect(r.rules!.added, 1);
      expect(r.rules!.replaced, 1);
      expect(r.rules!.keptPhone, 0);
      final tim = (await _get(_sm, '0700000001'))!;
      expect(tim.level, RuleLevel.autoRecord);
      expect(tim.autoPending, isTrue);
      expect(tim.ceilingCents, 900);
      expect((await _get(_bg, '555'))!.level, RuleLevel.askFirst);
    });

    test('a 0.2.1 backup (schema 8, no rules): Replace leaves no rules, Merge leaves the phone\'s alone', () async {
      installLikeMain();
      await _seedRules(db);
      final old = _file(const [], schema: 8);
      final m = await _restore(db, FakeSafetyCopyStore([])).restore(old, RestoreMode.merge);
      expect(await AutoReadRuntime.ruleStore.all(), hasLength(3));
      expect(m.rules == null || m.rules!.added == 0, isTrue);
      await _restore(db, FakeSafetyCopyStore([])).restore(old, RestoreMode.replace);
      expect(await AutoReadRuntime.ruleStore.all(), isEmpty);
    });

    test('Record receiver details OFF: the export writes no rule; a restore drops the file\'s and counts them', () async {
      installLikeMain();
      await _seedRules(db);
      final withRules = await _backup(db).export();
      final p = await SharedPreferences.getInstance();
      await p.setBool(kReceiverDetailsPrefsKey, false);
      final off = await _backup(db).export();
      expect(off.receiverRules, 0);
      final r = await _restore(db, FakeSafetyCopyStore([])).restore(withRules.bytes, RestoreMode.replace);
      expect(r.rules!.droppedForPrivacy, 3);
      expect(r.rules!.added, 0);
      expect(await AutoReadRuntime.ruleStore.all(), isEmpty);
    });

    test('Undo of a Replace brings the old rules back (the safety copy carries them)', () async {
      installLikeMain();
      await _seedRules(db);
      final safety = FakeSafetyCopyStore([]);
      await _restore(db, safety).restore(_file([ruleRow('PO', 'OTHER', name: 'Other', lv: 1)]), RestoreMode.replace);
      expect((await AutoReadRuntime.ruleStore.all()).map((x) => x.key), ['OTHER']);
      expect(BackupValidator.validate(safety.bytes!).receiverRules, hasLength(3), reason: 'the safety copy holds the rules');

      final u = await _restore(db, safety).undoLastReplace();
      expect(u.rules!.added, 3);
      expect(await _get(_po, 'OTHER'), isNull);
      final tim = (await _get(_sm, '0700000001'))!;
      expect(tim.level, RuleLevel.autoRecord);
      expect(tim.autoPending, isTrue);
      expect(tim.ceilingCents, 50000);
      expect(tim.categoryId, await seedId(db, 'SEND_MONEY:rent'));
      expect((await _get(_bg, '123456'))!.level, RuleLevel.askFirst);
      expect((await _get(_po, 'JANE'))!.level, RuleLevel.suggested);
    });

    test('without the holder an Undo of a Replace cannot bring rules back (why both go together)', () async {
      // Today's behaviour, pinned so the difference is visible: no pair = the safety copy has no rules.
      await _seedRules(db);
      final safety = FakeSafetyCopyStore([]);
      await _restore(db, safety).restore(_file(const []), RestoreMode.replace);
      expect(BackupValidator.validate(safety.bytes!).receiverRules, isEmpty);
    });

    test('the pause switch is untouched by export, Replace, Merge and Undo (paused and not paused)', () async {
      // Since the 0.2.2 flip the pause notice sync is on, and it switches a pause off when nobody is on Auto-record
      // (by design). This test is about the backup seams only, so it runs with the Auto-record screens off.
      debugAutoRecordUiOverride = false;
      addTearDown(() => debugAutoRecordUiOverride = null);
      for (final start in [true, null]) {
        SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: ?start});
        RulesWiring.uninstall();
        installLikeMain();
        await _seedRules(db);
        final exp = await _backup(db).export();
        expect(await _paused(), start);
        expect(BackupValidator.validate(exp.bytes).prefs.keys, isNot(contains(kHardPausedPrefsKey)));
        final safety = FakeSafetyCopyStore([]);
        await _restore(db, safety).restore(exp.bytes, RestoreMode.replace);
        expect(await _paused(), start);
        await _restore(db, safety).restore(_file([ruleRow('BG', '777', lv: 1)]), RestoreMode.merge);
        expect(await _paused(), start);
        await _restore(db, safety).undoLastReplace();
        expect(await _paused(), start);
      }
    });
  });
}
