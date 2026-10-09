// DB6 (Judge C-A9): the Cash picker lists only the three M-Pesa groups.
// Required test on a FRESH v3 database (built from the frozen constants), plus
// a check that a populated 0.1.1 (v2) database gives the same picker as before.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/data/db/db_open.dart';
import 'package:mmogo/data/db/migration_v3_ddl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../fixtures/v2_fixture.dart';

const _six = {'Family/Friends', 'Rent', 'Transport', 'Groceries', 'Rent Payment', 'Shopping'};

Future<Database> _freshV3() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) => createFreshV3ForTest(db)));
}

/// The pre-fix query (no group whitelist), same ordering, for the control.
Future<List<Map<String, Object?>>> _unfilteredPicker(Database db) => db.rawQuery('''
  SELECT c.id, c.group_id, c.name FROM classifications c
  JOIN classification_groups g ON g.id = c.group_id
  WHERE c.active = 1 AND g.enabled = 1 ORDER BY c.id ASC''');

void main() {
  late Database db;
  setUp(() async {
    db = await _freshV3();
    final pochi = firstIntOf(await db.rawQuery(
        "SELECT id FROM classification_groups WHERE code = 'POCHI_LA_BIASHARA'"))!;
    // A user's own category in the (now enabled) Pochi group.
    await db.insert('classifications',
        {'group_id': pochi, 'name': 'Fuel', 'active': 1, 'created_at': 1790000000000});
  });
  tearDown(() => db.close());

  test('fresh v3: picker ids are {1..6}, the six distinct names; Fuel, Withdrawal, Airtime absent',
      () async {
    final items = await ClassificationDao.fetchFlatActiveClassifications(db);
    expect(items.map((i) => i.id).toSet(), {1, 2, 3, 4, 5, 6});
    expect(items.map((i) => i.name).toSet(), _six);
    expect(items, hasLength(6));
    final names = items.map((i) => i.name.toLowerCase()).toSet();
    expect(names, isNot(contains('fuel')));
    expect(names, isNot(contains('withdrawal')));
    expect(names, isNot(contains('airtime')));
  });

  test('CONTROL: the same database WITHOUT the whitelist leaks Fuel, Withdrawal and Airtime '
      '(so the test above fails if the filter is removed)', () async {
    final rows = await _unfilteredPicker(db);
    final names = rows.map((r) => (r['name']! as String).toLowerCase()).toSet();
    expect(names, containsAll(['fuel', 'withdrawal', 'airtime']));
    expect(rows.map((r) => r['id']).toSet(), isNot({1, 2, 3, 4, 5, 6}));
  });

  test('CONTROL: a names-only check cannot see a Pochi leak (the shared names are deduped away); '
      'the id check and the Fuel check are what catch it', () async {
    final unfiltered = await _unfilteredPicker(db);
    // dedupe by lower-case name keeping the lowest id, as the DAO does
    final seen = <String>{};
    final ids = <int>[];
    for (final r in unfiltered) {
      if (seen.add((r['name']! as String).trim().toLowerCase())) ids.add(r['id']! as int);
    }
    final pochiIds = {15, 16, 17};
    expect(ids.toSet().intersection(pochiIds), isEmpty,
        reason: 'Pochi Transport/Groceries/Shopping are shadowed by lower ids, names alone look fine');
  });

  test('a populated 0.1.1 (v2) database: the picker is exactly what the unfiltered query gave '
      '(Pochi group is disabled there), and Pochi ids never appear', () async {
    final dir = Directory.systemTemp.createTempSync('mmogo_picker_');
    final v2 = await buildV2Database('${dir.path}${Platform.pathSeparator}v2.db');
    // an inactive Pochi user row and an active one in the DISABLED Pochi group
    final pochi = firstIntOf(await v2.rawQuery(
        "SELECT id FROM classification_groups WHERE code = 'POCHI_LA_BIASHARA'"))!;
    await v2.insert('classifications',
        {'group_id': pochi, 'name': 'Fuel', 'active': 1, 'created_at': kFixtureNow});

    final after = await ClassificationDao.fetchFlatActiveClassifications(v2);
    // before-the-change behaviour, recomputed from the old query + same dedupe
    final seen = <String>{};
    final before = <(int, String)>[];
    for (final r in await _unfilteredPicker(v2)) {
      final name = r['name']! as String;
      if (seen.add(name.trim().toLowerCase())) before.add((r['id']! as int, name));
    }
    before.sort((a, b) => a.$2.toLowerCase().compareTo(b.$2.toLowerCase()));
    expect(after.map((i) => (i.id, i.name)).toList(), before);
    expect(after.map((i) => i.name), isNot(contains('Fuel')));
    expect(after, isNotEmpty);
    await v2.close();
    dir.deleteSync(recursive: true);
  });
}
