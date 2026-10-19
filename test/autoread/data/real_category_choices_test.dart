// §AUTOREAD.REAL_CATEGORY_CHOICES (I1): the Categorize sheet's categories are the
// same classifications Add lists, scoped to the item's type group.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/real_category_choices.dart';
import 'package:mmogo/autoread/ui/category_choices.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/data/db/schema.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> _freshDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
            await AppSchema.createSchema(db);
            await AppSchema.seed(db);
          }));
}

Future<int> _group(Database db, String code) async =>
    (await ClassificationDao.fetchGroups(db)).firstWhere((g) => g.code == code).id;

void main() {
  late Database db;
  setUp(() async => db = await _freshDb());
  tearDown(() => db.close());

  test('lists exactly what Add lists for the type, ids are the decimal database ids', () async {
    final choices = RealCategoryChoices(db, SmsSourceType.sendMoney);
    final got = await choices.categories();
    final add = await ClassificationDao.fetchActiveClassifications(db, groupId: await _group(db, 'SEND_MONEY'));
    expect(got, isNotEmpty);
    expect([for (final c in got) c.id], [for (final i in add) '${i.id}']);
    expect([for (final c in got) c.name], [for (final i in add) i.name]);
  });

  test('other types see their own group only', () async {
    final pay = await RealCategoryChoices(db, SmsSourceType.payBill).categories();
    final payAdd = await ClassificationDao.fetchActiveClassifications(db, groupId: await _group(db, 'PAYBILL'));
    expect(pay.map((c) => c.id), payAdd.map((i) => '${i.id}'));
    final send = await RealCategoryChoices(db, SmsSourceType.sendMoney).categories();
    expect(pay.map((c) => c.id).toSet().intersection(send.map((c) => c.id).toSet()), isEmpty);
  });

  test('create trims, saves in the type group and shows up in Add too', () async {
    final choices = RealCategoryChoices(db, SmsSourceType.buyGoods);
    final made = await choices.create('  Sample Treats  ');
    expect(made.name, 'Sample Treats');
    expect((await choices.categories()).any((c) => c.id == made.id && c.name == 'Sample Treats'), isTrue);
    final add = await ClassificationDao.fetchActiveClassifications(db, groupId: await _group(db, 'BUY_GOODS'));
    expect(add.any((i) => '${i.id}' == made.id), isTrue);
    // Not in another type's list.
    expect((await RealCategoryChoices(db, SmsSourceType.sendMoney).categories()).any((c) => c.id == made.id), isFalse);
  });

  test('duplicate name, ignoring case and spaces, is refused', () async {
    final choices = RealCategoryChoices(db, SmsSourceType.sendMoney);
    final existing = (await choices.categories()).first.name;
    for (final name in [existing, ' ${existing.toUpperCase()} ', existing.toLowerCase()]) {
      await expectLater(
          choices.create(name), throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.duplicate)));
    }
  });

  test('empty and over-100 names are refused; exactly 100 is fine', () async {
    final choices = RealCategoryChoices(db, SmsSourceType.sendMoney);
    await expectLater(choices.create('   '),
        throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.empty)));
    await expectLater(choices.create('x' * 101),
        throwsA(isA<CategoryNameError>().having((e) => e.reason, 'reason', CategoryNameReason.tooLong)));
    expect((await choices.create('y' * 100)).name.length, 100);
  });

  test('the same name in ANOTHER type group is allowed (groups are separate, as in Add)', () async {
    final send = RealCategoryChoices(db, SmsSourceType.sendMoney);
    final name = (await send.categories()).first.name;
    final buy = RealCategoryChoices(db, SmsSourceType.buyGoods);
    final inBuy = (await buy.categories()).any((c) => c.name.toLowerCase() == name.toLowerCase());
    if (!inBuy) expect((await buy.create(name)).name, name);
  });

  test('withdrawal and airtime offer only their one built-in category and refuse create', () async {
    for (final t in [SmsSourceType.agentWithdrawal, SmsSourceType.airtime]) {
      final c = RealCategoryChoices(db, t);
      expect(await c.categories(), hasLength(1));
      await expectLater(c.create('Another'), throwsStateError);
    }
  });
}
