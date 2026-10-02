import 'package:flutter/material.dart';

import '../../copy/privacy_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// Settings "Privacy and security" group (B32): one row, "Privacy and your
/// data", opening the static Privacy page.
class PrivacySection extends StatelessWidget {
  const PrivacySection({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSettingsPrivacyGroup, palette: palette),
        SettingsCard(
          palette: palette,
          child: SettingsLink(
            palette: palette,
            icon: Icons.shield_outlined,
            label: kPrivacyTitle,
            subtitle: kSettingsPrivacySubtitle,
            first: true,
            onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
          ),
        ),
      ],
    );
  }
}
