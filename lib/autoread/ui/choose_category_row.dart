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
import '../history/history_summary_writer.dart' show HistorySummaryWriter;
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
    this.chipsFor,
    this.onPickChip,
  });

  /// 0.2.2 (item 0 Part 1): the suggested chips of this item, left to right (most used last). Null or empty or
  /// a failure: no chips, the row is as before. Needs [onPickChip] too.
  final Future<List<CategoryChoice>> Function(WaitingItem item)? chipsFor;

  /// A chip tap: records at once through the existing record path (the caller shows the Undo pill). Returns
  /// false when nothing was recorded (the category is no longer active): the row then refreshes its chips.
  final Future<bool> Function(WaitingItem item, CategoryChoice chip)? onPickChip;

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
  bool _saveFailed = false;
  bool _busy = false;
  List<CategoryChoice> _chips = const [];

  @override
  void initState() {
    super.initState();
    _loadChips();
    // N1: a record or Undo elsewhere changed the history summary: re-read this card's chips.
    HistorySummaryWriter.changes.addListener(_onSummaryChanged);
  }

  @override
  void dispose() {
    HistorySummaryWriter.changes.removeListener(_onSummaryChanged);
    super.dispose();
  }

  void _onSummaryChanged() {
    if (mounted && !_busy) _loadChips();
  }

  bool get _chipsOn =>
      widget.chipsFor != null && widget.onPickChip != null && !_isAirtime && !_withdrawalMode;

  Future<void> _loadChips() async {
    if (!_chipsOn) return;
    List<CategoryChoice> found;
    try {
      found = await widget.chipsFor!(widget.item);
    } catch (_) {
      found = const []; // never an error: the row is as before
    }
    if (!mounted) return;
    setState(() => _chips = found.length > 2 ? found.sublist(found.length - 2) : found);
  }

  /// A chip tap. One call only: a second tap or a second chip does nothing once the first is accepted.
  Future<void> _chipTap(CategoryChoice c) async {
    if (_busy) return;
    _busy = true;
    try {
      final recorded = await widget.onPickChip!(widget.item, c);
      if (!recorded) {
        _busy = false; // nothing was written: the user can choose again
        await _loadChips();
      }
      // After a success the row is about to leave, so it stays locked.
    } catch (_) {
      _busy = false;
      if (mounted) setState(() => _saveFailed = true);
    }
  }

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
        suggestedChips: _chipsOn ? () => widget.chipsFor!(widget.item) : null,
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
            if (_saveFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  kCategorizeSaveFailed,
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
            // N5: ONE row, right side (thumb reach). Not now and Categorize keep their natural width; the
            // suggested chips share what is left and cut a long name with "..." rather than wrap or overflow.
            // Only when even that cannot fit (huge text, a narrow screen) the pills wrap, as before.
            LayoutBuilder(
              builder: (context, box) {
                final labelOf = <String>[
                  if (later) kChooseLaterChip,
                  kActionCategorize,
                ];
                final fixed = labelOf.fold<double>(0, (w, l) => w + _pillWidth(context, l)) + 8.0 * (labelOf.length - 1);
                final oneRow = fixed + _chips.length * (8 + _kMinChipWidth) <= box.maxWidth;
                final later0 = later
                    ? _Pill(
                        key: const Key('choose-later'),
                        label: kChooseLaterChip,
                        quiet: true,
                        onTap: () => widget.onLater!(widget.item),
                      )
                    : null;
                final cat = _Pill(
                  key: const Key('choose-categorize'),
                  label: kActionCategorize,
                  fill: _chips.isEmpty, // same filled look as the Parse button (PM 17-11-2026); with chips the chip is the main button
                  onTap: _open,
                );
                // Left to right; the most used is LAST (on the right, filled).
                Widget chip(int i) => _Pill(
                      key: Key('choose-chip-${_chips[i].id}'),
                      label: _chips[i].name,
                      fill: i == _chips.length - 1,
                      spoken: chipSpoken(_chips[i].name),
                      ellipsize: true, // one line always; a long name is cut with "..."
                      onTap: () => _chipTap(_chips[i]),
                    );
                if (!oneRow && _chips.isNotEmpty) {
                  // Deliberate two-row fallback (N5, mock-chips: right-aligned, most used bottom right):
                  // row 1 = Not now + Categorize, row 2 = the chips together, never one chip alone.
                  return Column(
                    key: const Key('choose-actions'),
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Wrap(
                        key: const Key('choose-actions-top'),
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [?later0, cat],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        key: const Key('choose-actions-chips'),
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (var i = 0; i < _chips.length; i++) ...[
                            if (i > 0) const SizedBox(width: 8),
                            Flexible(child: chip(i)),
                          ],
                        ],
                      ),
                    ],
                  );
                }
                if (!oneRow) {
                  return SizedBox(
                    width: double.infinity,
                    child: Wrap(
                      key: const Key('choose-actions'),
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [?later0, cat, for (var i = 0; i < _chips.length; i++) chip(i)],
                    ),
                  );
                }
                return Row(
                  key: const Key('choose-actions'),
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (later0 != null) ...[later0, const SizedBox(width: 8)],
                    cat,
                    for (var i = 0; i < _chips.length; i++) ...[
                      const SizedBox(width: 8),
                      Flexible(child: chip(i)),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// A chip is never squeezed below this on the one-row layout; below it the pills wrap (N5 last resort).
const double _kMinChipWidth = 96;

/// The width a pill needs for [label] at the current text size (text + 14 padding each side + 1.5 border each side).
double _pillWidth(BuildContext context, String label) {
  final tp = TextPainter(
    text: TextSpan(
      text: label,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13, fontWeight: FontWeight.w800),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width + 28 + 3;
  tp.dispose();
  return w < 44 ? 44 : w;
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.onTap,
    this.quiet = false,
    this.fill = false,
    this.spoken,
    this.ellipsize = false,
  });
  final String label;

  /// One line, cut with an ellipsis when the width runs out (never wraps, never overflows).
  final bool ellipsize;

  /// What a screen reader says, when it differs from [label].
  final String? spoken;
  final VoidCallback onTap;
  final bool quiet;

  /// The filled primary pill, drawn like the Parse button on the same page.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: spoken ?? label,
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
                      maxLines: ellipsize ? 1 : null,
                      overflow: ellipsize ? TextOverflow.ellipsis : null,
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
