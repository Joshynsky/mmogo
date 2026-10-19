/// §AUTOREAD.REAL_CATEGORY_CHOICES — the real [CategoryChoices] for the
/// Categorize sheet: the SAME classifications the Add screen lists and creates,
/// scoped to the group of the waiting item's type.
///
/// Ids: the sheet uses String ids, the database uses int ids. The String is
/// the int in decimal (`'7'` is classification 7); the repository's
/// `saveCategory` turns it back with `int.parse`.
///
/// Withdrawal and Airtime have ONE locked built-in category in Add (found by
/// `seed_key`); the sheet offers only that one, and `create` refuses (the
/// sheet shows its generic "could not create" line), the same as Add.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/classification_dao.dart';
import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/screens/add/add_draft.dart';
import '../ui/category_choices.dart';

class RealCategoryChoices implements CategoryChoices {
  RealCategoryChoices(this._db, this._type);

  final Database _db;
  final SmsSourceType _type;

  Future<int?> _groupId() async {
    final groups = await ClassificationDao.fetchGroups(_db);
    for (final g in groups) {
      if (g.code == _type.dbValue) return g.id;
    }
    return null;
  }

  Future<List<ClassificationItem>> _items() async {
    final seed = AddDraft.fixedSeedKey(_type.dbValue);
    if (seed != null) {
      final one = await ClassificationDao.fetchActiveBySeedKey(_db, seedKey: seed);
      return one == null ? const <ClassificationItem>[] : [one];
    }
    final group = await _groupId();
    if (group == null) return const <ClassificationItem>[];
    return ClassificationDao.fetchActiveClassifications(_db, groupId: group);
  }

  @override
  Future<List<CategoryChoice>> categories() async => [
        for (final i in await _items()) CategoryChoice(id: '${i.id}', name: i.name),
      ];

  @override
  Future<CategoryChoice> create(String name) async {
    if (AddDraft.fixedSeedKey(_type.dbValue) != null) {
      throw StateError('This type has one built-in category.');
    }
    final group = await _groupId();
    if (group == null) throw StateError('No category group for this type.');
    final existing = (await _items()).map((i) => i.name);
    final v = checkNewCategoryName(name, existing);
    try {
      final id = await ClassificationDao.createClassification(_db, groupId: group, name: v);
      return CategoryChoice(id: '$id', name: v);
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw const CategoryNameError(CategoryNameReason.duplicate);
      }
      rethrow;
    }
  }
}
