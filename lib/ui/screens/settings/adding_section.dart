import 'package:flutter/material.dart';

import '../../copy/settings_copy.dart';
import '../../shell/routes.dart';
import '../../theme/app_colors.dart';
import '../fuliza/fuliza_visible.dart';
import 'remembered_hook_row.dart';
import 'settings_widgets.dart';

/// Settings ADDING ENTRIES card (0.1.2 S9a, mock M9): the Auto-recognize
/// switch, the Record receiver details switch (the Add screen's remembered tick), Manage categories (was "Manage classifications") and Remembered
/// recipients. State and handlers are owned by the Settings shell; [tourKey]
/// is its coach-tour anchor.
class AddingSection extends StatelessWidget {
  const AddingSection({
    super.key,
    required this.palette,
    required this.tourKey,
    required this.autoRecognize,
    required this.onAutoRecognizeChanged,
    required this.captureReceiver,
    required this.onCaptureReceiverChanged,
    this.showFuliza = true,
    this.onShowFulizaChanged,
    this.rememberedHook,
  });

  /// Null keeps the Remembered recipients row as it is; set, the one
  /// "Remembered: recipients and auto-record" row replaces it.
  final RememberedRowHook? rememberedHook;

  final AppPalette palette;
  final GlobalKey tourKey;
  final bool autoRecognize;
  final ValueChanged<bool>? onAutoRecognizeChanged;
  final bool captureReceiver;
  final ValueChanged<bool>? onCaptureReceiverChanged;

  /// Fuliza kill-switch (S12 slice C).
  final bool showFuliza;
  final ValueChanged<bool>? onShowFulizaChanged;

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
                SettingsToggle(
                  key: const Key('settingsCaptureReceiver'),
                  palette: palette,
                  icon: Icons.person_outline,
                  label: kCaptureReceiverLabel,
                  subtitle: kCaptureReceiverSubtitle,
                  value: captureReceiver,
                  onChanged: onCaptureReceiverChanged,
                ),
                if (fulizaVisible)
                  SettingsToggle(
                    key: const Key('settingsShowFuliza'),
                    palette: palette,
                    icon: Icons.account_balance_wallet_outlined,
                    label: kShowFulizaLabel,
                    subtitle: kShowFulizaSubtitle,
                    value: showFuliza,
                    onChanged: onShowFulizaChanged,
                  ),
                SettingsLink(
                  key: const Key('settingsManageCategories'),
                  palette: palette,
                  icon: Icons.category_outlined,
                  label: kManageCategoriesLabel,
                  subtitle: kManageCategoriesSubtitle,
                  onTap: () => Navigator.of(context).pushNamed(Routes.manageClassifications),
                ),
                if (rememberedHook != null)
                  RememberedHookRow(key: const Key('settingsRemembered'), palette: palette, hook: rememberedHook!)
                else
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
