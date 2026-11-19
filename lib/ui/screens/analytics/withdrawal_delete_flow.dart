import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/linked_cash_dao.dart';
import '../../../data/db/transaction_dao.dart';
import '../../../domain/format/money.dart';
import '../../copy/withdrawal_copy.dart';
import '../../widgets/two_button_dialog.dart';

/// What a delete did: the id Undo restores and the toast words.
class DeleteOutcome {
  const DeleteOutcome({required this.undoId, required this.message});
  final int undoId;
  final String message;
}

/// §ANALYTICS.WITHDRAWAL_DELETE (0.2.1) — delete with the withdrawal prompts, side by side:
///  - a withdrawal WITH a linked Cash entry: Cancel | Delete both (one soft delete takes the pair);
///  - a plain withdrawal: Cancel | Delete;
///  - a linked Cash entry: Keep withdrawal (the entry goes, the withdrawal is marked Cash only)
///    | Delete withdrawal too (soft delete of the withdrawal, which takes the entry with it).
/// Every other row is deleted at once as before. Returns null when the user cancelled.
Future<DeleteOutcome?> deleteWithPrompt(
  BuildContext context,
  Database db,
  AnalyticsTransactionRow tx,
) async {
  if (tx.sourceType == 'AGENT_WITHDRAWAL') {
    final entries = await LinkedCashDao.linkedEntriesOf(db, tx.id);
    if (!context.mounted) return null;
    final linked = entries.isNotEmpty;
    final both = await showTwoButtonDialog(
      context,
      dialogKey: const Key('deleteWithdrawalDialog'),
      title: kWdDeleteWithdrawalTitle,
      body: linked
          ? wdDeleteBothBody(tx.amountCents, [for (final e in entries) '${e.classificationName} ${kshTrim(e.amountCents)}'])
          : wdDeletePlainBody(tx.transactionCostCents ?? 0),
      leftLabel: kWdCancel,
      rightLabel: linked ? kWdDeleteBoth : kWdDelete,
      danger: true,
    );
    if (both != true) return null;
    await TransactionDao.softDelete(db, id: tx.id);
    return DeleteOutcome(undoId: tx.id, message: linked ? kWdMovedBoth : '${tx.displayName} moved to Recently Deleted');
  }
  if (tx.sourceType == 'CASH' && tx.fromWithdrawal) {
    final parent = tx.parentTransactionId!;
    final rows = await db.rawQuery('SELECT amount_cents FROM transactions WHERE id = ?', [parent]);
    final w = rows.isEmpty ? 0 : (rows.first['amount_cents']! as num).toInt();
    if (!context.mounted) return null;
    final alsoWithdrawal = await showTwoButtonDialog(
      context,
      dialogKey: const Key('deleteLinkedEntryDialog'),
      title: wdDeleteEntryTitle(tx.classificationName),
      body: wdDeleteEntryBody(w),
      leftLabel: kWdKeepWithdrawal,
      rightLabel: kWdDeleteWithdrawalToo,
      danger: true,
    );
    if (alsoWithdrawal == null) return null;
    if (alsoWithdrawal) {
      await TransactionDao.softDelete(db, id: parent);
      return DeleteOutcome(undoId: parent, message: kWdMovedBoth);
    }
    await TransactionDao.softDelete(db, id: tx.id);
    if ((await LinkedCashDao.linkedEntriesOf(db, parent)).isEmpty) {
      await LinkedCashDao.markCashOnly(db, withdrawalId: parent);
    }
    return DeleteOutcome(undoId: tx.id, message: kWdMovedEntryKept);
  }
  await TransactionDao.softDelete(db, id: tx.id);
  return DeleteOutcome(undoId: tx.id, message: '${tx.displayName} moved to Recently Deleted');
}
