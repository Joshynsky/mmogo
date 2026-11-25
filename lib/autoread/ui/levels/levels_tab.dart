/// §AUTOREAD.LEVELS.TAB: the second tab of the Remembered page ("Suggest and
/// auto-record"), layout A (0.2.2 U5; PM D3 replaced the 0.2.1 level filter and type chips): helper line,
/// search, people in sections by level (levels_groups.dart; Auto-record first, Suggested folded), then the
/// airtime switches. Named slots (null = nothing drawn) take the pause card, the paused banner, the reset
/// footer and the restore review line, which the integration slice fills. With Record receiver details OFF
/// the tab explains itself (Open Settings) and draws no slots. Composition only: every part is its own
/// widget in this folder. Without [LevelsDeps] (no rules store wired) only the airtime switches show.
/// The level sheet's save lives here (`_save`): Suggested KEEPS the rule (PM 25-11), the ceiling is
/// forwarded, and the one notice (deps.notice) follows a successful save while the Auto-record screens are on.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart' show sourceTypeName;
import '../../../ui/screens/remembered/remembered_extra_tab.dart';
import '../../../ui/shell/routes.dart' show Routes;
import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../logic/airtime_auto.dart';
import '../../logic/phone_mask.dart' show nameWithMask;
import '../../rules/rule_cleanup.dart';
import '../../rules/rule_model.dart';
import 'airtime_switches.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'level_sheet.dart';
import 'levels_copy.dart';
import 'levels_deps.dart';
import 'levels_groups.dart';
import 'levels_help.dart';
import 'levels_person_row.dart';
import 'levels_search.dart';

/// The tab's named slots (0.2.2). Each is drawn only when given; the integration slice passes the pause
/// card, the paused banner, the reset footer and the restore review line. Built inside the tab, so they
/// follow its theme.
class LevelsSlots {
  const LevelsSlots({this.pauseCard, this.pausedBanner, this.resetFooter, this.reviewLine});

  /// Under the helper line, above the search.
  final WidgetBuilder? pauseCard;

  /// Pinned at the top of the tab, above the list.
  final WidgetBuilder? pausedBanner;

  /// Pinned at the bottom of the tab.
  final WidgetBuilder? resetFooter;

  /// Pinned at the top of the tab, under the paused banner.
  final WidgetBuilder? reviewLine;
}

/// The page object the Remembered screen takes as its second tab.
///
/// [cleanup] (optional) makes a Forget, a Change to Send Money and a Forget all on the recipients list
/// also remove the person's rule. [detailsOn] reads "Record receiver details" (null = treated as on).
RememberedExtraTab levelsExtraTab(AirtimeAutoController controller,
        {LevelsDeps? deps, RuleCleanup? cleanup, Future<bool> Function()? detailsOn, LevelsSlots slots = const LevelsSlots()}) =>
    _LevelsExtraTab(controller, deps, cleanup, detailsOn, slots);

class _LevelsExtraTab implements RememberedExtraTab, RememberedForgetHooks, RememberedForgetAllCopy {
  _LevelsExtraTab(this.c, this.deps, this.cleanup, this.detailsOn, this.slots);
  final AirtimeAutoController c;
  final LevelsDeps? deps;
  final RuleCleanup? cleanup;
  final Future<bool> Function()? detailsOn;
  final LevelsSlots slots;

  @override
  Future<void> onNameForgotten(String key) async => cleanup?.onNameForgotten(key);
  @override
  Future<void> onNameChangedToSendMoney(String key) async => cleanup?.onNameChangedToSendMoney(key);
  @override
  Future<void> onAllNamesForgotten() async {
    await cleanup?.onAllNamesForgotten();
    // 0.2.2: the Forget all words say levels and ceilings are forgotten too, so every rule goes (not only
    // the Pochi ones). The pause switch is not a rule and stays.
    final d = deps;
    if (!autoRecordUi || d == null) return;
    try {
      for (final r in await d.store.all()) {
        await d.store.forget(r.type, r.key);
      }
    } catch (_) {
      // Partly done: say so (the existing save-failed toast) and throw, so the page shows no "Forgot n"
      // success toast; it marks the run failed and reloads, and the rules still stored stay listed here.
      PillToast.show(kLevelSheetSaveFailed);
      rethrow;
    }
  }

  /// Flag on (PM 25-11): the TRUE count of everyone Forget all removes: every remembered name plus every
  /// person with a rule, each once (a Pochi rule lives under its remembered name's key, so that person
  /// counts once; other rules are keyed by number and are separate people). Flag off: null = today's dialog.
  @override
  Future<RememberedForgetAllText?> forgetAllText(List<String> nameKeys) async {
    if (!autoRecordUi) return null;
    final names = nameKeys.toSet();
    final d = deps;
    final rules = d == null ? const <ReceiverRule>[] : await d.store.all(); // a failure throws: no dialog
    final n = names.length + rules.where((r) => !(r.type == ReceiverType.pochi && names.contains(r.key))).length;
    return RememberedForgetAllText(title: hardForgetTitle(n), body: kHardForgetBody, ok: kHardForgetOk, toast: hardForgetToast(n));
  }

