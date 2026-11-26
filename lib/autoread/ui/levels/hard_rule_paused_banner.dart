/// §AUTOREAD.LEVELS.HARD_RULE_PAUSED_BANNER: the amber "Auto-record is paused. {n} people are asked first
/// until you resume." banner with Resume, on the To do page only (mock ctl-a-todo; item 2 redesign: the
/// Remembered page has no banner, reversal 4). Shown only while paused AND at least one person is on
/// Auto-record (B-6: never "0 people"); the count goes through peopleCount (hardPausedBanner). Follows
/// [HardRulePausePort.changes] and the rule store's changes. Draws nothing while [autoRecordUi] is false.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_pause_card.dart';
import 'hard_rule_ports.dart';

class HardRulePausedBanner extends StatefulWidget {
  const HardRulePausedBanner({super.key, required this.port, this.bulk});

  final HardRulePausePort port;

  /// For the count of people on Auto-record (null = 0, so nothing is drawn).
  final RuleBulkOps? bulk;

  @override
  State<HardRulePausedBanner> createState() => _HardRulePausedBannerState();
}

class _HardRulePausedBannerState extends State<HardRulePausedBanner> with HardRulePauseWatch<HardRulePausedBanner> {
  int? _n;
  bool _busy = false;
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
  void didUpdateWidget(covariant HardRulePausedBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_store, widget.bulk?.store)) _follow();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Recounts when someone joins or leaves Auto-record while paused.
  void _follow() {
    _sub?.cancel();
    _store = widget.bulk?.store;
    _sub = widget.bulk?.store.changes.listen((_) {
      if (paused == true) _count();
    });
  }

  @override
  void onPauseRead(bool value) {
    if (value) _count();
  }

  Future<void> _count() async {
    final seq = ++_countSeq;
    final n = await hardAutoRecordCount(widget.bulk);
    if (mounted && seq == _countSeq) setState(() => _n = n);
  }

  Future<void> _resume() async {
    if (_busy) return;
    setState(() => _busy = true);
    await setHardRulePause(widget.port, widget.bulk, false);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final n = _n;
    if (!autoRecordUi || paused != true || n == null || n <= 0) return const SizedBox.shrink();
    final p = AppPalette.of(context);
    final text = hardPausedBanner(n);
    return Semantics(
      key: const Key('hardPausedBanner'),
      container: true,
      liveRegion: true,
      child: Container(
        decoration: BoxDecoration(
          color: p.highlight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: p.sun, width: 1.5),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 4, 6, 4),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(text, style: TextStyle(fontSize: 13.5, height: 1.35, color: p.ink)),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            key: const Key('hardResume'),
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: p.ink,
              textStyle: const TextStyle(fontWeight: FontWeight.w800, decoration: TextDecoration.underline),
            ),
            onPressed: _busy ? null : _resume,
            child: const Text(kHardResume),
          ),
        ]),
      ),
    );
  }
}
