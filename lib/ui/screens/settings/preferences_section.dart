import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// Settings "Preferences" section: the auto-recognize switch and "Show tips
/// again". State and handlers are owned by the Settings shell; [tourKey] is
/// its coach-tour anchor.
class PreferencesSection extends StatelessWidget {
  const PreferencesSection({
    super.key,
    required this.palette,
    required this.tourKey,
    required this.autoRecognize,
    required this.onAutoRecognizeChanged,
    required this.onShowTipsAgain,
  });

  final AppPalette palette;
  final GlobalKey tourKey;
  final bool autoRecognize;
  final ValueChanged<bool>? onAutoRecognizeChanged;
  final VoidCallback onShowTipsAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel('Preferences', palette: palette),
        KeyedSubtree(
          key: tourKey,
          child: SettingsCard(
            palette: palette,
            child: Column(
              children: [
                SettingsToggle(
                  palette: palette,
                  icon: Icons.auto_awesome_outlined,
                  label: 'Auto-recognize classifications',
                  subtitle: 'Suggest a classification for repeat senders and receivers while you add',
                  first: true,
                  value: autoRecognize,
                  onChanged: onAutoRecognizeChanged,
                ),
                SettingsLink(
                  palette: palette,
                  icon: Icons.lightbulb_outline,
                  label: 'Show tips again',
                  subtitle: 'Replay the guide on every page',
                  onTap: onShowTipsAgain,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
