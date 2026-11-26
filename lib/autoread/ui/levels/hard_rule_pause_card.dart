/// §AUTOREAD.LEVELS.HARD_RULE_PAUSE_CARD: the reversible "Pause all Auto-record" switch ROW at the top of the
/// Remembered page (item 2 redesign, mock-remembered-v2 page-all / page-paused; amber switch only when on,
/// hidden while nobody is on Auto-record, B-6), plus the pieces every pause control shares:
/// [HardRulePauseWatch] (the state read from [HardRulePausePort.changes], so the row, the To do banner, the
/// Settings row and the To do tag stay in sync and snap back after a failed write), [setHardRulePause]
/// (write + toast) and [hardPauseSwitch] (the Settings row's switch).
/// Draws nothing while [autoRecordUi] is false (dormant).
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../rules/rule_model.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart';
import 'levels_copy.dart' show kSuggestSaveFailed;

/// Keeps [paused] equal to what [pausePort] stores. Re-reads after every change (also a failed one), so a
/// switch snaps back. Fail closed: a read that throws is paused. Null until the first read is done.
mixin HardRulePauseWatch<T extends StatefulWidget> on State<T> {
  HardRulePausePort? get pausePort;

  bool? paused;
  HardRulePausePort? _watched;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_watched, pausePort)) _watch();
  }

  @override
  void dispose() {
    _watched?.changes.removeListener(rereadPause);
    super.dispose();
  }

  void _watch() {
    _watched?.changes.removeListener(rereadPause);
    _watched = pausePort;
    _watched?.changes.addListener(rereadPause);
    rereadPause();
  }

  /// Numbers each read; only the newest read may set [paused] (an older read finishing late is dropped).
  int _readSeq = 0;

  /// Reads the stored state again (fail closed). Reads can overlap (two quick changes); the last one
  /// started wins, whatever order they finish in.
  Future<void> rereadPause() async {
    final port = _watched;
    if (port == null) return;
    final seq = ++_readSeq;
    var v = true;
    try {
      v = await port.isPaused();
    } catch (_) {
      v = true;
    }
    if (!mounted || !identical(port, _watched) || seq != _readSeq) return;
    setState(() => paused = v);
    onPauseRead(v);
  }

  /// Called after every read (the banner reloads its count here).
  void onPauseRead(bool value) {}
}

/// How many people are on Auto-record (the banner's and the resume toast's number). 0 on a failure.
Future<int> hardAutoRecordCount(RuleBulkOps? bulk) async {
  if (bulk == null) return 0;
  try {
    return (await bulk.countByLevel())[RuleLevel.autoRecord] ?? 0;
  } catch (_) {
    return 0;
  }
}

/// Stores [paused] and shows the toast: paused, resumed for n people, or the save-failed line. The caller's
/// switch follows the port (it fires either way), so a failure snaps it back. Returns whether it was stored.
Future<bool> setHardRulePause(HardRulePausePort port, RuleBulkOps? bulk, bool paused) async {
  var ok = false;
  try {
    ok = await port.setPaused(paused);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    PillToast.show(kSuggestSaveFailed);
  } else if (paused) {
    PillToast.show(kHardPausedToast);
  } else {
    PillToast.show(hardResumedToast(await hardAutoRecordCount(bulk)));
  }
  return ok;
}

/// The Settings row's amber switch (mock `.sw.amb`; the page row uses [hardPauseRowSwitch]).
Switch hardPauseSwitch(AppPalette p, {Key? key, required bool value, ValueChanged<bool>? onChanged}) => Switch(
      key: key,
      value: value,
      onChanged: onChanged,
      activeThumbColor: p.surface,
      activeTrackColor: p.sun,
      inactiveTrackColor: p.surface,
      trackOutlineColor: WidgetStatePropertyAll(p.sun),
    );

