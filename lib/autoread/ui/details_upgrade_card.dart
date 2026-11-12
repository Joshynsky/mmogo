/// §AUTOREAD.UI.DETAILS_CARD (0.2.0 row 16, J1 B4): the one-time card for a phone
/// that agreed before "Show details" existed. It shows only while the details key
/// is absent; either button writes the key, which is what ends it. Autoread
/// flavor only.
library;

import 'package:flutter/material.dart';

import '../../ui/screens/settings/settings_widgets.dart';
import '../../ui/theme/app_colors.dart';
import 'consent_details_copy.dart';

class DetailsUpgradeCard extends StatelessWidget {
  const DetailsUpgradeCard({super.key, required this.palette, required this.busy, required this.onChoose});

  final AppPalette palette;
  final bool busy;

  /// true = Show details, false = Keep generic.
  final void Function(bool details) onChoose;

  @override
  Widget build(BuildContext context) {
    const minSize = Size(64, 44);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SettingsCard(
        palette: palette,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(kUpgradeCardTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.ink)),
              const SizedBox(height: 4),
              Text(kUpgradeCardBody, style: TextStyle(fontSize: 13, height: 1.45, color: palette.ink)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    key: const Key('detailsCardYes'),
                    style: FilledButton.styleFrom(minimumSize: minSize),
                    onPressed: busy ? null : () => onChoose(true),
                    child: const Text(kUpgradeCardYes),
                  ),
                  OutlinedButton(
                    key: const Key('detailsCardNo'),
                    style: OutlinedButton.styleFrom(minimumSize: minSize),
                    onPressed: busy ? null : () => onChoose(false),
                    child: const Text(kUpgradeCardNo),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