  @override
  Listenable get listenable => c;
  @override
  String get pageTitle => 'Remembered';
  @override
  String get recipientsTabLabel => kLevelsRecipientsTab;
  @override
  String tabLabel() => kLevelsTabLabel;
  @override
  String get forgetAllLabel => kLevelsForgetAllLabel;
  @override
  String get forgetAllNote => kLevelsForgetAllNote;
  @override
  RememberedExtraHelp get help => levelsHelp();
  @override
  Widget buildBody(BuildContext context) => LevelsTab(controller: c, deps: deps, detailsOn: detailsOn, slots: slots);
}

class LevelsTab extends StatefulWidget {
  const LevelsTab({super.key, required this.controller, this.deps, this.detailsOn, this.slots = const LevelsSlots()});
  final AirtimeAutoController controller;
  final LevelsDeps? deps;

  /// "Record receiver details"; null = treated as on.
  final Future<bool> Function()? detailsOn;
  final LevelsSlots slots;

  @override
  State<LevelsTab> createState() => _LevelsTabState();
}

class _LevelsTabState extends State<LevelsTab> {
  List<LevelPerson> _people = const [];
  bool _loaded = false;
  bool _failed = false;
  bool _detailsOff = false;
  bool _paused = false;
  final Set<RuleLevel> _folded = {...kLevelGroupsFoldedAtStart};
  final TextEditingController _search = TextEditingController();
  StreamSubscription<void>? _sub;
  int _gen = 0;

  /// Read once per tab: the 0.2.2 Auto-record screens are on.
  final bool _hard = autoRecordUi;

