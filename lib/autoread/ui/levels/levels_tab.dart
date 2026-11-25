/// §AUTOREAD.LEVELS.TAB: the second tab of the Remembered page ("Suggest and auto-record"), 0.2.2 item 2
/// redesign (mock-remembered-v2 page-all / page-open / page-auto / page-paused / page-empty / page-end):
/// the pause switch pinned at the top, then (scrolling) the restore review line, the people in folded
/// groups by level (levels_groups.dart: Auto-record open at start, opening one closes the other), then the
/// airtime switches; the bottom bar pinned at the bottom (it gets the Set up action). No chips, no search
/// and no paused banner on this page. Named slots (null = nothing drawn) take the pause switch, the bottom
/// bar, the review line and the Set up action; the integration slice fills them. With Record receiver
/// details OFF the tab is ONE card (levels_details_off_card.dart) and draws no slots. The tab reloads when
/// it comes back from Settings or from Set up, and when the app is resumed (B-8). Composition only: every
/// part is its own widget in this folder. Without [LevelsDeps] (no rules store wired) only the airtime
/// switches show.
/// The person's sheet save: `_save` delegates to saveLevelChoice (level_sheet_open.dart). The page object
/// with the Forget all hooks is levels_extra_tab.dart (exported here, so importers keep this path).
library;

export 'levels_extra_tab.dart' show levelsExtraTab;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/format/source_types.dart' show sourceTypeName;
import '../../../ui/theme/app_colors.dart';
import '../../logic/airtime_auto.dart';
import '../../rules/rule_model.dart';
import 'airtime_switches.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart' show autoRecordUi;
import 'level_sheet.dart';
import 'level_sheet_open.dart';
import 'levels_copy.dart';
import 'levels_deps.dart';
import 'levels_details_off_card.dart';
import 'levels_groups.dart';
import 'levels_person_row.dart';

/// The tab's named slots (0.2.2 item 2 redesign). Each is drawn only when given and only while Record
/// receiver details is on. Built inside the tab, so they follow its theme. There is deliberately NO paused
/// banner slot: the amber switch and the "Paused: asking first" rows say it on this page.
class LevelsSlots {
  const LevelsSlots({this.pauseSwitch, this.bottomBar, this.reviewLine, this.onSetUp});

  /// The "Pause all Auto-record" switch row, pinned at the top (scrolls with the list when the tab is
  /// too short to pin it).
  final WidgetBuilder? pauseSwitch;

  /// The bottom bar (Reset link and Set up button), pinned at the bottom. It receives the tab's Set up
  /// action: null when [onSetUp] is null (the bar hides its Set up button then).
  final Widget Function(BuildContext context, VoidCallback? onSetUp)? bottomBar;

  /// The restore review line, first in the scrolling list.
  final WidgetBuilder? reviewLine;

  /// Opens the Set up sheet (null = no Set up). The tab reloads when it completes.
  final Future<void> Function(BuildContext context)? onSetUp;
}

/// Below this height the pause switch scrolls with the list instead of being pinned (large text on a
/// short screen keeps room for the people).
const double kLevelsPinTopMinHeight = 480;

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

class _LevelsTabState extends State<LevelsTab> with WidgetsBindingObserver {
  List<LevelPerson> _people = const [];
  bool _loaded = false;
  bool _failed = false;
  bool _detailsOff = false;
  bool _paused = false;

  /// The one open group; set to the start group the first time people are shown, then the user's.
  RuleLevel? _open;
  bool _openSet = false;
  StreamSubscription<void>? _sub;
  int _gen = 0;

