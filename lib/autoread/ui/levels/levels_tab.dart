/// §AUTOREAD.LEVELS.TAB: the second tab of the Remembered page ("Suggest and
/// auto-record"): helper line, level filter, type chips (one type open at a time,
/// Send Money first), then the airtime switches (Airtime) or one row per person
/// or account (the other types). The page's one "?" explains this tab. Composition only: every part is its own
/// widget in this folder. Without [LevelsDeps] (no rules store wired) only the
/// airtime switches show.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/screens/remembered/remembered_extra_tab.dart';
import '../../../ui/theme/app_colors.dart';
import '../../logic/airtime_auto.dart';
import '../../rules/rule_cleanup.dart';
import '../../rules/rule_model.dart';
import 'airtime_switches.dart';
import 'level_filter_row.dart';
import 'level_sheet.dart';
import 'levels_copy.dart';
import 'levels_deps.dart';
import 'levels_help.dart';
import 'levels_person_row.dart';
import 'type_chips_row.dart';

/// The page object the Remembered screen takes as its second tab.
///
/// [cleanup] (optional) makes a Forget, a Change to Send Money and a Forget all on the recipients list
/// also remove the person's rule.
RememberedExtraTab levelsExtraTab(AirtimeAutoController controller, {LevelsDeps? deps, RuleCleanup? cleanup}) =>
    _LevelsExtraTab(controller, deps, cleanup);

class _LevelsExtraTab implements RememberedExtraTab, RememberedForgetHooks {
  _LevelsExtraTab(this.c, this.deps, this.cleanup);
  final AirtimeAutoController c;
  final LevelsDeps? deps;
  final RuleCleanup? cleanup;

  @override
  Future<void> onNameForgotten(String key) async => cleanup?.onNameForgotten(key);
  @override
  Future<void> onNameChangedToSendMoney(String key) async => cleanup?.onNameChangedToSendMoney(key);
  @override
  Future<void> onAllNamesForgotten() async => cleanup?.onAllNamesForgotten();

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
  Widget buildBody(BuildContext context) => LevelsTab(controller: c, deps: deps);
}

class LevelsTab extends StatefulWidget {
  const LevelsTab({super.key, required this.controller, this.deps});
  final AirtimeAutoController controller;
  final LevelsDeps? deps;

  @override
  State<LevelsTab> createState() => _LevelsTabState();
}

class _LevelsTabState extends State<LevelsTab> {
  List<LevelPerson> _people = const [];
  bool _loaded = false;
  bool _failed = false;
  LevelFilter _filter = LevelFilter.all;
  TypeChip _chip = TypeChip.sendMoney; // one type open at a time, money out first
  StreamSubscription<void>? _sub;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.deps?.store.changes.listen((_) => _load());
    _load();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final d = widget.deps;
    if (d == null) {
      setState(() => _loaded = true);
      return;
    }
    final gen = ++_gen;
    try {
      final cats = {for (final c in await d.categories.categories()) if (int.tryParse(c.id) != null) int.parse(c.id): c.name};
      final rules = await d.store.all();
      final known = d.known == null ? const <KnownPerson>[] : await d.known!();
      final knownPochi = {for (final k in known) if (k.type == ReceiverType.pochi) k.key};
      final byId = <String, LevelPerson>{};
      Future<LevelPerson> make(ReceiverType t, String key, String name, ReceiverRule? r) async {
        if (r != null && r.level == RuleLevel.askFirst) {
          final id = r.categoryId;
          return LevelPerson(
              type: t, key: key, name: name, level: r.level, categoryId: id, categoryNames: [if (id != null && cats[id] != null) cats[id]!]);
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
            categoryNames: [for (final i in ids) if (cats[i] != null) cats[i]!]);
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

  /// Ask first before Suggested, then by name.
  List<LevelPerson> _shown() {
    final l = _people.where((x) => _filter.matches(x.level) && _chip.receiver == x.type).toList();
    l.sort((a, b) {
      final r = b.level.code.compareTo(a.level.code);
      return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return l;
  }

  Future<LevelSaveResult> _save(LevelPerson x, RuleLevel level, int? cat) async {
    final d = widget.deps!;
    try {
      if (level == RuleLevel.suggested) {
        await d.store.forget(x.type, x.key);
        return LevelSaveResult.ok;
      }
      final ok = await d.store.setLevel(x.type, x.key, name: x.name, level: level, categoryId: cat, at: d.now());
      return ok ? LevelSaveResult.ok : LevelSaveResult.capReached;
    } catch (_) {
      return LevelSaveResult.failed;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final d = widget.deps;
    final showAir = d == null || _chip == TypeChip.airtime;
    final showPeople = d != null && _chip.receiver != null;
    final shown = _shown();
    return ListView(
      key: const Key('levelsTab'),
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        if (d != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(kLevelsHelper, key: const Key('levelsHelper'), style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
          ),
          LevelFilterRow(value: _filter, onChanged: (f) => setState(() => _filter = f)),
          TypeChipsRow(selected: _chip, onChanged: (c) => setState(() => _chip = c)),
        ],
        if (showAir) AirtimeSwitches(controller: widget.controller),
        if (showPeople) ...[
          if (_failed)
            _note(p, kLevelsLoadFailed, const Key('levelsFailed'))
          else if (_loaded && shown.isEmpty)
            _note(p, _filter == LevelFilter.all ? kLevelsEmpty : kLevelsFilterEmpty, const Key('levelsEmpty'))
          else
            for (final x in shown)
              LevelsPersonRow(
                key: Key('levelRow.${x.type.code}.${x.key}'),
                person: x,
                onLevelTap: () => showLevelSheet(context, person: x, categories: d.choicesFor(x.type), onSave: (l, c, {ceilingCents}) => _save(x, l, c)),
              ),
        ],
      ],
    );
  }

  Widget _note(AppPalette p, String text, Key key) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Text(text, key: key, style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
      );
}
