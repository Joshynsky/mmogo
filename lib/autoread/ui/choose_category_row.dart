/// §AUTOREAD.CHOOSE_CATEGORY_ROW - a parsed message asking for its category in
/// place: the category chips (from [choicesFor]), a Later chip on a freshly
/// read row only, and "+ New", which opens the existing Categorize sheet. An
/// airtime row shows its one fixed category and no Later, no "+ New". The row
/// holds no repository: a chip calls [onPickCategory], once (a second tap while
/// the first save runs is ignored). Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../../ui/theme/app_colors.dart';
import '../model/waiting_item.dart';
import 'categorize_sheet.dart';
import 'category_choices.dart';
import 'choose_category_copy.dart';

class ChooseCategoryRow extends StatefulWidget {
  const ChooseCategoryRow({
    super.key,
    required this.item,
    required this.description,
    required this.choicesFor,
    required this.onPickCategory,
    this.onLater,
    this.fresh = true,
  });

  final WaitingItem item;

  /// What the message is ("Sent Ksh 200 to X"), built by the caller.
  final String description;
  final Future<CategoryChoices> Function(WaitingItem item) choicesFor;
  final Future<void> Function(WaitingItem item, String categoryId) onPickCategory;

  /// Moves the row to To categorize. Null, or [fresh] false: no Later chip.
  final void Function(WaitingItem item)? onLater;

  /// True for the freshly read row; false for a row in To categorize.
  final bool fresh;

  @override
  State<ChooseCategoryRow> createState() => _ChooseCategoryRowState();
}

class _ChooseCategoryRowState extends State<ChooseCategoryRow> {
  CategoryChoices? _choices;
  List<CategoryChoice>? _cats;
  bool _failed = false;
  bool _busy = false;

  bool get _isAirtime => widget.item.parsed?.sourceType == SmsSourceType.airtime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await widget.choicesFor(widget.item);
      final cats = await c.categories();
      if (!mounted) return;
      setState(() {
        _choices = c;
        _cats = cats;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _pick(String id) async {
    if (_busy) return;
    _busy = true;
    try {
      await widget.onPickCategory(widget.item, id);
    } catch (_) {
      // The save failed: the row stays and the user can tap again. After a
      // success the row is about to leave, so it stays locked (one call only).
      _busy = false;
    }
  }

  Future<void> _new() async {
    final c = _choices;
    if (c == null || _busy) return;
    await showCategorizeSheet(
      context,
      item: widget.item,
      choices: c,
      onSave: (id) => widget.onPickCategory(widget.item, id),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final later = widget.fresh && !_isAirtime && widget.onLater != null;
    final sub = widget.fresh ? chooseCategoryFresh(widget.description) : chooseCategoryLater(widget.description);
    return Semantics(
      container: true,
      label: chooseCategorySpoken(widget.description),
      child: Container(
        decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kChooseCategoryTitle,
                      style: TextStyle(color: p.ink, fontSize: 14, height: 1.3, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(color: p.mutedInk, fontSize: 12.5, height: 1.35)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (_failed)
              Text(kCategorizeLoadFailed, style: TextStyle(color: p.mutedInk, fontSize: 12.5))
            else if (_cats != null)
              Wrap(
                key: const Key('choose-chips'),
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _cats!) _Pill(key: Key('choose-chip-${c.id}'), label: c.name, onTap: () => _pick(c.id)),
                  if (!_isAirtime) _Pill(key: const Key('choose-new'), label: kCategorizeNewPill, onTap: _new),
                  if (later)
                    _Pill(
                        key: const Key('choose-later'),
                        label: kChooseLaterChip,
                        quiet: true,
                        onTap: () => widget.onLater!(widget.item)),
                ],
              ),
            if (_isAirtime && _cats != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(kCategorizeAirtimeFixed, style: TextStyle(color: p.mutedInk, fontSize: 12, height: 1.35)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onTap, this.quiet = false});
  final String label;
  final VoidCallback onTap;
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: StadiumBorder(side: BorderSide(color: quiet ? p.mutedInk : p.line, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(label,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: quiet ? p.mutedInk : p.ink)),
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
