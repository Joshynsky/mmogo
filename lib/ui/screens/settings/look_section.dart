import 'package:flutter/material.dart';

import '../../../domain/analytics/chart_blocks.dart' show MonthChartStyle, WhereItWentStyle, YearViewAmounts;
import '../../copy/settings_copy.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette_scope.dart';
import '../../widgets/palette_alert_dialog.dart';
import 'appearance_section.dart';
import 'settings_widgets.dart';

/// §SETTINGS.LOOK — the Look card (signed ST1 / mock M9, M9b, M10): Colour
/// palette, Appearance (three icons on the row), First day of the week (a
/// dialog), Month chart shows, Year view amounts, Show withdrawals in the
/// chart, Where it went style, and the note about what is kept in backups.
/// All state and writes are owned by the Settings shell; [tourKey] is its
/// coach-tour anchor.
class LookSection extends StatelessWidget {
  const LookSection({
    super.key,
    required this.palette,
    required this.tourKey,
    required this.appearance,
    required this.onAppearance,
    required this.firstDay,
    required this.onFirstDay,
    required this.monthStyle,
    required this.onMonthStyle,
    required this.yearAmounts,
    required this.onYearAmounts,
    required this.showWithdrawals,
    required this.onShowWithdrawals,
    required this.whereStyle,
    required this.onWhereStyle,
  });

  final AppPalette palette;
  final GlobalKey tourKey;

  /// `system` | `light` | `dark`.
  final String appearance;
  final ValueChanged<String> onAppearance;

