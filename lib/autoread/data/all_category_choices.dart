/// §AUTOREAD.ALL_CATEGORY_CHOICES - every active category of the Send Money, Paybill, Buy Goods and Pochi
/// groups, as one list. The Remembered page's level sheet picks the Ask first category from it, and the
/// Notifications page turns a category number into its name with it. Read only; "+ New" is refused
/// here (new categories are made on Add). Auto-read build only.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../ui/category_choices.dart';

class AllCategoryChoices implements CategoryChoices {
  AllCategoryChoices(this._db);
  final Future<Database> Function() _db;

  @override
  Future<List<CategoryChoice>> categories() async {
    final rows = await (await _db()).rawQuery('''
      SELECT c.id, c.name
      FROM classifications c
      JOIN classification_groups g ON g.id = c.group_id
      WHERE c.active = 1 AND g.enabled = 1 AND g.code IN ('SEND_MONEY','PAYBILL','BUY_GOODS','POCHI_LA_BIASHARA')
      ORDER BY c.name COLLATE NOCASE ASC, c.id ASC
    ''');
    return [for (final r in rows) CategoryChoice(id: '${r['id']}', name: r['name']! as String)];
  }

  @override
  Future<CategoryChoice> create(String name) async => throw StateError('New categories are made on Add.');
}
