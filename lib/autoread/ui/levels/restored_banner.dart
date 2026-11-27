/// §AUTOREAD.LEVELS.RESTORED_BANNER: "Auto-record was restored for N people. Keep it?" with Keep and
/// Turn off, first in the Remembered page's second tab (0.2.2 restore; replaces the old review line).
/// Draws nothing at 0 people, while [autoRecordUi] is false, or while "Record receiver details" is off
/// ([detailsOn]). Hides itself after Keep or Turn off (the port's count drops to 0). A failed write keeps
/// the banner and says so. All words are drafts for PM sign-off (hard_rule_copy.dart).
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/pill_toast.dart';
import '../../../ui/widgets/tap_target.dart';
import 'hard_rule_copy.dart';
import 'hard_rule_ports.dart';
import 'levels_copy.dart' show kLevelSheetSaveFailed;
import 'restored_auto_record_port.dart';

class RestoredBanner extends StatefulWidget {
  /// [port] null = the default over [bulk]'s store, owned (and disposed) by the banner.
  const RestoredBanner({super.key, required this.bulk, this.port, this.detailsOn = true, this.now = DateTime.now});
  final RuleBulkOps bulk;
  final RestoredAutoRecordPort? port;
  final bool detailsOn;
  final DateTime Function() now;

  @override
  State<RestoredBanner> createState() => _RestoredBannerState();
}

class _RestoredBannerState extends State<RestoredBanner> {
  late final RestoredAutoRecordPort _port = widget.port ?? StoreRestoredAutoRecord(widget.bulk, now: widget.now);
  bool _busy = false;

  @override
  void dispose() {
    if (widget.port == null) _port.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() op) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await op();
    } catch (_) {
      PillToast.show(kLevelSheetSaveFailed);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!autoRecordUi || !widget.detailsOn) return const SizedBox.shrink();
    return ValueListenableBuilder<int>(
      valueListenable: _port.count,
      builder: (context, n, _) {
        if (n <= 0) return const SizedBox.shrink();
        final p = AppPalette.of(context);
        TextButton button(String key, String label, VoidCallback? on) => TextButton(
              key: Key(key),
              onPressed: on,
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                foregroundColor: p.tintInk,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: Text(label),
            );
        return Semantics(
          container: true,
          liveRegion: true,
          child: Container(
            key: const Key('restoredBanner'),
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 6, 4),
            decoration: BoxDecoration(
              color: p.tint,
              border: Border.all(color: p.primary, width: 1.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(hardRestoredBanner(n),
                    key: const Key('restoredBannerText'), style: TextStyle(fontSize: 13.5, height: 1.4, color: p.tintInk)),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Wrap(
                  children: [
                    button('restoredTurnOff', kHardRestoredTurnOff, _busy ? null : () => _run(_port.turnOffAll)),
                    button('restoredKeep', kHardRestoredKeep, _busy ? null : () => _run(_port.keepAll)),
                  ],
                )),
              ],
            ),
          ),
        );
      },
    );
  }
}
