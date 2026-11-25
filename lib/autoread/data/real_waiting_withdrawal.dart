/// §AUTOREAD.REAL_WAITING_WITHDRAWAL — the withdrawal methods of RealWaitingRepository (0.2.1; split out 0.2.2).
/// A part of real_waiting_repository.dart so it can use the repository's private state; no behaviour change.
part of 'real_waiting_repository.dart';

extension RealWaitingWithdrawals on RealWaitingRepository {
  /// 0.2.1: a parsed withdrawal item is recorded as a withdrawal (under its own built-in category
  /// [withdrawalCategoryId]) and decided in the same step: [useCategoryId] null = Cash only (the
  /// withdrawal is marked decided), else a linked Cash entry for the full amount in that category.
  /// Same save order as [saveCategory]; the decision follows the transaction, so a crash between
  /// them leaves an undecided withdrawal that the "need a decision" item then shows.
  Future<void> saveWithdrawal(String id, String withdrawalCategoryId, {int? useCategoryId}) => _locked(() async {
        final cls = int.tryParse(withdrawalCategoryId);
        if (cls == null) throw ArgumentError.value(withdrawalCategoryId, 'withdrawalCategoryId', 'not a category id');
        final rowId = await _saveInner(id, cls);
        if (rowId != null) {
          final db = await _database();
          if (useCategoryId == null) {
            await LinkedCashDao.markCashOnly(db, withdrawalId: rowId);
          } else {
            await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: rowId, classificationId: useCategoryId);
          }
          // N2: _saveInner already told Home "saved", but BEFORE the linked Cash entry / decision existed, so
          // Home re-read a half-written state (old leftover, no Cash row). Tell it again now the step is done.
          _onSaved();
        }
        await _publish();
      });

  /// 0.2.1: every recorded withdrawal still waiting for "Cash only" or a category (newest first).
  Future<List<AnalyticsTransactionRow>> undecidedWithdrawals() async =>
      LinkedCashDao.undecidedWithdrawals(await _database());

  /// Reloads [undecided]; on a failure it keeps what it showed.
  Future<void> refreshUndecided() async {
    try {
      final rows = await undecidedWithdrawals();
      if (!_closed) undecided.value = rows;
    } catch (_) {
      // Keeps the last list.
    }
  }

  /// 0.2.1: decides a recorded withdrawal from the "need a decision" item.
  Future<void> decideWithdrawal(int withdrawalId, {int? useCategoryId}) async {
    final db = await _database();
    if (useCategoryId == null) {
      await LinkedCashDao.markCashOnly(db, withdrawalId: withdrawalId);
    } else {
      await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: withdrawalId, classificationId: useCategoryId);
    }
    _onSaved();
    await refreshUndecided();
  }

  /// 0.2.1: "Cash only for all": every id in one database transaction (all or nothing).
  Future<void> decideAllCashOnly(List<int> withdrawalIds) async {
    final db = await _database();
    await LinkedCashDao.markManyCashOnly(db, withdrawalIds: withdrawalIds);
    _onSaved();
    await refreshUndecided();
  }

  /// 0.2.1: the Cash list (and only it) for "What was this money for?"; empty until the user makes one.
  Future<List<ClassificationItem>> withdrawalUseChoices() async =>
      ClassificationDao.fetchCashUseClassifications(await _database());

  /// 0.2.1: "+ New" in "What was this money for?" - creates INTO the Cash list (duplicates checked only there).
  Future<WdCreateResult> createWithdrawalUseCategory(String name) async =>
      wd_create.createWithdrawalUseCategory(await _database(), name);

}