  @override
  void initState() {
    super.initState();
    _sub = widget.deps?.store.changes.listen((_) => _load());
    if (_hard) widget.deps?.pause?.changes.addListener(_readPause);
    _load();
    _readPause();
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_hard) widget.deps?.pause?.changes.removeListener(_readPause);
    _search.dispose();
    super.dispose();
  }

  Future<void> _readPause() async {
    final port = widget.deps?.pause;
    if (!_hard || port == null) return;
    final v = await port.isPaused(); // fail closed: any failure reads as paused
    if (mounted && v != _paused) setState(() => _paused = v);
  }

  Future<void> _load() async {
    final d = widget.deps;
    if (d == null) {
      setState(() => _loaded = true);
      return;
    }
    final gen = ++_gen;
    try {
      final off = widget.detailsOn != null && !await widget.detailsOn!();
      final cats = {for (final c in await d.categories.categories()) if (int.tryParse(c.id) != null) int.parse(c.id): c.name};
      final rules = await d.store.all();
      final known = d.known == null ? const <KnownPerson>[] : await d.known!();
      final knownPochi = {for (final k in known) if (k.type == ReceiverType.pochi) k.key};
      final byId = <String, LevelPerson>{};
      Future<LevelPerson> make(ReceiverType t, String key, String name, ReceiverRule? r) async {
        if (r != null && r.level != RuleLevel.suggested) {
          final id = r.categoryId;
          return LevelPerson(
              type: t,
              key: key,
              name: name,
              level: r.level,
              categoryId: id,
              categoryNames: [if (id != null && cats[id] != null) cats[id]!],
              ceilingCents: r.ceilingCents,
              autoPending: r.autoPending);
        }
        List<int>? top;
        try {
          top = await d.history.topTwo(t, key);
        } catch (_) {}
        final ids = top ?? const <int>[];
        return LevelPerson(
            type: t,
            key: key,
            name: name,
            level: RuleLevel.suggested,
            topIds: ids,
            categoryNames: [for (final i in ids) if (cats[i] != null) cats[i]!],
            autoPending: r?.autoPending ?? false);
      }

      final ruleBy = {for (final r in rules) '${r.type.code}.${r.key}': r};
      for (final r in rules) {
        if (r.type == ReceiverType.pochi && !knownPochi.contains(r.key)) continue; // Pochi: remembered names only
        byId['${r.type.code}.${r.key}'] = await make(r.type, r.key, r.name, r);
      }
      for (final k in known) {
        final id = '${k.type.code}.${k.key}';
        if (byId.containsKey(id)) continue;
        byId[id] = await make(k.type, k.key, k.name, ruleBy[id]);
      }
      if (!mounted || gen != _gen) return;
      setState(() {
        _people = byId.values.toList();
        _detailsOff = off;
        _loaded = true;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loaded = true;
        _failed = true;
      });
    }
  }

  /// The name the sheet and the notice use (masked number for Send Money).
  static String _who(LevelPerson x) => x.type == ReceiverType.sendMoney ? nameWithMask(x.name, x.key) : x.name;

  /// The level sheet's save. Suggested keeps the rule (level Suggested, stored category passed explicitly,
  /// ceiling and pending mark cleared by setLevel); nobody without a rule gets one for Suggested. Ask first
  /// and Auto-record pass the chosen category (stored one when none) and the ceiling (Auto-record only).
  Future<LevelSaveResult> _save(LevelPerson x, RuleLevel level, int? cat, int? ceilingCents) async {
    final d = widget.deps!;
    final ceiling = level == RuleLevel.autoRecord ? ceilingCents : null;
    try {
      final stored = await d.store.get(x.type, x.key);
      final bool ok;
      if (level == RuleLevel.suggested) {
        // No rule = already Suggested: nothing is saved, so no notice either.
        if (stored == null) return LevelSaveResult.ok;
        ok = await d.store.setLevel(x.type, x.key,
            name: x.name, level: RuleLevel.suggested, categoryId: stored.categoryId, at: d.now());
      } else {
        ok = await d.store.setLevel(x.type, x.key,
            name: x.name, level: level, categoryId: cat ?? stored?.categoryId, ceilingCents: ceiling, at: d.now());
      }
      if (!ok) return LevelSaveResult.capReached;
    } catch (_) {
      return LevelSaveResult.failed;
    }
    if (_hard) {
      try {
        d.notice.show(_who(x), level, ceiling, level == RuleLevel.autoRecord ? () => _changeCeiling(x) : null);
      } catch (_) {} // the notice never undoes a stored change
    }
    return LevelSaveResult.ok;
  }

  /// The pill's "Change ceiling": the person's sheet again, with the field focused.
  void _changeCeiling(LevelPerson before) {
    if (!mounted) return;
    final now = _people.where((p) => p.id == before.id).firstOrNull ?? before;
    _openSheet(now, focusCeiling: true);
  }

  void _openSheet(LevelPerson x, {bool focusCeiling = false}) {
    final d = widget.deps;
    if (d == null) return;
    showLevelSheet(context,
        person: x,
        categories: d.choicesFor(x.type),
        focusCeiling: focusCeiling,
        onSave: (l, c, {ceilingCents}) => _save(x, l, c, ceilingCents));
  }

  void _toggle(RuleLevel l) => setState(() => _folded.contains(l) ? _folded.remove(l) : _folded.add(l));

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final d = widget.deps;
    if (d == null) {
      return ListView(
        key: const Key('levelsTab'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [AirtimeSwitches(controller: widget.controller)],
      );
    }
    final slots = widget.slots;
    final on = !_detailsOff;
    final list = ListView(
      key: const Key('levelsTab'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (!on)
          ..._detailsOffBody(p)
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(_hard ? kHardPageHelper : kLevelsHelper,
                key: const Key('levelsHelper'), style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
          ),
          if (slots.pauseCard != null) slots.pauseCard!(context),
          if (_failed)
            _note(p, kLevelsLoadFailed, const Key('levelsFailed'))
          else if (_loaded && _people.isEmpty)
            _note(p, kLevelsEmpty, const Key('levelsEmpty'))
          else if (_loaded) ...[
            LevelsSearchField(controller: _search, onChanged: (_) => setState(() {})),
            LevelsGroups(
              people: _people,
              query: _search.text,
              folded: _folded,
              onToggle: _toggle,
              rowBuilder: (x) => LevelsPersonRow(
                key: Key('levelRow.${x.type.code}.${x.key}'),
                person: x,
                paused: _paused,
                hard: _hard,
                onLevelTap: () => _openSheet(x),
              ),
            ),
          ],
        ],
        _airtimeHeader(p),
        AirtimeSwitches(controller: widget.controller),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (on && slots.pausedBanner != null) slots.pausedBanner!(context),
      if (on && slots.reviewLine != null) slots.reviewLine!(context),
      Expanded(child: list),
      if (on && slots.resetFooter != null) slots.resetFooter!(context),
    ]);
  }

  /// Record receiver details OFF (mock rst-off-page): the line, Open Settings, the empty line.
  List<Widget> _detailsOffBody(AppPalette p) => [
        Container(
          key: const Key('levelsDetailsOff'),
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(16)),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Text(kHardDetailsOffLine, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.tintInk)),
            TextButton(
              key: const Key('levelsOpenSettings'),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              onPressed: () => Navigator.of(context).pushNamed(Routes.settings),
              child: Text(kHardOpenSettings, style: TextStyle(fontWeight: FontWeight.w800, color: p.primary)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
          child: Text(kHardDetailsOffEmpty,
              key: const Key('levelsDetailsOffEmpty'), textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: p.mutedInk)),
        ),
      ];

  /// The airtime switches' own heading (the type name, as the old Airtime chip said).
  Widget _airtimeHeader(AppPalette p) => Semantics(
        header: true,
        label: sourceTypeName('AIRTIME'),
        excludeSemantics: true,
        child: Padding(
          key: const Key('levelsAirtimeHeader'),
          padding: const EdgeInsets.fromLTRB(16, 18, 14, 4),
          child: Text(sourceTypeName('AIRTIME').toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: p.mutedInk)),
        ),
      );

  Widget _note(AppPalette p, String text, Key key) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Text(text, key: key, style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
      );
}
