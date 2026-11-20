/// §AUTOREAD.REAL_WAITING_ACTIONS — the [WaitingActions] the Notifications page
/// uses in the autoread flavor: every button does its real job through the
/// [RealWaitingRepository]. Built by `NotificationsRoute` inside
/// `if (kAutoReadCompiled)`.
///
/// - Parse: the repository parses and the row turns into a choose-a-category
///   row in place (no toast). Airtime recorded on its own keeps its Undo toast.
/// - Pick a category in the row: the same `repo.saveCategory` call the
///   Categorize sheet makes; a quiet note says what was recorded.
/// - Later: the row stays, without the Later chip, under To categorize.
/// - Categorize: an item not parsed yet is parsed first; then the sheet opens
///   with the same categories Add shows; Save writes the real transaction.
/// - Paste: after the paste sheet closed, Add opens. Add is paste-first: its
///   Paste card is the first thing on it.
/// - Remove: the repository removes it (unreadable or gone rows only).
/// - Parse all: each readable item is parsed, one after another.
/// - Details: a one-time look at the held message, shown in a sheet.
library;

import 'package:flutter/material.dart';

import '../../data/db/analytics_dao.dart' show AnalyticsTransactionRow;
import '../../domain/format/money.dart';
import '../../ui/widgets/withdrawal_use_block.dart' show WdChoice, WdCreateResult;
import '../../ui/shell/routes.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';
import '../logic/airtime_auto.dart';
import '../logic/held_describe.dart' show describeReadable;
import '../../ui/widgets/pill_toast.dart';
import '../ui/categorize_sheet.dart';
import '../ui/message_details_sheet.dart';
import '../ui/notifications_autoread_copy.dart';
import '../ui/notifications/rules_page_state.dart';
import '../wiring/rules_wiring.dart';
import '../model/rule_hint.dart';
import '../ui/remove_confirm.dart';
import '../ui/todo_choose.dart';
import '../ui/todo_copy.dart';
import '../ui/waiting_section.dart';
import '../ui/withdrawal_categorize_sheet.dart';
import 'real_waiting_repository.dart';

