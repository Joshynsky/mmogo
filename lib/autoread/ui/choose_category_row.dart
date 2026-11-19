/// §AUTOREAD.CHOOSE_CATEGORY_ROW - a parsed message asking for its category in
/// place: one compact row (what it is, then a Categorize button and, on a
/// freshly read row only, a Later chip). Categorize opens the existing
/// Categorize sheet (details, the category chips, "+ New", Save), as it did in
/// 0.1.x (PM 14-11-2026: a wall of chips per row does not scale to many items).
/// An airtime row opens the same sheet with its one fixed category. The row
/// holds no repository: the sheet's Save calls [onPickCategory], once (a second
/// tap while a save runs is ignored). Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/copy/withdrawal_copy.dart';
import '../../ui/theme/app_colors.dart';
import '../model/waiting_item.dart';
import 'categorize_sheet.dart';
import 'category_choices.dart';
import 'choose_category_copy.dart';
import 'notifications_autoread_copy.dart' show kActionCategorize;

class ChooseCategoryRow extends StatefulWidget {
  const ChooseCategoryRow({
    super.key,
    required this.item,
    required this.description,
    required this.choicesFor,
    required this.onPickCategory,
    this.onLater,
    this.fresh = true,
    this.onCashOnly,
    this.onCategorizeWithdrawal,
  });

  /// 0.2.1: both set + the item is a withdrawal: the row shows two side-by-side buttons,
  /// Cash only | Categorize (no Later chip); Categorize opens the withdrawal sheet.
  final Future<void> Function(WaitingItem item)? onCashOnly;
  final Future<void> Function(WaitingItem item)? onCategorizeWithdrawal;

  final WaitingItem item;

  /// What the message is ("Sent Ksh 200 to X"), built by the caller.
  final String description;
  final Future<CategoryChoices> Function(WaitingItem item) choicesFor;
  final Future<void> Function(WaitingItem item, String categoryId)
  onPickCategory;

  /// Moves the row to To categorize. Null, or [fresh] false: no Later chip.
  final void Function(WaitingItem item)? onLater;

  /// True for the freshly read row; false for a row in To categorize.
  final bool fresh;

  @override
  State<ChooseCategoryRow> createState() => _ChooseCategoryRowState();
}

class _ChooseCategoryRowState extends State<ChooseCategoryRow> {
  bool _failed = false;
  bool _busy = false;

  bool get _isAirtime =>
      widget.item.parsed?.sourceType == SmsSourceType.airtime;

  Future<void> _pick(String id) async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onPickCategory(widget.item, id);
    } catch (_) {
      // The save failed: the row stays and the user can tap again. After a
      // success the row is about to leave, so it stays locked (one call only).
      _busy = false;
      rethrow;
    }
  }

  bool get _withdrawalMode =>
      widget.item.parsed?.sourceType == SmsSourceType.agentWithdrawal &&
      widget.onCashOnly != null &&
      widget.onCategorizeWithdrawal != null;

  Future<void> _cashOnly() async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onCashOnly!(widget.item);
    } catch (_) {
      _busy = false; // the save failed: the row stays; after a success it leaves
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Opens the Categorize sheet for this item (the categories load when it opens).
  Future<void> _open() async {
    if (_busy) return;
    if (_withdrawalMode) {
      try {
        await widget.onCategorizeWithdrawal!(widget.item);
      } catch (_) {
        if (mounted) setState(() => _failed = true);
      }
      return;
    }
    try {
      final c = await widget.choicesFor(widget.item);
      if (!mounted) return;
      if (_failed) setState(() => _failed = false);
      await showCategorizeSheet(
        context,
        item: widget.item,
        choices: c,
        onSave: (id) => _pick(id),
      );
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final later = widget.fresh && !_isAirtime && widget.onLater != null;
    final sub = widget.fresh
        ? chooseCategoryFresh(widget.description)
        : chooseCategoryLater(widget.description);
    return Semantics(
      container: true,
      label: chooseCategorySpoken(widget.description),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _withdrawalMode ? kWdQuestion : kChooseCategoryTitle,
                    style: TextStyle(
                      color: p.ink,
                      fontSize: 14,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sub,
                    style: TextStyle(
                      color: p.mutedInk,
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  kCategorizeLoadFailed,
                  style: TextStyle(color: p.mutedInk, fontSize: 12.5),
                ),
              ),
            if (_withdrawalMode)
              Row(
                key: const Key('choose-actions'),
                children: [
                  Expanded(child: _Pill(key: const Key('choose-cash-only'), label: kWdTodoRowCashOnly, onTap: _cashOnly)),
                  const SizedBox(width: 8),
                  Expanded(child: _Pill(key: const Key('choose-categorize'), label: kActionCategorize, fill: true, onTap: _open)),
                ],
              )
            else
            SizedBox(
              width: double.infinity,
              child: Wrap(
                key: const Key('choose-actions'),
                alignment: WrapAlignment
                    .end, // right side, like the To parse row (PM 14-11-2026: thumb reach)
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (later)
                    _Pill(
                      key: const Key('choose-later'),
                      label: kChooseLaterChip,
                      quiet: true,
                      onTap: () => widget.onLater!(widget.item),
                    ),
                  _Pill(
                    key: const Key('choose-categorize'),
                    label: kActionCategorize,
                    fill: true, // same filled look as the Parse button (PM 17-11-2026)
                    onTap: _open,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.onTap,
    this.quiet = false,
    this.fill = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool quiet;

  /// The filled primary pill, drawn like the Parse button on the same page.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: fill ? p.primary : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: fill ? p.primary : (quiet ? p.mutedInk : p.line), width: 1.5),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: fill ? FontWeight.w800 : FontWeight.w700,
                        color: fill ? p.onPrimary : (quiet ? p.mutedInk : p.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