  /// Read once per tab: the 0.2.2 Auto-record screens are on.
  final bool _hard = autoRecordUi;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sub = widget.deps?.store.changes.listen((_) => _load());
    if (_hard) widget.deps?.pause?.changes.addListener(_readPause);
    _load();
    _readPause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    if (_hard) widget.deps?.pause?.changes.removeListener(_readPause);
    super.dispose();
  }

  /// B-8: back in the app (Settings may have changed Record receiver details): read everything again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    _load();
    _readPause();
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
      final cats = await levelCategoryNames(d);
      final rules = await d.store.all();
      final known = d.known == null ? const <KnownPerson>[] : await d.known!();
      final knownPochi = {for (final k in known) if (k.type == ReceiverType.pochi) k.key};
      final byId = <String, LevelPerson>{};
      Future<LevelPerson> make(ReceiverType t, String key, String name, ReceiverRule? r) async =>
          (await buildLevelPerson(d, t, key, name, r, cats)).withChosenFrom(r, cats);

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
        if (!_openSet && !off && _people.isNotEmpty) {
          _open = initialOpenGroup(_people);
          _openSet = true;
        }
      });
    } catch (_) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _loaded = true;
        _failed = true;
      });
    }
  }

  /// The person sheet's save (level_sheet_open.dart, shared with the offer pill): Suggested keeps the rule,
  /// the ceiling is forwarded, the notice follows while the Auto-record screens are on, and its Change
  /// opens this person's sheet again here, with the field focused.
  Future<LevelSaveResult> _save(LevelPerson x, RuleLevel level, int? cat, int? ceilingCents) =>
      saveLevelChoice(widget.deps!, x, level, cat, ceilingCents, notify: _hard, onChangeCeiling: () => _changeCeiling(x));

  /// The pill's "Change": the person's sheet again, with the field focused.
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

  void _toggle(RuleLevel l) => setState(() {
        _open = toggledGroup(_open, l);
        _openSet = true;
      });

  /// B-7 + B-8: Settings at the "Record receiver details" switch; read again when it is closed.
  Future<void> _openSettings() async {
    await openSettingsAtCaptureReceiver(context);
    _refresh();
  }

  /// The Set up action given to the bottom bar (null = no Set up); read again when the sheet is closed.
  VoidCallback? get _setUp {
    final open = widget.slots.onSetUp;
    if (open == null) return null;
    return () async {
      await open(context);
      _refresh();
    };
  }

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
    return LayoutBuilder(builder: (context, box) {
      final pinTop = box.maxHeight >= kLevelsPinTopMinHeight;
      final top = on && slots.pauseSwitch != null ? slots.pauseSwitch!(context) : null;
      final list = ListView(
        key: const Key('levelsTab'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          if (!on)
            LevelsDetailsOffCard(onOpenSettings: _openSettings)
          else ...[
            if (top != null && !pinTop) top,
            if (slots.reviewLine != null) slots.reviewLine!(context),
            // Flag off: the 0.2.1 helper line stays; the redesigned page has none (mock page-all).
            if (!_hard)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text(kLevelsHelper,
                    key: const Key('levelsHelper'), style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
              ),
            if (_failed)
              _note(p, kLevelsLoadFailed, const Key('levelsFailed'))
            else if (_loaded && _people.isEmpty)
              _note(p, _hard ? kHardPageFirstTime : kLevelsEmpty, const Key('levelsEmpty'), center: _hard)
            else if (_loaded)
              LevelsGroups(
                people: _people,
                open: _open,
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
          _airtimeHeader(p),
          AirtimeSwitches(controller: widget.controller),
        ],
      );
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (top != null && pinTop) top,
        Expanded(child: list),
        if (on && slots.bottomBar != null) slots.bottomBar!(context, _setUp),
      ]);
    });
  }

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

  /// A one-line state of the list (failed, nobody yet); a live region so a screen reader hears it.
  Widget _note(AppPalette p, String text, Key key, {bool center = false}) => Padding(
        padding: EdgeInsets.fromLTRB(14, center ? 20 : 12, 14, 4),
        child: Semantics(
          liveRegion: true,
          child: Text(text,
              key: key,
              textAlign: center ? TextAlign.center : TextAlign.start,
              style: TextStyle(fontSize: center ? 14 : 13, height: 1.4, color: p.mutedInk)),
        ),
      );
}
