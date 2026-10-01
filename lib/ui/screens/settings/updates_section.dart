import 'package:flutter/material.dart';

import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// Settings "Updates and feedback" group (B48). Only rows whose destination
/// exists today: "Updates" opens the notifications/updates page. Send
/// feedback, the update switch and Check now arrive with B28/B27/B33.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key, required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel('Updates and feedback', palette: palette),
        SettingsCard(
          palette: palette,
          child: SettingsLink(
            palette: palette,
            icon: Icons.notifications_none_rounded,
            label: 'Updates',
            subtitle: 'News about new versions of mmogo',
            first: true,
            onTap: () => Navigator.of(context).pushNamed(Routes.notifications),
          ),
        ),
      ],
    );
  }
}
