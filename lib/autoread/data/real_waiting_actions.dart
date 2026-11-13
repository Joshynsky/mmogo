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

import '../../domain/format/money.dart';
import '../../ui/shell/routes.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';
import '../logic/airtime_auto.dart';
import '../logic/held_describe.dart' show describeReadable;
import '../ui/categorize_sheet.dart';
import '../ui/message_details_sheet.dart';
import '../ui/notifications_autoread_copy.dart';
import '../ui/remove_confirm.dart';
import '../ui/todo_choose.dart';
import '../ui/todo_copy.dart';
import '../ui/waiting_section.dart';
import 'real_waiting_repository.dart';

/// The "Recorded as Airtime" toast with Undo. `persist: false` is required:
/// since Flutter 3.2x a SnackBar with an action defaults to `persist: true`
/// and never times out (found 11-11-2026: it stayed on the phone for 35+
/// minutes). It must go after [kAutoRecordedToastSeconds].
const int kAutoRecordedToastSeconds = 8;

SnackBar autoRecordedSnackBar(AutoRecorded e, VoidCallback onUndo) => SnackBar(
      duration: const Duration(seconds: kAutoRecordedToastSeconds),
      persist: false,
      content: Text(autoRecordedToast(kshTrim(e.amountCents))),
      action: SnackBarAction(label: kAutoRecordedUndo, onPressed: onUndo),
    );

/// [choosing] and [note] belong to the page (they must outlive a rebuild of
/// the route); a caller that passes none gets fresh ones.
WaitingActions buildRealWaitingActions(
  BuildContext context,
  RealWaitingRepository repo, {
  ChoosingIds? choosing,
  ValueNotifier<String?>? note,
}) {
  final ids = choosing ?? ChoosingIds();
  final quiet = note ?? ValueNotifier<String?>(null);

  void toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  /// Toast for a Parse that recorded Airtime on its own: with Undo (J2).
  void toastAutoRecorded(AutoRecorded e) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(autoRecordedSnackBar(e, () async {
      await repo.undoAutoRecord(e);
      toast(kAutoRecordedUndoneToast);
    }));
  }

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
  );
}
