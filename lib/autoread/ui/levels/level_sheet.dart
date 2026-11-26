/// §AUTOREAD.LEVELS.LEVEL_SHEET: the sheet behind a person's level button, opened by [showLevelSheet].
/// Flag off: the 0.2.1 sheet exactly ([kSheetLevels]: Suggested and Ask first; Ask first needs a category from
/// the person's own group, picked on its own small sheet, [showCategoryPickSheet]).
/// 0.2.2 (only while [autoRecordUi]): the person sheet of the item 2 redesign ([PersonSheet],
/// person_sheet.dart; mock-remembered-v2 p-*). [LevelSheet] picks one of the two.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../logic/phone_mask.dart';
import '../../rules/rule_model.dart';
import '../../../ui/widgets/bottom_sheet_shell.dart';
import '../category_choices.dart';
import 'category_pick_sheet.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'levels_copy.dart';
import 'levels_person_row.dart';
import 'person_sheet.dart';
import 'setup_ports.dart';

/// The words of a level tag on the 0.2.1 sheet (two levels). Moved here from the removed
/// level_filter_row.dart (PM D3, I1): the sheet is its only user.
String levelTagText(RuleLevel l) => switch (l) {
      RuleLevel.askFirst => kLevelAskFirst,
      _ => kLevelSuggested,
    };

/// Levels the sheet offers, in order.
const List<RuleLevel> kSheetLevels = [RuleLevel.suggested, RuleLevel.askFirst];

enum LevelSaveResult { ok, capReached, failed }

/// What the sheet calls on Save. [ceilingCents] is the Auto-record limit (0.2.2 sheet only). The chosen
/// Suggest list is not passed: the save keeps the stored one (saveLevelChoice).
typedef LevelSaveFn = Future<LevelSaveResult> Function(RuleLevel level, int? categoryId, {int? ceilingCents});

/// The one-line reason Auto-record is greyed for [type]; null when the type can hold it. Withdrawals have
/// no [ReceiverType] (they never hold a rule), so kHardWhyNotWithdrawal has no row to sit on today.
String? autoRecordWhyNot(ReceiverType type) => canHoldAutoRecord(type) ? null : kHardPaybillAlwaysAsks;

Future<void> showLevelSheet(
  BuildContext context, {
  required LevelPerson person,
  required CategoryChoices categories,
  required LevelSaveFn onSave,
  bool focusCeiling = false,
  PickCategories? pickCategories,
  int? paymentCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LevelSheet(
      person: person,
      categories: categories,
      onSave: onSave,
      focusCeiling: focusCeiling,
      pickCategories: pickCategories,
      paymentCount: paymentCount,
    ),
  );
}

class LevelSheet extends StatelessWidget {
  const LevelSheet({
    super.key,
    required this.person,
    required this.categories,
    required this.onSave,
    this.focusCeiling = false,
    this.pickCategories,
    this.paymentCount,
  });
  final LevelPerson person;
  final CategoryChoices categories;
  final LevelSaveFn onSave;

  /// Opens with the limit field focused (the pill's "Set a limit" / "Change"); only when Auto-record shows.
  final bool focusCeiling;

  /// The category chips picker (LevelsDeps.pickCategories, single choice). Null = the older list sheet.
  /// 0.2.2 sheet only.
  final PickCategories? pickCategories;

  /// "{k} payments" in the 0.2.2 sheet's header; null = not shown.
  final int? paymentCount;

  @override
  Widget build(BuildContext context) => autoRecordUi
      ? PersonSheet(
          person: person,
          categories: categories,
          onSave: onSave,
          focusCeiling: focusCeiling,
          pickCategories: pickCategories,
          paymentCount: paymentCount,
        )
      : _LegacyLevelSheet(person: person, categories: categories, onSave: onSave);
}

/// The 0.2.1 sheet (flag off), unchanged: two level chips, the note, the category row for Ask first.
class _LegacyLevelSheet extends StatefulWidget {
  const _LegacyLevelSheet({required this.person, required this.categories, required this.onSave});
  final LevelPerson person;
  final CategoryChoices categories;
  final LevelSaveFn onSave;

  @override
  State<_LegacyLevelSheet> createState() => _LegacyLevelSheetState();
}