/// [choosing] and [note] belong to the page (they must outlive a rebuild of
/// the route); a caller that passes none gets fresh ones.
WaitingActions buildRealWaitingActions(
  BuildContext context,
  RealWaitingRepository repo, {
  ChoosingIds? choosing,
  ValueNotifier<String?>? note,
  RulesPageState? rules,
}) {
  final ids = choosing ?? ChoosingIds();
  final quiet = note ?? ValueNotifier<String?>(null);

  void toast(String text) => PillToast.show(text);

  /// Toast for a Parse that recorded Airtime on its own: with Undo (J2). A top pill (stays 6 s or more).
  void toastAutoRecorded(AutoRecorded e) => PillToast.show(
        autoRecordedToast(kshTrim(e.amountCents)),
        actionLabel: kAutoRecordedUndo,
        onAction: () async {
          await repo.undoAutoRecord(e);
          toast(kAutoRecordedUndoneToast);
        },
      );

  Future<void> parse(WaitingItem item) async {
    // The row turns into a choose row the moment it is parsed (marked first so
    // it never flashes as a To categorize row).
    ids.add(item.id);
    try {
      final before = repo.airtime.recordedCount; // a counter: the list can stay the same length (cap, purge)
      final r = await repo.parse(item.id);
      final recorded = repo.airtime.lastRecorded;
      if (r == ParseOutcome.parsed && repo.airtime.recordedCount > before && recorded != null) {
        toastAutoRecorded(recorded);
      }
      if (repo.itemById(item.id)?.kind != WaitingKind.waitingCategory) ids.remove(item.id);
    } catch (_) {
      // The row stays as it was; a later ingest shows the true state.
      ids.remove(item.id);
    }
  }

  Future<void> pickCategory(WaitingItem item, String categoryId) async {
    await repo.saveCategory(item.id, categoryId); // the call the Categorize sheet makes
    ids.remove(item.id);
    final f = item.parsed;
    if (f != null) quiet.value = noteRecorded(describeReadable(f));
  }

  void later(WaitingItem item) {
    ids.remove(item.id);
    quiet.value = kNoteMovedToCategorize;
  }

  Future<void> categorize(WaitingItem item) async {
    try {
      var target = item;
      if (target.kind == WaitingKind.readyToParse) {
        if (await repo.parse(item.id) != ParseOutcome.parsed) return;
        final parsed = repo.itemById(item.id);
        if (parsed == null || parsed.kind != WaitingKind.waitingCategory) return;
        target = parsed;
      }
      final choices = await repo.categoryChoicesFor(target);
      if (!context.mounted) return;
      await showCategorizeSheet(
        context,
        item: target,
        choices: choices,
        onSave: (categoryId) => repo.saveCategory(target.id, categoryId),
      );
    } catch (_) {
      // Nothing is saved; the row stays.
    }
  }

  // 0.2.1 rules (Suggested + Ask first): an Ask first row asks "Record as [Category]?". Yes records
  // with the person's category (the ledger hook then counts it); Change category opens the
  // Categorize sheet; Categorize later puts the row under To categorize for this visit. A category
  // that cannot be saved for this person falls back to the sheet (nothing is half-saved).
  Future<void> askFirstYes(WaitingItem item, RuleHint hint) async {
    final cat = hint.suggested.isEmpty ? null : hint.suggested.first;
    if (cat == null) return categorize(item);
    try {
      await repo.saveCategory(item.id, '$cat');
      final f = item.parsed;
      if (f != null) quiet.value = noteRecorded(describeReadable(f));
    } catch (_) {
      await categorize(item);
    }
  }

  void askFirstLater(WaitingItem item, RuleHint hint) {
    rules?.markLater(item.id);
    quiet.value = kNoteMovedToCategorize;
  }

  // 0.2.1: withdrawals. A waiting withdrawal ITEM is recorded and decided in one step.
  Future<void> reloadUndecided() => repo.refreshUndecided(); // the repository's own notifier: item, chip and bell

  Future<List<WdChoice>> useChoices() async => [for (final c in await repo.withdrawalUseChoices()) WdChoice(c.id, c.name)];

  Future<WdCreateResult> createUseCategory(String name) => repo.createWithdrawalUseCategory(name);

  Future<String> withdrawalCategoryId(WaitingItem item) async =>
      (await (await repo.categoryChoicesFor(item)).categories()).first.id;

  Future<void> withdrawalCashOnly(WaitingItem item) async {
    await repo.saveWithdrawal(item.id, await withdrawalCategoryId(item));
    ids.remove(item.id);
    final f = item.parsed;
    if (f != null) quiet.value = noteRecorded(describeReadable(f));
  }

  Future<void> withdrawalCategorize(WaitingItem item) async {
    final f = item.parsed;
    if (f == null) return;
    final wid = await withdrawalCategoryId(item);
    final choices = await useChoices();
    if (!context.mounted) return;
    await showWithdrawalCategorizeSheet(
      context,
      title: describeReadable(f),
      amountCents: f.amountCents,
      choices: choices,
      onCreate: createUseCategory,
      onSave: (cat) async {
        await repo.saveWithdrawal(item.id, wid, useCategoryId: cat);
        ids.remove(item.id);
        quiet.value = noteRecorded(describeReadable(f));
      },
    );
  }

  Future<void> decisionCashOnly(AnalyticsTransactionRow row) async {
    await repo.decideWithdrawal(row.id);
    await reloadUndecided();
  }

  /// "Cash only for all": one database transaction; a failure leaves everything as it was and rethrows
  /// (the sheet shows its error).
  Future<void> decisionCashOnlyAll(List<AnalyticsTransactionRow> rows) =>
      repo.decideAllCashOnly([for (final r in rows) r.id]);

  Future<void> decisionCategorize(AnalyticsTransactionRow row) async {
    final choices = await useChoices();
    if (!context.mounted) return;
    final who = (row.counterpartyLabel ?? '').isEmpty ? '' : ' from ${row.counterpartyLabel}';
    await showWithdrawalCategorizeSheet(
      context,
      title: 'Withdrew ${kshTrim(row.amountCents)}$who',
      amountCents: row.amountCents,
      choices: choices,
      onCreate: createUseCategory,
      onSave: (cat) async {
        await repo.decideWithdrawal(row.id, useCategoryId: cat);
        await reloadUndecided();
      },
    );
  }

  Future<void> remove(WaitingItem item) async {
    try {
      await repo.remove(item.id);
      toast(kToastRemoved);
    } catch (_) {
      // The row stays.
    }
  }

  Future<void> parseAll(List<WaitingItem> items) async {
    for (final i in items) {
      ids.add(i.id);
    }
    try {
      final before = repo.airtime.recordedCount;
      final n = await repo.parseAll([for (final i in items) i.id]);
      if (n > 0) {
        if (repo.airtime.recordedCount > before) {
          toast(kToastParsedAirtimeRecorded);
        } else {
          quiet.value = noteReadMany(n);
        }
      }
    } catch (_) {
      // Rows that were not parsed stay.
    } finally {
      ids.retainWhere((id) => repo.itemById(id)?.kind == WaitingKind.waitingCategory);
    }
  }

  Future<void> details(WaitingItem item) async {
    try {
      final d = await repo.detailsFor(item.id);
      if (!context.mounted) return;
      await showMessageDetailsSheet(
        context,
        details: d,
        onRemove: item.kind == WaitingKind.unreadable && d?.kind == WaitingKind.unreadable
            ? () async {
                if (context.mounted && await showRemoveConfirm(context, item: item)) await remove(item);
              }
            : null,
      );
    } catch (_) {
      // Nothing changes; the row stays.
    }
  }

  return WaitingActions(
    onDetails: details,
    describe: (item) => repo.describeHeld(item.id),
    clearDescriptions: repo.clearDescriptions,
    airtime: repo.airtime,
    onParse: parse,
    onCategorize: categorize,
    onPaste: (_) => Navigator.of(context).pushNamed(Routes.add),
    onRemove: remove,
    onParseAll: parseAll,
    onChangeInSettings: () => Navigator.of(context)
        .pushNamed(Routes.rememberedRecipients, arguments: const RememberedRouteArgs(openAutoRecord: true)),
    choicesFor: repo.categoryChoicesFor,
    onPickCategory: pickCategory,
    onLater: later,
    choosing: ids,
    undecided: repo.undecided,
    onWithdrawalCashOnly: withdrawalCashOnly,
    onWithdrawalCategorize: withdrawalCategorize,
    onDecisionCashOnly: decisionCashOnly,
    onDecisionCashOnlyAll: decisionCashOnlyAll,
    onDecisionCategorize: decisionCategorize,
    suggestions: RulesWiring.suggestions,
    ruleHintFor: rules == null ? null : (item) => rules.isLater(item.id) ? null : item.hint,
    categoryNameOf: rules?.nameOf,
    onAskFirstYes: rules == null ? null : askFirstYes,
    onAskFirstChange: rules == null ? null : (item, _) => categorize(item),
    onAskFirstLater: rules == null ? null : askFirstLater,
    askFirstChanges: rules,
  );
}
