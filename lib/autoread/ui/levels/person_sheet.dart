/// §AUTOREAD.LEVELS.PERSON_SHEET: the 0.2.2 person sheet (item 2 redesign, slice U-PERSON; mock-remembered-v2
/// p-sug, p-ask, p-ask-err, p-wait, p-auto, p-auto-err, p-auto-confirm, p-paybill, p-buygoods, chk-200-p).
/// Drawn by [LevelSheet] while the Auto-record screens are on ([autoRecordUi]).
/// - One height for every level ([kPersonSheetHeightFactor]); back arrow, no X; header pinned, body scrolls,
///   footer pinned.
/// - Suggest: the Suggested note + "Suggests from last 10 payments" only (PM 25-11, plan section 11: no
///   "Suggest from:" choice in 0.2.2). The save keeps the stored chosen list (saveLevelChoice).
/// - Ask first: a category is required; the most-used one is pre-filled when there is history; Save with
///   none shows the error. Auto-record: category + limit field + confirm only for a NEW Auto-record.
/// - Paybill: Auto-record greyed with "Paybill payments always ask first."; Buy Goods may be Auto-record.
/// - The category is chosen through [PickCategories] in single-choice mode; null = the older list sheet.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../rules/rule_model.dart';
import '../category_choices.dart';
import 'category_pick_sheet.dart';
import 'hard_rule_confirm_dialog.dart';
import 'hard_rule_copy.dart';
import 'level_sheet.dart' show LevelSaveFn, LevelSaveResult;
import 'level_sheet_ceiling.dart';
import 'levels_copy.dart';
import 'levels_person_row.dart';
import 'person_sheet_parts.dart';
import 'person_sheet_rules.dart';
import 'setup_ports.dart';

class PersonSheet extends StatefulWidget {
  const PersonSheet({
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
  final bool focusCeiling;
  final PickCategories? pickCategories;

  /// "{k} payments" under the name; null = the line is left out (count not known to the caller).
  final int? paymentCount;

  @override
  State<PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<PersonSheet> {
  late final bool _autoAllowed = canHoldAutoRecord(widget.person.type);
  late RuleLevel _level = personSheetStartLevel(widget.person);
  late ({int? id, bool fromHistory}) _cat = personSheetStartCategory(widget.person);
  List<CategoryChoice> _cats = const [];
  bool _saving = false;
  bool _catError = false;
  String? _saveError;
  // The limit field. Starts with the stored limit, also for an autoPending person.
  late final TextEditingController _ceil = TextEditingController(text: ceilingFieldText(widget.person.ceilingCents));
  final FocusNode _ceilFocus = FocusNode();
  CeilingProblem? _ceilProblem;

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
    final offered = {for (final c in list) ?int.tryParse(c.id)};
    setState(() {
      _cats = list;
      _cat = personSheetFitCategory(widget.person, _cat, offered);
    });
  }

  bool get _needsCat => _level != RuleLevel.suggested;
  String? get _catName =>
      _cat.id == null ? null : _cats.where((c) => int.tryParse(c.id) == _cat.id).map((c) => c.name).firstOrNull;

  /// The limit to save; `ok: false` (and [_ceilProblem] set) when the text is refused. An unchanged field
  /// keeps the stored cents exactly.
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
    if (_saving) return;
    if (_level == RuleLevel.autoRecord && !_autoAllowed) return; // never asks the store for a refused level
    if (_needsCat && _catName == null) {
      setState(() => _catError = true); // must choose (mock p-ask-err)
      return;
    }
    int? ceiling;
    if (_level == RuleLevel.autoRecord) {
      final c = _readCeiling();
      if (!c.ok) return; // Save does nothing while the limit is refused
      ceiling = c.cents;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    // A NEW Auto-record asks first; a change on an existing Auto-record (the limit) does not.
    if (_level == RuleLevel.autoRecord && widget.person.level != RuleLevel.autoRecord) {
      final yes = await showHardRuleConfirm(
        context,
        name: widget.person.name,
        category: _catName!,
        ceilingCents: ceiling,
      );
      if (!mounted) return;
      if (!yes) {
        setState(() => _saving = false); // Cancel keeps the sheet open; nothing saved
        return;
      }
    }
    final r = await widget.onSave(_level, _needsCat ? _cat.id : null, ceilingCents: ceiling);
    if (!mounted) return;
    if (r == LevelSaveResult.ok) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _saveError = r == LevelSaveResult.capReached ? kLevelSheetCapReached : kLevelSheetSaveFailed;
    });
  }

