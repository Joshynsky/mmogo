/// §AUTOREAD.LEVELS.HARD_RULE_PAUSED_BANNER: the amber "Auto-record is paused. {n} people are asked first
/// until you resume." banner with Resume (mock ctl-a-paused on the Remembered page, ctl-a-todo on To do).
/// Shown only while paused; follows [HardRulePausePort.changes]. Draws nothing while [autoRecordUi] is false.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_pause_card.dart';
import 'hard_rule_ports.dart';

class HardRulePausedBanner extends StatefulWidget {
  const HardRulePausedBanner({super.key, required this.port, this.bulk});

  final HardRulePausePort port;

  /// For the count of people on Auto-record (null = 0).
  final RuleBulkOps? bulk;

  @override
  State<HardRulePausedBanner> createState() => _HardRulePausedBannerState();
}

class _HardRulePausedBannerState extends State<HardRulePausedBanner> with HardRulePauseWatch<HardRulePausedBanner> {
  int? _n;
  bool _busy = false;

  @override
  HardRulePausePort? get pausePort => widget.port;

  @override
  void onPauseRead(bool value) {
    if (value) _count();
  }

  Future<void> _count() async {
    final n = await hardAutoRecordCount(widget.bulk);
    if (mounted) setState(() => _n = n);
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
    if (!autoRecordUi || paused != true || n == null) return const SizedBox.shrink();
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
