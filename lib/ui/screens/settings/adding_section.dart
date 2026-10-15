import 'package:flutter/material.dart';

import '../../copy/settings_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// Settings ADDING ENTRIES card (0.1.2 S9a, mock M9): the Auto-recognize
/// switch, Manage categories (was "Manage classifications") and Remembered
/// recipients. State and handlers are owned by the Settings shell; [tourKey]
/// is its coach-tour anchor.
class AddingSection extends StatelessWidget {
  const AddingSection({
    super.key,
    required this.palette,
    required this.tourKey,
    required this.autoRecognize,
    required this.onAutoRecognizeChanged,
  });

  final AppPalette palette;
  final GlobalKey tourKey;
  final bool autoRecognize;
  final ValueChanged<bool>? onAutoRecognizeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSettingsAddingGroup, palette: palette),
        KeyedSubtree(
          key: tourKey,
          child: SettingsCard(
            palette: palette,
            child: Column(
              children: [
                SettingsToggle(
                  key: const Key('settingsAutoRecognize'),
                  palette: palette,
                  icon: Icons.auto_awesome_outlined,
                  label: kAutoRecognizeLabel,
                  subtitle: kAutoRecognizeSubtitle,
                  first: true,
                  value: autoRecognize,
                  onChanged: onAutoRecognizeChanged,
                ),
                SettingsLink(
                  key: const Key('settingsManageCategories'),
                  palette: palette,
                  icon: Icons.category_outlined,
                  label: kManageCategoriesLabel,
                  subtitle: kManageCategoriesSubtitle,
                  onTap: () => Navigator.of(context).pushNamed(Routes.manageClassifications),
                ),
                SettingsLink(
                  key: const Key('settingsRemembered'),
                  palette: palette,
                  icon: Icons.people_outline,
                  label: kRememberedRowLabel,
                  subtitle: kRememberedRowSubtitle,
                  onTap: () => Navigator.of(context).pushNamed(Routes.rememberedRecipients),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
