/// §AUTOREAD.LEVELS.HARD_RULE_PAUSE_CARD: the amber, reversible "Pause all Auto-record" switch card on the
/// Remembered page (mock ctl-a), plus the two pieces every pause control shares: [HardRulePauseWatch] (the
/// state read from [HardRulePausePort.changes], so the card, the banner, the Settings row and the To do tag
/// stay in sync and snap back after a failed write) and [setHardRulePause] (write + toast).
/// Draws nothing while [autoRecordUi] is false (dormant).
library;

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

/// The amber switch colours shared by the card and the Settings row (mock `.sw.amb`).
Switch hardPauseSwitch(AppPalette p, {Key? key, required bool value, ValueChanged<bool>? onChanged}) => Switch(
      key: key,
      value: value,
      onChanged: onChanged,
      activeThumbColor: p.surface,
      activeTrackColor: p.sun,
      inactiveTrackColor: p.surface,
      trackOutlineColor: WidgetStatePropertyAll(p.sun),
    );

/// The card: title, one line, the amber switch. The whole card is one switch for a screen reader.
class HardRulePauseCard extends StatefulWidget {
  const HardRulePauseCard({super.key, required this.port, this.bulk});

  final HardRulePausePort port;

  /// For the resume toast's count (null = 0).
  final RuleBulkOps? bulk;

  @override
  State<HardRulePauseCard> createState() => _HardRulePauseCardState();
}

class _HardRulePauseCardState extends State<HardRulePauseCard> with HardRulePauseWatch<HardRulePauseCard> {
  bool _busy = false;

  @override
  HardRulePausePort? get pausePort => widget.port;

  Future<void> _set(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    await setHardRulePause(widget.port, widget.bulk, v);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final on = paused;
    if (!autoRecordUi || on == null) return const SizedBox.shrink();
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
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: p.sun, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('hardPauseCard'),
          onTap: change,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(kHardPauseTitle, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: p.ink)),
                      const SizedBox(height: 2),
                      Text(kHardPauseSub, style: TextStyle(fontSize: 12.5, height: 1.35, color: p.mutedInk)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                hardPauseSwitch(p, key: const Key('hardPauseSwitch'), value: on, onChanged: _busy ? null : _set),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
