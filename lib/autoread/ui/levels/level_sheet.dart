/// §AUTOREAD.LEVELS.LEVEL_SHEET: the sheet behind a person's level button.
/// 0.2.1 offers Suggested and Ask first ([kSheetLevels]); the 0.2.2
/// Auto-record level adds one entry there. Ask first needs a category, picked from the categories of the
/// person's own group only. The sheet stays short: the category is a row that opens its own small sheet ([showCategoryPickSheet]).
/// 0.2.2 (only while [autoRecordUi]): three radio options (mock lvl-tim/amina/mboga/kplc), Auto-record
/// greyed with a reason where the type cannot hold it, the ceiling field ([CeilingField]) inside the
/// Auto-record option, and the confirm dialog ([showHardRuleConfirm]) before a NEW Auto-record.
/// Flag off = the 0.2.1 sheet exactly.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../logic/phone_mask.dart';
import '../../rules/rule_model.dart';
import '../../../ui/widgets/bottom_sheet_shell.dart';
import '../category_choices.dart';
import 'category_pick_sheet.dart';
import 'hard_rule_confirm_dialog.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'level_sheet_ceiling.dart';
import 'level_filter_row.dart' show levelTagText;
import 'levels_copy.dart';
import 'levels_person_row.dart';

/// Levels the sheet offers, in order.
const List<RuleLevel> kSheetLevels = [RuleLevel.suggested, RuleLevel.askFirst];

enum LevelSaveResult { ok, capReached, failed }

/// What the sheet calls on Save. [ceilingCents] is the Auto-record ceiling (0.2.2); callers ignore it
/// until the sheet offers Auto-record.
typedef LevelSaveFn = Future<LevelSaveResult> Function(RuleLevel level, int? categoryId, {int? ceilingCents});

/// The one-line reason Auto-record is greyed for [type]; null when the type can hold it. Withdrawals have
/// no [ReceiverType] (they never hold a rule), so kHardWhyNotWithdrawal has no row to sit on today.
String? autoRecordWhyNot(ReceiverType type) => canHoldAutoRecord(type) ? null : kHardWhyNotPaybill;

Future<void> showLevelSheet(
  BuildContext context, {
  required LevelPerson person,
  required CategoryChoices categories,
  required LevelSaveFn onSave,
  bool focusCeiling = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => LevelSheet(person: person, categories: categories, onSave: onSave, focusCeiling: focusCeiling),
  );
}

class LevelSheet extends StatefulWidget {
  const LevelSheet({super.key, required this.person, required this.categories, required this.onSave, this.focusCeiling = false});
  final LevelPerson person;
  final CategoryChoices categories;
  final LevelSaveFn onSave;

  /// Opens with the ceiling field focused (the pill's "Change ceiling"); only when Auto-record shows.
  final bool focusCeiling;

  @override
  State<LevelSheet> createState() => _LevelSheetState();
}

class _LevelSheetState extends State<LevelSheet> {
  /// Read once: the 0.2.2 three-level sheet, else the 0.2.1 one.
  final bool _hard = autoRecordUi;
  late final List<RuleLevel> _levels = _hard ? RuleLevel.values : kSheetLevels;
  late final bool _autoAllowed = _hard && canHoldAutoRecord(widget.person.type);
  late RuleLevel _level = _startLevel();
  // Starts as the rule's category, else the most-used one; cleared on load when it is not in this group's list.
  late int? _cat = widget.person.categoryId ?? (widget.person.topIds.isEmpty ? null : widget.person.topIds.first);
  List<CategoryChoice> _cats = const [];
  bool _loaded = false;
  bool _saving = false;
  String? _error;
  // The ceiling field (0.2.2). Starts with the stored ceiling, also for an autoPending person.
  late final TextEditingController _ceil = TextEditingController(text: ceilingFieldText(widget.person.ceilingCents));
  final FocusNode _ceilFocus = FocusNode();
  CeilingProblem? _ceilProblem;

