/// §AUTOREAD.LEVELS.DETAILS_OFF_CARD: what the Remembered page's second tab shows while "Record receiver
/// details" is off (0.2.2 item 2 redesign, signed 25-11 "Details-off card"): ONE card with the signed
/// line and "Turn it on in Settings". The button opens Settings with the "Record receiver details" switch
/// outlined (B-7: HighlightRequest(kSettingsTargetCaptureReceiver), the same link What's new and the
/// Paid to explainer use). The caller refreshes when Settings is closed (B-8).
library;

import 'package:flutter/material.dart';

import '../../../ui/screens/settings/settings_targets.dart' show kSettingsTargetCaptureReceiver;
import '../../../ui/shell/routes.dart' show Routes;
import '../../../ui/theme/app_colors.dart';
import '../../../ui/widgets/highlight_pulse.dart' show HighlightRequest;
import '../../../ui/widgets/tap_target.dart' show kMinTapTarget;
import 'hard_rule_copy.dart';

/// Opens Settings at the "Record receiver details" switch (B-7). Completes when Settings is closed.
Future<void> openSettingsAtCaptureReceiver(BuildContext context) async {
  HighlightRequest.set(kSettingsTargetCaptureReceiver);
  await Navigator.of(context).pushNamed(Routes.settings);
}

class LevelsDetailsOffCard extends StatelessWidget {
  const LevelsDetailsOffCard({super.key, required this.onOpenSettings});

  /// "Turn it on in Settings".
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: const Key('levelsDetailsOff'),
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 8, 6),
      decoration: BoxDecoration(color: p.tint, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: Text(kHardDetailsOffCard, style: TextStyle(fontSize: 14, height: 1.45, color: p.tintInk)),
        ),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const Key('levelsOpenSettings'),
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              foregroundColor: p.primary,
            ),
            onPressed: onOpenSettings,
            child: Text(kHardTurnOnInSettings, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}
