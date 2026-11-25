/// §AUTOREAD.LEVELS.CATEGORY_CHIPS_PICKER: the real category chips picker behind the [PickCategories] port
/// (0.2.2 item 2, slice U-PICK; mock-remembered-v2 pick-multi, pick-one; sign-off "Category picker").
/// All chips are visible at once. The order is fixed when the picker opens: the chosen chips first, then the
/// rest, each part in the given category order ([chipsPickerOrder]); nothing moves while tapping.
/// [CategoryPickMode.one]: a tap chooses that chip (the old one goes off). [CategoryPickMode.upTo2]: a tap turns
/// a chip on or off, "{k} of {m} chosen" is read out, and a tap on a further chip at the limit is refused with
/// the limit line. Done returns the chosen ids in the order chosen; Back, the scrim or the system back = null.
/// I2 installs [showCategoryChipsPicker] into LevelsDeps.pickCategories.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/shell/chrome_widgets.dart';
import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import '../category_choices.dart';
import 'category_pick_chip.dart';
import 'hard_rule_copy.dart';
import 'levels_copy.dart' show kLevelSheetNoCategories;
import 'setup_ports.dart';

/// How many may be chosen in [mode].
int chipsPickerMax(CategoryPickMode mode) => mode == CategoryPickMode.one ? 1 : kMaxChosenCategories;

/// The chips in the order they stay in while the picker is open: the offered choices (whole-number ids only)
/// that are in [initial] first, then the others; each part keeps the order of [choices]. Pure.
List<CategoryChoice> chipsPickerOrder(List<CategoryChoice> choices, Iterable<int> initial) {
  final on = initial.toSet();
  final offered = [
    for (final c in choices)
      if (int.tryParse(c.id) != null) c,
  ];
  return [
    for (final c in offered)
      if (on.contains(int.parse(c.id))) c,
    for (final c in offered)
      if (!on.contains(int.parse(c.id))) c,
  ];
}

/// The starting choice: [initial] cut to the offered ids, no id twice, at most [chipsPickerMax], order kept.
List<int> chipsPickerStart(List<CategoryChoice> choices, Iterable<int> initial, CategoryPickMode mode) {
  final offered = {for (final c in choices) ?int.tryParse(c.id)};
  final out = <int>[];
  for (final id in initial) {
    if (offered.contains(id) && !out.contains(id) && out.length < chipsPickerMax(mode)) out.add(id);
  }
  return out;
}

/// Opens the picker. Matches [PickCategories]; [name] (optional, not in the port yet: see the U-PICK report
/// HANDOFF) puts the person's name in the title.
Future<List<int>?> showCategoryChipsPicker(
  BuildContext context, {
  required CategoryPickMode mode,
  required List<CategoryChoice> choices,
  required List<int> initial,
  required Set<int> usedBefore,
  String? name,
}) {
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        CategoryChipsPicker(mode: mode, choices: choices, initial: initial, usedBefore: usedBefore, name: name),
  );
}

class CategoryChipsPicker extends StatefulWidget {
  const CategoryChipsPicker({
    super.key,
    required this.mode,
    required this.choices,
    required this.initial,
    required this.usedBefore,
    this.name,
  });

  final CategoryPickMode mode;
  final List<CategoryChoice> choices;
  final List<int> initial;
  final Set<int> usedBefore;
  final String? name;

  @override
  State<CategoryChipsPicker> createState() => _CategoryChipsPickerState();
}

class _CategoryChipsPickerState extends State<CategoryChipsPicker> {
  late final List<CategoryChoice> _order = chipsPickerOrder(widget.choices, widget.initial);
  late final List<int> _chosen = chipsPickerStart(widget.choices, widget.initial, widget.mode);
  bool _refused = false;

  bool get _single => widget.mode == CategoryPickMode.one;
  int get _max => chipsPickerMax(widget.mode);

  void _tap(int id) {
    setState(() {
      if (_single) {
        _chosen
          ..clear()
          ..add(id);
        return;
      }
      if (_chosen.remove(id)) {
        _refused = false;
      } else if (_chosen.length >= _max) {
        _refused = true;
      } else {
        _chosen.add(id);
        _refused = false;
      }
    });
  }

  void _done() {
    // One: Done with nothing chosen = closed without a choice. Up to 2: an empty list is a real answer.
    Navigator.of(context).pop(_single && _chosen.isEmpty ? null : List<int>.unmodifiable(_chosen));
  }

  String get _title {
    final n = widget.name;
    if (n == null) return _single ? kHardCategoryChoose : kHardSuggestChoose;
    return _single ? hardPickerTitleOne(n) : hardPickerTitleMulti(n);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    final hint = TextStyle(fontSize: 13, color: p.mutedInk, height: 1.3);
    final anyUsed = _order.any((c) => widget.usedBefore.contains(int.parse(c.id)));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: math.max(200, math.min(h * 0.85, h - MediaQuery.viewInsetsOf(context).bottom - 8)),
      ),
      child: Container(
        key: const Key('chipsPicker'),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 10, 16, 4),
                child: Row(
                  children: [
                    IconCircleButton(
                      key: const Key('chipsPickerBack'),
                      icon: Icons.arrow_back,
                      tooltip: kHardBack,
                      background: p.track,
                      foreground: p.ink,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          _title,
                          key: const Key('chipsPickerTitle'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  key: const Key('chipsPickerScroll'),
                  padding: const EdgeInsetsDirectional.fromSTEB(18, 4, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_single)
                        // The count is read out on every change (live region), like the mock's role="status".
                        Semantics(
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: '${hardPickerUpTo(_max)} '),
                                  TextSpan(
                                    text: hardPickerCount(_chosen.length, _max),
                                    style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
                                  ),
                                ],
                              ),
                              key: const Key('chipsPickerCount'),
                              style: hint,
                            ),
                          ),
                        ),
                      if (!_single)
                        // The refusal at the limit (the mock shows it as a toast; inside a sheet it is a line here).
                        Semantics(
                          liveRegion: true,
                          child: _refused
                              ? Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    hardPickerLimit(_max),
                                    key: const Key('chipsPickerLimit'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: p.error,
                                      height: 1.3,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      if (anyUsed)
                        // The key line for the dot; each chip already says "Used before" to screen readers.
                        ExcludeSemantics(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                PickUsedDot(color: p.primary),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(kHardPickerUsedBefore, key: const Key('chipsPickerUsedKey'), style: hint),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      if (_order.isEmpty)
                        Text(kLevelSheetNoCategories, key: const Key('chipsPickerEmpty'), style: hint),
                      Semantics(
                        container: true,
                        explicitChildNodes: true,
                        child: Wrap(
                          key: const Key('chipsPickerWrap'),
                          spacing: 8,
                          runSpacing: 8,
                          children: [for (final c in _order) _chip(c)],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton(
                  key: const Key('chipsPickerDone'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: p.primary,
                    foregroundColor: p.onPrimary,
                  ),
                  onPressed: _done,
                  child: Text(
                    kHardPickerDone,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(CategoryChoice c) {
    final id = int.parse(c.id);
    final on = _chosen.contains(id);
    return CategoryPickChip(
      key: Key('chipsPick.$id'),
      name: c.name,
      chosen: on,
      usedBefore: widget.usedBefore.contains(id),
      single: _single,
      dimmed: !_single && !on && _chosen.length >= _max,
      onTap: () => _tap(id),
    );
  }
}