  void _pick(RuleLevel l) => setState(() {
    _level = l;
    _ceilProblem = null;
    _catError = false;
  });

  Future<void> _chooseCategory() async {
    final pick = widget.pickCategories;
    int? id;
    if (pick != null) {
      final got = await pick(
        context,
        mode: CategoryPickMode.one,
        choices: _cats,
        initial: [?_cat.id],
        usedBefore: widget.person.topIds.toSet(),
      );
      id = got == null || got.isEmpty ? null : got.first;
    } else {
      id = await showCategoryPickSheet(context, categories: _cats, selected: _cat.id);
    }
    if (id != null && mounted) {
      setState(() {
        _cat = (id: id, fromHistory: false);
        _catError = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    final room = mq.size.height - mq.viewInsets.bottom - mq.padding.top;
    final height = (mq.size.height * kPersonSheetHeightFactor).clamp(0.0, room < 0 ? 0.0 : room);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Container(
        key: const Key('personSheet'),
        height: height,
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Grab(),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(6, 0, 16, 4),
                child: PersonSheetHeader(
                  name: widget.person.name,
                  maskedNumber: widget.person.maskedNumber,
                  paymentCount: widget.paymentCount,
                  onBack: () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const Key('personSheetBody'),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (i, w) in _body(p).indexed) ...[if (i > 0) const SizedBox(height: 12), w],
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: p.line),
              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), child: _footer(p)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(AppPalette p) {
    final name = widget.person.name;
    final cat = _catName;
    final hint = personSheetCategoryHint(
      hasCategory: cat != null,
      fromHistory: _cat.fromHistory,
      name: name,
      paymentCount: widget.paymentCount,
    );
    return [
      PersonLevelChoice(selected: _level, autoAllowed: _autoAllowed, onPick: _saving ? null : _pick),
      if (!_autoAllowed) const PersonPaybillLine(),
      if (_level == RuleLevel.suggested)
        Text(
          kHardSuggestsFromLast10,
          key: const Key('personSuggestsFrom'),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: p.ink),
        ),
      PersonHowBox(
        key: const Key('personHow'),
        title: personSheetHowTitle(_level),
        text: personSheetHowText(_level, name, cat),
      ),
      if (_level == RuleLevel.askFirst) ...[
        PersonCategoryLine(category: cat),
        if (_catError || hint != null) PersonCategoryNote(hint: hint, error: _catError),
      ],
      if (_level == RuleLevel.autoRecord && _autoAllowed) ...[
        PersonCategoryButton(category: cat, bad: _catError, onTap: _saving ? null : _chooseCategory),
        if (_catError || hint != null) PersonCategoryNote(hint: hint, error: _catError),
        CeilingField(
          controller: _ceil,
          focusNode: _ceilFocus,
          problem: _ceilProblem,
          onChanged: (_) {
            if (_ceilProblem != null) setState(() => _ceilProblem = null);
          },
        ),
        const PersonHowBox(key: Key('personLimitHow'), title: kHardLimitHelpTitle, text: kHardLimitHelp),
      ],
    ];
  }

  Widget _footer(AppPalette p) {
    final save = FilledButton(
      key: const Key('levelSheetSave'),
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const StadiumBorder(),
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
      ),
      onPressed: _saving ? null : _save,
      child: const Text(kHardSave, textAlign: TextAlign.center),
    );
    final choose = _level == RuleLevel.askFirst
        ? OutlinedButton(
            key: const Key('personChooseCategory'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const StadiumBorder()),
            onPressed: _saving ? null : _chooseCategory,
            child: const Text(kHardCategoryChoose, textAlign: TextAlign.center),
          )
        : null;
    final stacked = personSheetStacked(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_saveError != null) ...[
          Semantics(
            liveRegion: true,
            child: Text(
              _saveError!,
              key: const Key('levelSheetError'),
              style: TextStyle(fontSize: 13, color: p.error, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (choose == null)
          save
        else if (stacked) ...[
          choose,
          const SizedBox(height: 8),
          save,
        ] else
          Row(
            children: [
              Expanded(flex: 3, child: choose),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: save),
            ],
          ),
      ],
    );
  }
}

/// The decorative drag handle at the top (mock `.grab`; the sheet does not resize).
class _Grab extends StatelessWidget {
  const _Grab();

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return ExcludeSemantics(
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          width: 40,
          height: 4,
          decoration: BoxDecoration(color: p.line, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}
