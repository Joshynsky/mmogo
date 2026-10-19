/// §AUTOREAD.REAL_WAITING_ACTIONS — the [WaitingActions] the Notifications page
/// uses in the autoread flavor: every button does its real job through the
/// [RealWaitingRepository]. Built by `NotificationsRoute` inside
/// `if (kAutoReadCompiled)`.
///
/// - Parse: the repository parses; the toast says it moved to To categorize.
/// - Categorize: an item not parsed yet is parsed first; then the sheet opens
///   with the same categories Add shows; Save writes the real transaction.
/// - Paste: after the paste sheet closed, Add opens. Add is paste-first: its
///   Paste card is the first thing on it.
/// - Remove: the repository removes it (unreadable or gone rows only).
/// - Parse all: each readable item is parsed, one after another.
library;

import 'package:flutter/material.dart';

import '../../ui/shell/routes.dart';
import '../model/waiting_item.dart';
import '../model/waiting_repository.dart';
import '../ui/categorize_sheet.dart';
import '../ui/notifications_autoread_copy.dart';
import '../ui/waiting_section.dart';
import 'real_waiting_repository.dart';

WaitingActions buildRealWaitingActions(BuildContext context, RealWaitingRepository repo) {
  void toast(String text) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.hideCurrentSnackBar();
    m?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> parse(WaitingItem item) async {
    try {
      final r = await repo.parse(item.id);
      if (r == ParseOutcome.parsed) toast(kToastParsed);
    } catch (_) {
      // The row stays as it was; a later ingest shows the true state.
    }
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
    try {
      final n = await repo.parseAll([for (final i in items) i.id]);
      if (n > 0) toast(kToastParsed);
    } catch (_) {
      // Rows that were not parsed stay.
    }
  }

  return WaitingActions(
    onParse: parse,
    onCategorize: categorize,
    onPaste: (_) => Navigator.of(context).pushNamed(Routes.add),
    onRemove: remove,
    onParseAll: parseAll,
  );
}
