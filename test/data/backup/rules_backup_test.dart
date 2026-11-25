// 0.2.2 item 2, slice S-4a: backup schema 9 (the `receiver_rules` section): file format, export,
// validator, limits, exporter-side repair. Invented data only. Restore is S-4b (not tested here).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/rule_backup_source.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/autoread/rules/rule_store.dart';
import 'package:mmogo/data/backup/backup_codec.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_rules.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/restore_files.dart';
import '../../support/restore_test_db.dart';

Map<String, Object?> _v9({List<Map<String, Object?>> rules = const []}) =>
    fileJson(classes: seedRowsV5(), rules: rules, schemaVersion: 9);

ValidatedBackup _ok(Map<String, Object?> json) => BackupValidator.validate(fileBytes(json));

RestoreRejected _refused(Map<String, Object?> json) {
  try {
    BackupValidator.validate(fileBytes(json));
  } on RestoreRejected catch (e) {
    return e;
  }
  fail('the file was accepted');
}

BackupService _svc(dynamic db, BackupRulesSource? rules) => BackupService(
      db: () async => db,
      now: () => DateTime.fromMillisecondsSinceEpoch(t0 + 999999),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      rules: rules,
    );

Map<String, Object?> _json(Uint8List b) => jsonDecode(utf8.decode(b)) as Map<String, Object?>;
List<Map<String, Object?>> _ruleRows(Map<String, Object?> j) =>
    (j['receiver_rules']! as List).cast<Map<String, Object?>>();