  RuleLevel _startLevel() {
    final l = widget.person.level;
    if (!_levels.contains(l)) return RuleLevel.suggested;
    // A stored Auto-record the type cannot hold (the store never writes one) shows its highest level.
    if (l == RuleLevel.autoRecord && !canHoldAutoRecord(widget.person.type)) return RuleLevel.askFirst;
    return l;
  }

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.focusCeiling && _level == RuleLevel.autoRecord) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ceilFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _ceil.dispose();
    _ceilFocus.dispose();
    super.dispose();
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

  bool get _needsCat => _level != RuleLevel.suggested;
  bool get _canSave => !_saving && (!_needsCat || _cat != null) && (_level != RuleLevel.autoRecord || _catName != null);
  String? get _catName => _cat == null ? null : _cats.where((c) => int.tryParse(c.id) == _cat).map((c) => c.name).firstOrNull;

  /// The ceiling to save; `ok: false` (and [_ceilProblem] set) when the text is refused. An unchanged
  /// field keeps the stored cents exactly.
  ({bool ok, int? cents}) _readCeiling() {
    final stored = widget.person.ceilingCents;
    if (stored != null && _ceil.text == ceilingFieldText(stored)) return (ok: true, cents: stored);
    final r = parseCeiling(_ceil.text);
    if (!r.ok) {
      setState(() => _ceilProblem = r.problem);
      return (ok: false, cents: null);
    }
    return (ok: true, cents: r.cents);
  }

  Future<void> _save() async {
    int? ceiling;
    if (_level == RuleLevel.autoRecord) {
      if (!_autoAllowed) return; // never asks the store for an Auto-record this type cannot hold
      final c = _readCeiling();
      if (!c.ok) return; // Save does nothing while the ceiling is refused
      ceiling = c.cents;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    // A NEW Auto-record asks first; a change on an existing Auto-record (the ceiling) does not.
    if (_level == RuleLevel.autoRecord && widget.person.level != RuleLevel.autoRecord) {
      final yes = await showHardRuleConfirm(context, name: _displayName, category: _catName!, ceilingCents: ceiling);
      if (!mounted) return;
      if (!yes) {
        setState(() => _saving = false); // Cancel keeps the sheet open; nothing saved
        return;
      }
    }
    final r = _hard
        ? await widget.onSave(_level, _needsCat ? _cat : null, ceilingCents: ceiling)
        : await widget.onSave(_level, _level == RuleLevel.askFirst ? _cat : null);
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
    final name = _displayName;
    return BottomSheetShell(palette: p, children: [...(_hard ? _hardTop(p, name) : _top(p, name)), _actions(p)]);
  }

  /// The 0.2.2 top: title, three radio options (mock lvl-*), then the category row for Ask first and
  /// Auto-record.
  List<Widget> _hardTop(AppPalette p, String name) {
    return [
      Semantics(
        header: true,
        child: Text(
          hardSheetTitle(name),
          key: const Key('levelSheetTitle'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink),
        ),
      ),
      Semantics(
        // Radio group; the options carry their own checked state.
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final l in _levels) ...[
              if (l != _levels.first) const SizedBox(height: 8),
              LevelOption(
                key: Key('levelChoice${l.name}'),
                title: hardRuleLevelName(l),
                note: l == RuleLevel.autoRecord && !_autoAllowed
                    ? (autoRecordWhyNot(widget.person.type) ?? kHardWhyNotPaybill)
                    : _hardNote(l),
                selected: _level == l,
                enabled: l != RuleLevel.autoRecord || _autoAllowed,
                onTap: _saving ? null : () => _pick(l),
                extra: l == RuleLevel.autoRecord && _level == l && _autoAllowed
                    ? CeilingField(
                        controller: _ceil,
                        focusNode: _ceilFocus,
                        problem: _ceilProblem,
                        onChanged: (_) {
                          if (_ceilProblem != null) setState(() => _ceilProblem = null);
                        },
                      )
                    : null,
              ),
            ],
          ],
        ),
      ),
      if (_needsCat) ..._categoryPart(p),
    ];
  }

  void _pick(RuleLevel l) => setState(() {
    _level = l;
    _ceilProblem = null;
  });

  String _hardNote(RuleLevel l) => switch (l) {
    RuleLevel.suggested => hardSheetNoteSuggested(widget.person.name),
    // No category chosen yet: today's Ask first note (there is no category to quote).
    RuleLevel.askFirst => _catName == null ? kLevelSheetAskFirstNote : hardSheetNoteAskFirst(_catName!),
    RuleLevel.autoRecord => kHardSheetNoteAutoRecord,
  };

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

/// One radio option of the 0.2.2 sheet: title, note (or the greyed reason), and [extra] under it (the
/// ceiling field). A disabled option is drawn muted with an empty radio, says "disabled" to a screen
/// reader and ignores taps; the reason line is the non-colour cue.
class LevelOption extends StatelessWidget {
  const LevelOption({
    super.key,
    required this.title,
    required this.note,
    required this.selected,
    required this.enabled,
    this.onTap,
    this.extra,
  });
  final String title;
  final String note;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final tap = enabled ? onTap : null;
    final on = selected && enabled;
    final hasExtra = extra != null;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: on ? p.tint : Colors.transparent,
        border: Border.all(color: on ? p.primary : p.line, width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              inMutuallyExclusiveGroup: true,
              checked: on,
              enabled: enabled,
              label: '$title. $note',
              excludeSemantics: true,
              onTap: tap,
              child: InkWell(
                onTap: tap,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  padding: EdgeInsetsDirectional.fromSTEB(12, 10, 12, hasExtra ? 4 : 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        size: 22,
                        color: enabled ? (on ? p.primary : p.mutedInk) : p.line,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: enabled ? (on ? p.tintInk : p.ink) : p.mutedInk,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              note,
                              key: enabled ? null : const Key('levelWhyNot'),
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                fontStyle: enabled ? FontStyle.normal : FontStyle.italic,
                                color: enabled ? (on ? p.tintInk : p.softInk) : p.mutedInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (hasExtra) Padding(padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 10), child: extra),
          ],
        ),
      ),
    );
  }
}
