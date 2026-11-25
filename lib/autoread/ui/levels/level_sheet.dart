/// §AUTOREAD.LEVELS.LEVEL_SHEET: the sheet behind a person's level button.
/// 0.2.1 offers Suggested and Ask first ([kSheetLevels]); the 0.2.2
/// Auto-record level adds one entry there. Ask first needs a category, picked from the categories of the
/// person's own group only. The sheet stays short: the category is a row that opens its own small sheet ([showCategoryPickSheet]).
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../logic/phone_mask.dart';
import '../../rules/rule_model.dart';
import '../../../ui/widgets/bottom_sheet_shell.dart';
import '../category_choices.dart';
import 'category_pick_sheet.dart';
import 'level_filter_row.dart' show levelTagText;
import 'levels_copy.dart';
import 'levels_person_row.dart';

/// Levels the sheet offers, in order.
const List<RuleLevel> kSheetLevels = [RuleLevel.suggested, RuleLevel.askFirst];

enum LevelSaveResult { ok, capReached, failed }

/// What the sheet calls on Save. [ceilingCents] is the Auto-record ceiling (0.2.2); callers ignore it
/// until the sheet offers Auto-record.
typedef LevelSaveFn = Future<LevelSaveResult> Function(RuleLevel level, int? categoryId, {int? ceilingCents});

Future<void> showLevelSheet(
  BuildContext context, {
  required LevelPerson person,
  required CategoryChoices categories,
  required LevelSaveFn onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LevelSheet(person: person, categories: categories, onSave: onSave),
  );
}

class LevelSheet extends StatefulWidget {
  const LevelSheet({super.key, required this.person, required this.categories, required this.onSave});
  final LevelPerson person;
  final CategoryChoices categories;
  final LevelSaveFn onSave;

  @override
  State<LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends State<LevelSheet> {
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
        _cat = [for (final i in widget.person.topIds) if (ids.contains(i)) i].firstOrNull;
      }
    });
  }

  bool get _canSave => !_saving && (_level != RuleLevel.askFirst || _cat != null);

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

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final person = widget.person;
    final name = person.type == ReceiverType.sendMoney ? nameWithMask(person.name, person.key) : person.name;
    return BottomSheetShell(palette: p, children: [..._top(p, name), _actions(p)]);
  }

  List<Widget> _top(AppPalette p, String name) {
    final w = <Widget>[
        Semantics(
          header: true,
          child: Text(levelSheetTitle(name),
              key: const Key('levelSheetTitle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
        ),
        Wrap(spacing: 8, runSpacing: 6, children: [
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
                    child: Text(levelTagText(l),
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _level == l ? p.tintInk : p.ink)),
                  ),
                ),
              ),
            ),
        ]),
        Text(_level == RuleLevel.askFirst ? kLevelSheetAskFirstNote : levelSheetSuggestedNote(name),
            key: const Key('levelSheetNote'), style: TextStyle(fontSize: 13, height: 1.4, color: p.softInk)),
        if (_level == RuleLevel.askFirst) ..._categoryPart(p),
    ];
    return w;
  }

  Widget _actions(AppPalette p) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_error != null) ...[
        Text(_error!, key: const Key('levelSheetError'), style: TextStyle(fontSize: 13, color: p.error, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
      ],
      Row(children: [
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
                  minimumSize: const Size.fromHeight(48), shape: const StadiumBorder(), backgroundColor: p.primary, foregroundColor: p.onPrimary),
              onPressed: _canSave ? _save : null,
              child: const Text(kLevelSheetSave),
            ),
          ),
        ]),
    ]);
  }

  List<Widget> _categoryPart(AppPalette p) {
    final name = _cat == null ? null : _cats.where((c) => int.tryParse(c.id) == _cat).map((c) => c.name).firstOrNull;
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
            decoration: BoxDecoration(border: Border.all(color: p.line, width: 1.5), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kLevelSheetCategory, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.mutedInk)),
                  Text(name ?? kLevelSheetNoneChosen,
                      key: const Key('levelCategoryValue'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: name == null ? p.mutedInk : p.ink)),
                ]),
              ),
              Icon(Icons.arrow_drop_down, size: 24, color: p.mutedInk),
            ]),
          ),
        ),
      ),
      if (_cat == null && _loaded && _cats.isNotEmpty)
        Text(kLevelSheetPickCategory, style: TextStyle(fontSize: 12.5, color: p.mutedInk)),
    ];
  }

  Future<void> _openPicker() async {
    final id = await showCategoryPickSheet(context, categories: _cats, selected: _cat);
    if (id != null && mounted) setState(() => _cat = id);
  }
}