class _LegacyLevelSheetState extends State<_LegacyLevelSheet> {
  late RuleLevel _level = kSheetLevels.contains(widget.person.level) ? widget.person.level : RuleLevel.suggested;
  // Starts as the rule's category, else the most-used one; cleared on load when it is not in this group's list.
  late int? _cat = widget.person.categoryId ?? (widget.person.topIds.isEmpty ? null : widget.person.topIds.first);
  List<CategoryChoice> _cats = const [];
  bool _loaded = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<CategoryChoice> list = const [];
    try {
      list = await widget.categories.categories();
    } catch (_) {}
    if (!mounted) return;
    final ids = {for (final c in list) int.tryParse(c.id)};
    setState(() {
      _cats = list;
      _loaded = true;
      if (!ids.contains(_cat)) {
        // The rule's category is not in the person's group: take the most-used one that is, else none.
        _cat = [
          for (final i in widget.person.topIds)
            if (ids.contains(i)) i,
        ].firstOrNull;
      }
    });
  }

  bool get _canSave => !_saving && (_level != RuleLevel.askFirst || _cat != null);
  String? get _catName => _cat == null ? null : _cats.where((c) => int.tryParse(c.id) == _cat).map((c) => c.name).firstOrNull;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await widget.onSave(_level, _level == RuleLevel.askFirst ? _cat : null);
    if (!mounted) return;
    if (r == LevelSaveResult.ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = r == LevelSaveResult.capReached ? kLevelSheetCapReached : kLevelSheetSaveFailed;
    });
  }

  String get _displayName {
    final person = widget.person;
    return person.type == ReceiverType.sendMoney ? nameWithMask(person.name, person.key) : person.name;
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return BottomSheetShell(palette: p, children: [..._top(p, _displayName), _actions(p)]);
  }

  List<Widget> _top(AppPalette p, String name) {
    final w = <Widget>[
      Semantics(
        header: true,
        child: Text(
          levelSheetTitle(name),
          key: const Key('levelSheetTitle'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
        ),
      ),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final l in kSheetLevels)
            Semantics(
              button: true,
              selected: _level == l,
              label: levelTagText(l),
              excludeSemantics: true,
              onTap: () => setState(() => _level = l),
              child: InkWell(
                key: Key('levelChoice${l.name}'),
                borderRadius: BorderRadius.circular(999),
                onTap: () => setState(() => _level = l),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: _level == l ? p.tint : Colors.transparent,
                    border: Border.all(color: _level == l ? p.primary : p.line, width: 1.5),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      levelTagText(l),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _level == l ? p.tintInk : p.ink),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      Text(
        _level == RuleLevel.askFirst ? kLevelSheetAskFirstNote : levelSheetSuggestedNote(name),
        key: const Key('levelSheetNote'),
        style: TextStyle(fontSize: 13, height: 1.4, color: p.softInk),
      ),
      if (_level == RuleLevel.askFirst) ..._categoryPart(p),
    ];
    return w;
  }

  Widget _actions(AppPalette p) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          Text(
            _error!,
            key: const Key('levelSheetError'),
            style: TextStyle(fontSize: 13, color: p.error, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('levelSheetCancel'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text(kLevelSheetCancel),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                key: const Key('levelSheetSave'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  backgroundColor: p.primary,
                  foregroundColor: p.onPrimary,
                ),
                onPressed: _canSave ? _save : null,
                child: const Text(kLevelSheetSave),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _categoryPart(AppPalette p) {
    final name = _catName;
    return [
      Semantics(
        button: true,
        label: kLevelSheetCategory,
        value: name ?? kLevelSheetNoneChosen,
        excludeSemantics: true,
        onTap: _openPicker,
        child: InkWell(
          key: const Key('levelCategoryRow'),
          borderRadius: BorderRadius.circular(12),
          onTap: _openPicker,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: p.line, width: 1.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kLevelSheetCategory,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.mutedInk),
                      ),
                      Text(
                        name ?? kLevelSheetNoneChosen,
                        key: const Key('levelCategoryValue'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: name == null ? p.mutedInk : p.ink),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_drop_down, size: 24, color: p.mutedInk),
              ],
            ),
          ),
        ),
      ),
      if (_cat == null && _loaded && _cats.isNotEmpty) Text(kLevelSheetPickCategory, style: TextStyle(fontSize: 12.5, color: p.mutedInk)),
    ];
  }

  Future<void> _openPicker() async {
    final id = await showCategoryPickSheet(context, categories: _cats, selected: _cat);
    if (id != null && mounted) setState(() => _cat = id);
  }
}