BackupRuleInput _in(String t, String k,
        {String name = 'Person', int lv = 1, int? cat, int? ceil, bool ap = false}) =>
    BackupRuleInput(type: t, key: k, name: name, level: lv, categoryId: cat, ceilingCents: ceil, autoPending: ap);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('constants', () {
    test('file schema 9 is one ahead of the database (8); rule gates and caps are pinned', () {
      expect(kBackupSchemaVersion, 9);
      expect(kBackupFirstSchemaWithRules, 9);
      expect(kBackupMaxRules, kRuleCap);
      expect(kBackupRuleTypes, [for (final t in ReceiverType.values) t.code]);
      expect(kBackupMinCeilingCents, kCeilingMinCents);
      expect(kBackupMaxCeilingCents, kCeilingMaxCents);
      expect(kBackupMaxRuleLevel, RuleLevel.autoRecord.code);
      expect(kBackupRuleKeys, ['t', 'k', 'name', 'lv', 'cat_seed', 'cat_name', 'ceil', 'ap']);
    });

    test('receiver_rules sits between fuliza_events and prefs; the schema 8 lists are frozen', () {
      final i = kBackupTopLevelKeys.indexOf('receiver_rules');
      expect(kBackupTopLevelKeys[i - 1], 'fuliza_events');
      expect(kBackupTopLevelKeys[i + 1], 'prefs');
      expect(kBackupTopLevelKeys.last, 'end');
      expect(kBackupTopLevelKeysV8, [...kBackupTopLevelKeys]..remove('receiver_rules'));
      expect(kBackupCountsKeys, [...kBackupCountsKeysV8, 'receiver_rules']);
    });

    test('the 0.2.1 app (max schema 8) refuses a schema 9 file as newer: assert the constant', () {
      expect(kBackupSchemaVersion, greaterThan(8));
    });
  });

  group('codec', () {
    test('writes the section in order, `end` still last, counts entry; only the 8 keys', () {
      final bytes = BackupCodec.encode(
        createdAtMs: f0,
        classifications: const [],
        transactions: const [],
        counterpartyMap: const [],
        receiverRules: [
          {...ruleRow('SM', 'a', ceil: 500), 'stray': 'x'},
        ],
      );
      final j = _json(bytes);
      expect(j.keys.toList(), kBackupTopLevelKeys);
      expect((j['counts']! as Map)['receiver_rules'], 1);
      expect(_ruleRows(j).single.keys.toList(), kBackupRuleKeys);
      expect(utf8.decode(bytes).endsWith('"end":"mmogo-v1"}'), isTrue);
    });
  });

  group('validator: schema gating', () {
    test('a schema 9 file with the section validates; rows come back with hasRulesSection', () {
      final v = _ok(_v9(rules: [
        ruleRow('SM', 'a', lv: 2, ceil: 1, catSeed: 'SEND_MONEY:rent'),
        ruleRow('BG', 'b', lv: 1, catName: 'My own', ap: 1),
        ruleRow('PO', 'c', lv: 0),
      ]));
      expect(v.hasRulesSection, isTrue);
      expect(v.receiverRules.length, 3);
      expect(v.receiverRules.first['ceil'], 1);
    });

    test('a schema 9 file with an empty section validates', () {
      final v = _ok(_v9());
      expect(v.hasRulesSection, isTrue);
      expect(v.receiverRules, isEmpty);
    });

    test('a 0.2.1 (schema 8) backup with no rules validates: no section, none restored', () {
      final v = _ok(fileJson(classes: seedRowsV5(), schemaVersion: 8));
      expect(v.hasRulesSection, isFalse);
      expect(v.receiverRules, isEmpty);
    });

    test('schema 4..8 files stay valid with no section (frozen key lists)', () {
      for (final s in [4, 5, 6, 7, 8]) {
        expect(_ok(fileJson(classes: s >= 5 ? seedRowsV5() : seedRowsV3(), schemaVersion: s)).hasRulesSection, isFalse, reason: '$s');
      }
    });

    test('a schema 8 file that carries the section (or its count) is refused (exact keys)', () {
      final withSection = fileJson(classes: seedRowsV5(), schemaVersion: 8)..['receiver_rules'] = <Object?>[];
      expect(_refused(withSection).field, '(keys)');
      final withCount = fileJson(classes: seedRowsV5(), schemaVersion: 8);
      (withCount['counts']! as Map)['receiver_rules'] = 0;
      expect(_refused(withCount).field, 'counts');
    });

    test('a schema 9 file without the section, or without its count, is refused', () {
      final noSection = _v9()..remove('receiver_rules');
      expect(_refused(noSection).field, '(keys)');
      final noCount = _v9();
      (noCount['counts']! as Map).remove('receiver_rules');
      expect(_refused(noCount).field, 'counts');
    });

    test('the count must equal the rows; the section must be a list', () {
      final wrong = _v9(rules: [ruleRow('SM', 'a')]);
      (wrong['counts']! as Map)['receiver_rules'] = 2;
      expect(_refused(wrong).field, 'counts');
      expect(_refused(_v9()..['receiver_rules'] = 'x').field, 'receiver_rules');
    });

    test('schema 10 is newer', () {
      expect(_refused(fileJson(classes: seedRowsV5(), schemaVersion: 10)).reason, RestoreRejectReason.newer);
    });
  });

  group('validator: rows', () {
    void bad(String why, Map<String, Object?> row, String field) {
      final e = _refused(_v9(rules: [row]));
      expect(e.reason, RestoreRejectReason.invalidRow, reason: why);
      expect(e.table, 'receiver_rules', reason: why);
      expect(e.rowIndex, 0, reason: why);
      expect(e.field, field, reason: why);
    }

    test('bad kind, level, key, name, marker', () {
      bad('kind', ruleRow('XX', 'a'), 't');
      bad('level 3', ruleRow('SM', 'a', lv: 3), 'lv');
      bad('level -1', ruleRow('SM', 'a', lv: -1), 'lv');
      bad('empty key', ruleRow('SM', ''), 'k');
      bad('overlong key', ruleRow('SM', 'k' * 201), 'k');
      bad('control char in key', ruleRow('SM', 'a\u0007b'), 'k');
      bad('bidi in key', ruleRow('SM', 'a\u202Eb'), 'k');
      bad('untrimmed key', ruleRow('SM', ' a'), 'k');
      bad('empty name', ruleRow('SM', 'a', name: ''), 'name');
      bad('control in name', ruleRow('SM', 'a', name: 'x\ny'), 'name');
      bad('overlong name', ruleRow('SM', 'a', name: 'n' * 201), 'name');
      bad('marker 2', ruleRow('SM', 'a', ap: 2), 'ap');
    });

    test('key length boundary: 200 accepted', () {
      expect(_ok(_v9(rules: [ruleRow('SM', 'k' * 200)])).receiverRules.length, 1);
    });

    test('ceiling boundaries: 1 and 100,000,000 accepted; 0, 100,000,001, -1, 1.5, string refused', () {
      expect(_ok(_v9(rules: [ruleRow('SM', 'a', ceil: 1)])).receiverRules.length, 1);
      expect(_ok(_v9(rules: [ruleRow('SM', 'a', ceil: 100000000)])).receiverRules.length, 1);
      bad('0', ruleRow('SM', 'a', ceil: 0), 'ceil');
      bad('max+1', ruleRow('SM', 'a', ceil: 100000001), 'ceil');
      bad('-1', ruleRow('SM', 'a', ceil: -1), 'ceil');
      bad('1.5', {...ruleRow('SM', 'a'), 'ceil': 1.5}, 'ceil');
      bad('string', {...ruleRow('SM', 'a'), 'ceil': '5'}, 'ceil');
    });

    test('category: built-in key must be a known seed key; own name is checked text; never both', () {
      bad('unknown seed', ruleRow('SM', 'a', catSeed: 'SEND_MONEY:nope'), 'cat_seed');
      bad('seed not a string', {...ruleRow('SM', 'a'), 'cat_seed': 5}, 'cat_seed');
      bad('empty cat name', ruleRow('SM', 'a', catName: ''), 'cat_name');
      bad('overlong cat name', ruleRow('SM', 'a', catName: 'c' * 101), 'cat_name');
      bad('both', ruleRow('SM', 'a', catSeed: 'SEND_MONEY:rent', catName: 'x'), 'cat_name');
      expect(_ok(_v9(rules: [ruleRow('SM', 'a', catName: 'c' * 100)])).receiverRules.length, 1);
    });

    test('exact keys: a missing, an extra and a database `cat` id are refused', () {
      bad('missing ap', ruleRow('SM', 'a')..remove('ap'), '(keys)');
      bad('extra', {...ruleRow('SM', 'a'), 'x': 1}, '(keys)');
      bad('category db id', {...ruleRow('SM', 'a'), 'cat': 3}, '(keys)');
    });

    test('duplicate (kind, key) refused; same key under another kind is fine', () {
      final e = _refused(_v9(rules: [ruleRow('SM', 'a'), ruleRow('SM', 'a', lv: 0)]));
      expect((e.table, e.rowIndex, e.field), ('receiver_rules', 1, 'k'));
      expect(_ok(_v9(rules: [ruleRow('SM', 'a'), ruleRow('BG', 'a')])).receiverRules.length, 2);
    });

    test('Paybill at level 2 is ACCEPTED by the validator (restore S-4b degrades it)', () {
      final v = _ok(_v9(rules: [ruleRow('PB', 'KPLC#1', lv: 2)]));
      expect(v.receiverRules.single['lv'], 2);
    });

    test('cap: 300 rules accepted, 301 refused as tooMany', () {
      List<Map<String, Object?>> n(int c) => [for (var i = 0; i < c; i++) ruleRow('SM', 'k$i')];
      expect(_ok(_v9(rules: n(300))).receiverRules.length, 300);
      final e = _refused(_v9(rules: n(301)));
      expect((e.reason, e.table), (RestoreRejectReason.tooMany, 'receiver_rules'));
    });

    test('the 20 MB cap is unaffected: 300 maximal rules are a few tens of KB', () {
      final rows = [for (var i = 0; i < 300; i++) ruleRow('SM', '${'k' * 190}$i', name: 'n' * 200, catName: 'c' * 100, ceil: 100000000)];
      expect(fileBytes(_v9(rules: rows)).length, lessThan(kBackupMaxBytes ~/ 100));
    });
  });

  group('builder (pure)', () {
    final classes = <Map<String, Object?>>[
      {'id': 1, 'seed_key': 'SEND_MONEY:rent', 'name': 'Rent'},
      {'id': 2, 'seed_key': null, 'name': 'My own'},
    ];

    test('maps the category by seed key or by name; unknown or none gives no category', () {
      final r = buildBackupRuleRows([
        _in('SM', 'a', cat: 1),
        _in('SM', 'b', cat: 2),
        _in('SM', 'c', cat: 99),
        _in('SM', 'd'),
      ], classes);
      expect([for (final x in r.rows) (x['cat_seed'], x['cat_name'])], [
        ('SEND_MONEY:rent', null),
        (null, 'My own'),
        (null, null),
        (null, null),
      ]);
      expect(r.skipped, isEmpty);
      expect(r.repaired, 0);
    });

    test('level, ceiling and marker are carried; rows are sorted by kind then key', () {
      final r = buildBackupRuleRows([
        _in('SM', 'z', lv: 2, ceil: 700, ap: false),
        _in('BG', 'b', lv: 1, ap: true),
        _in('SM', 'a'),
      ], classes);
      expect([for (final x in r.rows) '${x['t']}${x['k']}'], ['BGb', 'SMa', 'SMz']);
      expect(r.rows[0]['ap'], 1);
      expect((r.rows[2]['lv'], r.rows[2]['ceil'], r.rows[2]['ap']), (2, 700, 0));
    });

    test('a Paybill at level 2 is written as Ask first and counted as repaired', () {
      final r = buildBackupRuleRows([_in('PB', 'KPLC#1', lv: 2, ceil: 50)], classes);
      expect(r.rows.single['lv'], 1);
      expect(r.repaired, 1);
    });

    test('a name with stray characters is tidied (counted); an empty name skips the rule', () {
      final r = buildBackupRuleRows([_in('SM', 'a', name: ' Jo\u202E  Doe\n'), _in('SM', 'b', name: ' \u0007 ')], classes);
      expect(r.rows.single['name'], 'Jo Doe');
      expect(r.repaired, 1);
      expect(r.skipped.single.toString(), 'receiver_rules row ?: name (empty)');
    });

    test('skips (never guesses): bad kind, key, level, ceiling, repeat; reports field and rule only', () {
      final r = buildBackupRuleRows([
        _in('ZZ', 'a'),
        _in('SM', ''),
        _in('SM', 'x' * 201),
        _in('SM', 'l', lv: 5),
        _in('SM', 'c0', ceil: 0),
        _in('SM', 'c1', ceil: 100000001),
        _in('SM', 'dup'),
        _in('SM', 'dup', lv: 0),
      ], classes);
      expect(r.rows.length, 1);
      expect([for (final s in r.skipped) '${s.field}/${s.rule}'], [
        'k/format', 'ceil/range', 'ceil/range', 'k/duplicate', 'lv/range', 'k/format', 't/enum',
      ]);
    });

    test('whatever it builds, the validator accepts', () {
      final r = buildBackupRuleRows([
        for (var i = 0; i < 40; i++) _in(kBackupRuleTypes[i % 4], 'key$i', lv: i % 3, cat: i % 3 == 0 ? 1 : 2, ceil: i.isEven ? i + 1 : null, ap: i % 5 == 0),
      ], classes);
      expect(_ok(_v9(rules: r.rows)).receiverRules.length, r.rows.length);
    });
  });

  group('export (real in-memory database)', () {
    test('no source wired: section empty, count 0, file validates (nothing travels yet)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final e = await _svc(db, null).export();
      final j = _json(e.bytes);
      expect(j['schema_version'], 9);
      expect(_ruleRows(j), isEmpty);
      expect((j['counts']! as Map)['receiver_rules'], 0);
      expect(e.receiverRules, 0);
      expect(_ok(j).hasRulesSection, isTrue);
    });

    test('with rules: section present with category by seed key / name, ceiling, marker; round-trips', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final rent = await seedId(db, 'SEND_MONEY:rent');
      final own = await addClass(db, 'SEND_MONEY', 'Invented Hobby');
      final e = await _svc(db, () async => [
            _in('SM', 'jo', name: 'Jo', lv: 2, cat: rent, ceil: 120000),
            _in('PO', 'pat', name: 'Pat', lv: 1, cat: own, ap: true),
            _in('BG', 'shop', name: 'Shop', lv: 0),
          ]).export();
      final j = _json(e.bytes);
      expect(j.keys.toList(), kBackupTopLevelKeys);
      expect(e.receiverRules, 3);
      final rows = {for (final r in _ruleRows(j)) '${r['t']}.${r['k']}': r};
      expect(rows['SM.jo']!['cat_seed'], 'SEND_MONEY:rent');
      expect(rows['SM.jo']!['cat_name'], isNull);
      expect((rows['SM.jo']!['lv'], rows['SM.jo']!['ceil']), (2, 120000));
      expect(rows['PO.pat']!['cat_seed'], isNull);
      expect(rows['PO.pat']!['cat_name'], 'Invented Hobby');
      expect(rows['PO.pat']!['ap'], 1);
      expect(rows['BG.shop']!['lv'], 0);
      // No database id travels anywhere in a rule row.
      for (final r in rows.values) {
        expect(r.keys.toList(), kBackupRuleKeys);
      }
      final v = _ok(j);
      expect(v.receiverRules.length, 3);
      expect(e.skippedCount, 0);
    });

    test('a rule whose category is gone is written with no category', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final e = await _svc(db, () async => [_in('SM', 'jo', cat: 987654)]).export();
      final r = _ruleRows(_json(e.bytes)).single;
      expect((r['cat_seed'], r['cat_name']), (null, null));
    });

    test('export through the real store adapter: details OFF gives an empty section (no rules exist)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final store = PrefsRuleStore();
      expect(await store.setLevel(ReceiverType.sendMoney, 'jo', name: 'Jo', level: RuleLevel.askFirst, at: DateTime.utc(2026, 11, 25)), isTrue);
      var e = await _svc(db, () => backupRulesFrom(store)).export();
      expect(_ruleRows(_json(e.bytes)).single['k'], 'jo');
      await (await SharedPreferences.getInstance()).setBool(kReceiverDetailsPrefsKey, false);
      e = await _svc(db, () => backupRulesFrom(store)).export();
      expect(_ruleRows(_json(e.bytes)), isEmpty);
      expect((_json(e.bytes)['counts']! as Map)['receiver_rules'], 0);
    });

    test('an unmappable rule is left out and reported, the rest still export (counted in skipped)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      final e = await _svc(db, () async => [_in('SM', 'ok'), _in('SM', 'bad', ceil: 0)]).export();
      expect(e.receiverRules, 1);
      expect(e.skippedCount, 1);
      expect(e.skipped.single.table, 'receiver_rules');
      expect(e.skipped.single.toString(), isNot(contains('bad')));
    });

    test('a failing rules source fails the export (a file silently missing rules would lose them on Undo)', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      await expectLater(_svc(db, () async => throw StateError('prefs')).export(), throwsStateError);
    });

    test('over 300 rules: the export refuses (BackupTooLarge), never a file the app cannot read', () async {
      final db = await openTestDb();
      addTearDown(db.close);
      await expectLater(
        _svc(db, () async => [for (var i = 0; i < 301; i++) _in('SM', 'k$i')]).export(),
        throwsA(isA<BackupTooLarge>().having((e) => e.what, 'what', 'receiver_rules')),
      );
      final ok = await _svc(db, () async => [for (var i = 0; i < 300; i++) _in('SM', 'k$i')]).export();
      expect(ok.receiverRules, 300);
    });
  });
}
