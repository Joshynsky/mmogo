import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/classification_dao.dart';
import 'withdrawal_use_block.dart';

/// §WIDGET.WITHDRAWAL_USE_CREATE (0.2.1, PM #33) - the choices of "What was this money for?":
/// ONLY the user's own Cash list (group `CASH_USE`), empty until they make one. A failed read
/// throws; the callers already guard it (no chips, Cash only still works).
Future<List<WdChoice>> loadWithdrawalUseChoices(Database db) async =>
    [for (final c in await ClassificationDao.fetchCashUseClassifications(db)) WdChoice(c.id, c.name)];

/// 0.2.1 - creates a category from the "+ New" chip of [WithdrawalUseBlock], INTO the Cash list.
/// Rules: empty is refused, at most [classificationNameMaxLength] characters, and a duplicate is
/// checked ONLY inside the Cash list (case-insensitive; a Send Money "Rent" does not block a Cash
/// "Rent"). Returns the new id and the reloaded Cash list, or an error message. Never throws.
Future<WdCreateResult> createWithdrawalUseCategory(Database db, String name) async {
  final clean = name.trim();
  if (clean.isEmpty) return const WdCreateResult.error('Type a name first.');
  if (clean.length > classificationNameMaxLength) {
    return const WdCreateResult.error('That name is too long. Use $classificationNameMaxLength characters or fewer.');
  }
  try {
    final existing = await ClassificationDao.fetchCashUseClassifications(db);
    if (existing.any((c) => c.name.toLowerCase() == clean.toLowerCase())) {
      return WdCreateResult.error('A category named "$clean" already exists.');
    }
    final id = await ClassificationDao.createCashUseClassification(db, name: clean);
    return WdCreateResult.ok(id, await loadWithdrawalUseChoices(db));
  } on DatabaseException catch (e) {
    return WdCreateResult.error(e.isUniqueConstraintError() ? 'A category named "$clean" already exists.' : 'Could not create category. Try again.');
  } catch (_) {
    return const WdCreateResult.error('Could not create category. Try again.');
  }
}