  /// 1 (Monday) .. 7 (Sunday); tapping the row opens the dialog.
  final int firstDay;
  final VoidCallback onFirstDay;
  final MonthChartStyle monthStyle;
  final ValueChanged<MonthChartStyle> onMonthStyle;
  final YearViewAmounts yearAmounts;
  final ValueChanged<YearViewAmounts> onYearAmounts;
  final bool showWithdrawals;
  final ValueChanged<bool> onShowWithdrawals;
  final WhereItWentStyle whereStyle;
  final ValueChanged<WhereItWentStyle> onWhereStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionLabel(kSettingsLookGroup, palette: palette),
        SettingsCard(
          palette: palette,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: tourKey,
                child: PaletteGroup(
                  key: const Key('settingsPalette'),
                  currentPaletteId: AppPaletteScope.of(context).value,
                  palette: palette,
                  onSelect: (id) => AppPaletteScope.of(context).select(id),
                ),
              ),
              SettingsHeadRow(
                key: const Key('settingsAppearanceRow'),
                palette: palette,
                icon: Icons.dark_mode_outlined,
                title: kAppearanceTitle,
                subtitle: kAppearanceSubtitle,
                trailing: AppearanceModeControl(palette: palette, value: appearance, onChanged: onAppearance),
              ),
              SettingsLink(
                key: const Key('settingsFirstDayRow'),
                palette: palette,
                icon: Icons.calendar_today_outlined,
                label: kFirstDayTitle,
                subtitle: kFirstDaySubtitle,
                value: kFirstDayNames[firstDay.clamp(1, 7) - 1],
                onTap: onFirstDay,
              ),
              SettingsHelp(
                kFirstDayRegrouped,
                palette: palette,
                bold: true,
                padding: const EdgeInsets.fromLTRB(60, 0, 14, 12),
              ),
              SettingsHeadRow(palette: palette, icon: Icons.calendar_view_month_outlined, title: kMonthChartTitle),
              SettingsSegment<MonthChartStyle>(
                palette: palette,
                label: kMonthChartTitle,
                keyPrefix: 'monthChart',
                options: const [
                  (MonthChartStyle.days, 'days', 'Days'),
                  (MonthChartStyle.weeks, 'weeks', 'Weeks'),
                ],
                value: monthStyle,
                onChanged: onMonthStyle,
              ),
              SettingsHelp(kMonthChartHelp, palette: palette),
              SettingsHeadRow(palette: palette, icon: Icons.bar_chart_outlined, title: kYearViewTitle),
              SettingsSegment<YearViewAmounts>(
                palette: palette,
                label: kYearViewTitle,
                keyPrefix: 'yearView',
                options: const [
                  (YearViewAmounts.quarters, 'quarters', 'Quarter totals'),
                  (YearViewAmounts.months, 'months', 'Monthly amounts'),
                ],
                value: yearAmounts,
                onChanged: onYearAmounts,
              ),
              SettingsHelp(kYearViewHelp, palette: palette),
              SettingsToggle(
                key: const Key('settingsShowWithdrawals'),
                palette: palette,
                icon: Icons.bar_chart_outlined,
                label: kShowWithdrawalsTitle,
                subtitle: kShowWithdrawalsSubtitle,
                value: showWithdrawals,
                onChanged: onShowWithdrawals,
              ),
              SettingsHeadRow(palette: palette, icon: Icons.grid_view_outlined, title: kWhereStyleTitle),
              SettingsSegment<WhereItWentStyle>(
                palette: palette,
                label: kWhereStyleTitle,
                keyPrefix: 'whereStyle',
                options: const [
                  (WhereItWentStyle.button, 'button', 'Button'),
                  (WhereItWentStyle.strip, 'strip', 'Strip'),
                ],
                value: whereStyle,
                onChanged: onWhereStyle,
              ),
              SettingsHelp(kWhereStyleHelp, palette: palette),
              Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Text(
                  kLookNote,
                  key: const Key('settingsLookNote'),
                  style: TextStyle(fontSize: 12, height: 1.4, color: palette.mutedInk),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// System / Light / Dark as three round icon buttons on the row, the chosen
/// one filled (the later signed card of 07-10-2026). One radio group; each
/// button has a 44 x 44 tap area around its 34 px circle.
class AppearanceModeControl extends StatelessWidget {
  const AppearanceModeControl({super.key, required this.palette, required this.value, required this.onChanged});

  final AppPalette palette;
  final String value;
  final ValueChanged<String> onChanged;

  static const modes = <(String, String, IconData)>[
    ('system', 'System', Icons.smartphone_outlined),
    ('light', 'Light', Icons.light_mode_outlined),
    ('dark', 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: kAppearanceTitle,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (id, name, icon) in modes)
              Semantics(
                button: true,
                inMutuallyExclusiveGroup: true,
                selected: id == value,
                label: name,
                excludeSemantics: true,
                child: Tooltip(
                  message: name,
                  child: InkWell(
                    key: Key('appearance-$id'),
                    customBorder: const CircleBorder(),
                    onTap: () => onChanged(id),
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: id == value ? palette.primary : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, size: 18, color: id == value ? palette.onPrimary : palette.mutedInk),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The First day of the week dialog (mock): seven radio options, Monday tagged
/// Default, Cancel. Returns 1..7, or null when it closes without a choice
/// (Cancel, a tap outside, Back).
Future<int?> showFirstDayDialog(BuildContext context, {required int current}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final palette = AppPalette.of(ctx);
      return PaletteAlertDialog(
        key: const Key('firstDayDialog'),
        title: const Text(kFirstDayTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Semantics(
              container: true,
              label: kFirstDayTitle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var d = 1; d <= 7; d++)
                    Semantics(
                      button: true,
                      inMutuallyExclusiveGroup: true,
                      selected: d == current,
                      excludeSemantics: true,
                      label: d == 1 ? '${kFirstDayNames[0]}, $kFirstDayDefaultTag' : kFirstDayNames[d - 1],
                      child: InkWell(
                        key: Key('firstDay-$d'),
                        onTap: () => Navigator.of(ctx).pop(d),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: Row(
                            children: [
                              Icon(
                                d == current ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                size: 20,
                                color: d == current ? palette.primary : palette.mutedInk,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  kFirstDayNames[d - 1],
                                  style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: palette.ink),
                                ),
                              ),
                              if (d == 1)
                                Text(
                                  kFirstDayDefaultTag,
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.mutedInk),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('firstDayCancel'),
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700, color: palette.primary)),
          ),
        ],
      );
    },
  );
}