/// The page row's switch (mock-remembered-v2 `.sw`): neutral when off, amber only when on (PM 25-11: "only
/// the switch turns amber"). Not colour-only: the thumb moves (mirrored in RTL by [Switch]) and carries a
/// pause mark while on; a screen reader hears the toggled state.
Switch hardPauseRowSwitch(AppPalette p, {Key? key, required bool value, ValueChanged<bool>? onChanged}) => Switch(
      key: key,
      value: value,
      onChanged: onChanged,
      activeThumbColor: p.ink,
      activeTrackColor: p.sun,
      inactiveThumbColor: p.mutedInk,
      inactiveTrackColor: p.track,
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.sun : p.mutedInk),
      thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Icon(Icons.pause, size: 16, color: p.sun) : null),
    );

/// The "Pause all Auto-record" switch row at the top of the Remembered page's second tab (item 2 redesign,
/// mock page-all / page-paused): title, the signed line, the switch. The whole row is one switch for a
/// screen reader. Same port as the Settings row; a failed write snaps back (the port fires either way).
/// Hidden while nobody is on Auto-record (B-6): it follows [RuleBulkOps.store]'s changes. With no [bulk]
/// (or a count that cannot be read) it is shown: a switch that does nothing harms less than a missing one.
/// Q1 (Pause switches itself off when the last person leaves Auto-record) is NOT done here: B-PAUSE's
/// pause_notice_sync.dart owns it; this row only hides.
class HardRulePauseCard extends StatefulWidget {
  const HardRulePauseCard({super.key, required this.port, this.bulk});

  final HardRulePausePort port;

  /// For the resume toast's count and the hide-at-0 count (null = always shown, toast count 0).
  final RuleBulkOps? bulk;

  @override
  State<HardRulePauseCard> createState() => _HardRulePauseCardState();
}

class _HardRulePauseCardState extends State<HardRulePauseCard> with HardRulePauseWatch<HardRulePauseCard> {
  bool _busy = false;

  /// People on Auto-record; null = not known (no bulk, or the read failed): shown.
  int? _auto;
  bool _counted = false;
  StreamSubscription<void>? _sub;
  Object? _store;
  int _countSeq = 0;

  @override
  HardRulePausePort? get pausePort => widget.port;

  @override
  void initState() {
    super.initState();
    _follow();
  }

  @override
  void didUpdateWidget(covariant HardRulePauseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // LevelsDeps.bulk is a new object on every read: follow the store, not the wrapper.
    if (!identical(_store, widget.bulk?.store)) _follow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _follow() {
    _sub?.cancel();
    _store = widget.bulk?.store;
    _sub = widget.bulk?.store.changes.listen((_) => _count());
    _count();
  }

  Future<void> _count() async {
    final bulk = widget.bulk;
    final seq = ++_countSeq;
    int? n;
    if (bulk != null) {
      try {
        n = (await bulk.countByLevel())[RuleLevel.autoRecord] ?? 0;
      } catch (_) {
        n = null;
      }
    }
    if (!mounted || seq != _countSeq) return;
    setState(() {
      _auto = n;
      _counted = true;
    });
  }

  Future<void> _set(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    await setHardRulePause(widget.port, widget.bulk, v);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = paused;
    if (!autoRecordUi || on == null || !_counted || _auto == 0) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    final change = _busy ? null : () => _set(!on);
    return Semantics(
      container: true,
      toggled: on,
      enabled: !_busy,
      label: kHardPauseTitle,
      hint: kHardPauseSub,
      onTap: change,
      excludeSemantics: true,
      child: Material(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.line, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('hardPauseCard'),
          onTap: change,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 6, 6),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kHardPauseTitle, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: p.ink)),
                      const SizedBox(height: 1),
                      Text(kHardPauseSub, style: TextStyle(fontSize: 12.5, height: 1.3, color: p.mutedInk)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                hardPauseRowSwitch(p, key: const Key('hardPauseSwitch'), value: on, onChanged: _busy ? null : _set),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
