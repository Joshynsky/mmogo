import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../data/db/analytics_dao.dart';
import '../../../data/db/linked_cash_dao.dart';
import '../../copy/withdrawal_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/two_button_dialog.dart';
import 'edit_sheet.dart' show AnalyticsDeleteRequest;
import 'linked_entry_sheet.dart';
import 'sheet_parts.dart';
import 'withdrawal_use_section.dart';

/// §ANALYTICS.LINKED_ENTRY_FLOW (0.2.1) — what the Analytics screen does around the
/// withdrawal sheet's "What was this money for?" and the linked Cash entry sheet.

/// The row of one live Cash entry (for the delete prompt and the sheet), or null.
Future<AnalyticsTransactionRow?> linkedEntryRow(Database db, int entryId) =>
    LinkedCashDao.liveEntryRow(db, entryId);

/// Saves the withdrawal sheet's pick. A category adds or moves the linked entry; Cash only
/// on a withdrawal that has entries asks first (the entries leave spending; Undo is not
/// offered here, they sit in Recently deleted for an hour). Returns true when something changed.
Future<bool> applyWithdrawalPick(BuildContext context, Database db, AnalyticsTransactionRow tx, WithdrawalPick pick) async {
  final id = pick.categoryId;
  if (id != null) {
    await LinkedCashDao.setWithdrawalCategory(db, withdrawalId: tx.id, classificationId: id);
    return true;
  }
  final entries = await LinkedCashDao.linkedEntriesOf(db, tx.id);
  if (entries.isEmpty) {
    await LinkedCashDao.markCashOnly(db, withdrawalId: tx.id);
    return true;
  }
  if (!context.mounted) return false;
  final remove = await showTwoButtonDialog(
    context,
    dialogKey: const Key('cashOnlyAskDialog'),
    title: kWdCashOnlyAskTitle,
    body: wdCashOnlyAskBody(entries.length),
    leftLabel: kWdKeepIt,
    rightLabel: kWdRemoveLinked,
    danger: true,
  );
  if (remove != true) return false;
  await LinkedCashDao.markCashOnly(db, withdrawalId: tx.id, removeLinked: true);
  return true;
}

/// How the linked entry sheet ended.
enum LinkedEntryEnd { nothing, saved, deleteRequested }

/// Opens the linked entry sheet for [entryId] (and, via "Add another entry", new ones).
/// Saves with [LinkedCashDao]. Returns [LinkedEntryEnd.deleteRequested] when the user taps Delete
/// (the caller runs the delete prompt on [linkedEntryRow]).
Future<LinkedEntryEnd> openLinkedEntryFlow(BuildContext context, Database db, AppPalette palette, int entryId) async {
  final row = await linkedEntryRow(db, entryId);
  if (row == null || row.parentTransactionId == null || !context.mounted) return LinkedEntryEnd.nothing;
  final withdrawalId = row.parentTransactionId!;
  var changed = false;
  int? editing = entryId;
  while (true) {
    final w = await db.rawQuery('SELECT amount_cents, transaction_occurred_at FROM transactions WHERE id = ?', [withdrawalId]);
    if (w.isEmpty || !context.mounted) break;
    final wCents = (w.first['amount_cents']! as num).toInt();
    final wAt = DateTime.fromMillisecondsSinceEpoch(w.first['transaction_occurred_at']! as int);
    final entries = await LinkedCashDao.linkedEntriesOf(db, withdrawalId);
    final mine = editing == null ? null : entries.where((e) => e.id == editing).firstOrNull;
    final left = await LinkedCashDao.remainingCents(db, withdrawalId);
    if (!context.mounted) break;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true, // keep the header (title, Delete) below the status bar
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x59000000),
      builder: (ctx) => Theme(
        data: analyticsPickerTheme(palette),
        child: LinkedEntrySheet(
          db: db,
          palette: palette,
          withdrawalCents: wCents,
          occurredAt: wAt,
          maxCents: left + (mine?.amountCents ?? 0),
          isNew: mine == null,
          categoryId: mine?.classificationId,
          categoryName: mine?.classificationName,
          amountCents: mine?.amountCents,
        ),
      ),
    );
    if (result is AnalyticsDeleteRequest) return LinkedEntryEnd.deleteRequested;
    if (result is! LinkedEntryResult) break;
    if (mine == null) {
      await LinkedCashDao.createLinkedCash(db,
          withdrawalId: withdrawalId, classificationId: result.categoryId, amountCents: result.amountCents);
    } else {
      await LinkedCashDao.updateLinkedEntry(db,
          entryId: mine.id, amountCents: result.amountCents, classificationId: result.categoryId);
    }
    changed = true;
    if (!result.addAnother) break;
    editing = null;
  }
  return changed ? LinkedEntryEnd.saved : LinkedEntryEnd.nothing;
}
