import 'package:flutter/material.dart';

import '../../../domain/analytics/chart_blocks.dart' show MonthChartStyle, WhereItWentStyle, YearViewAmounts;
import '../../copy/settings_copy.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_palette_scope.dart';
import 'appearance_section.dart';
import 'compact_choice_row.dart';
import 'first_day.dart';
import 'settings_widgets.dart';

// The First day dialog moved to first_day.dart (F4); callers of this file still find it here.
export 'first_day.dart' show showFirstDayDialog;

/// §SETTINGS.LOOK — the Look card (signed ST1 / mock M9, compacted in 0.1.2 F4
/// from the approved mock `look-compact.html`): Colour palette, Appearance
/// (three icon buttons), First day of the week (title, day, chevron; a
/// dialog), Month chart, Year view, Show withdrawals in the chart, Where it
/// went style, and the note about what is kept in backups. The three two-option
/// settings are one compact row each (compact_choice_row.dart). All state and
/// writes are owned by the Settings shell; [tourKey] is its coach-tour anchor.
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
              CompactSettingRow(
                key: const Key('settingsAppearanceRow'),
                palette: palette,
                icon: Icons.dark_mode_outlined,
                title: kAppearanceTitle,
                line: appearanceCaption(appearance),
                lineKey: const Key('settingsAppearanceCaption'),
                controlWidth: AppearanceModeControl.sideWidth,
                control: (context, stacked) =>
                    AppearanceModeControl(palette: palette, value: appearance, onChanged: onAppearance, stacked: stacked),
              ),
              FirstDayRow(
                key: const Key('settingsFirstDayRow'),
                palette: palette,
                title: kFirstDayTitle,
                dayNames: kFirstDayNames,
                day: kFirstDayNames[firstDay.clamp(1, 7) - 1],
                onTap: onFirstDay,
              ),
              CompactChoiceRow<MonthChartStyle>(
                key: const Key('settingsMonthChartRow'),
                palette: palette,
                icon: Icons.calendar_view_month_outlined,
                title: kMonthChartTitle,
                line: kMonthChartLine,
                keyPrefix: 'monthChart',
                options: const [
                  (MonthChartStyle.days, 'days', 'Days'),
                  (MonthChartStyle.weeks, 'weeks', 'Weeks'),
                ],
                value: monthStyle,
                onChanged: onMonthStyle,
              ),
              CompactChoiceRow<YearViewAmounts>(
                key: const Key('settingsYearViewRow'),
                palette: palette,
                icon: Icons.bar_chart_outlined,
                title: kYearViewTitle,
                line: kYearViewLine,
                keyPrefix: 'yearView',
                options: const [
                  (YearViewAmounts.quarters, 'quarters', 'Quarter'),
                  (YearViewAmounts.months, 'months', 'Monthly'),
                ],
                value: yearAmounts,
                onChanged: onYearAmounts,
              ),
              SettingsToggle(
                key: const Key('settingsShowWithdrawals'),
                palette: palette,
                icon: Icons.bar_chart_outlined,
                label: kShowWithdrawalsTitle,
                subtitle: kShowWithdrawalsSubtitle,
                value: showWithdrawals,
                onChanged: onShowWithdrawals,
              ),
              CompactChoiceRow<WhereItWentStyle>(
                key: const Key('settingsWhereStyleRow'),
                palette: palette,
                icon: Icons.grid_view_outlined,
                title: kWhereStyleTitle,
                line: kWhereStyleLine,
                keyPrefix: 'whereStyle',
                options: const [
                  (WhereItWentStyle.button, 'button', 'Button'),
                  (WhereItWentStyle.strip, 'strip', 'Strip'),
                ],
                value: whereStyle,
                onChanged: onWhereStyle,
              ),
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

/// System / Light / Dark as three icon buttons, the chosen one filled (the
/// later signed card of 07-10-2026, 44 x 44 each in the compact mock). One
/// radio group with the spoken names System, Light, Dark and a selected state.
/// [stacked] is the narrow fallback: the control fills its own line and each
/// icon carries a small text label.
class AppearanceModeControl extends StatelessWidget {
  const AppearanceModeControl({
    super.key,
    required this.palette,
    required this.value,
    required this.onChanged,
    this.stacked = false,
  });

  final AppPalette palette;
  final String value;
  final ValueChanged<String> onChanged;
  final bool stacked;

  /// Three 44 px buttons, two 2 px gaps and the 2 px track padding: 140.
  static const double sideWidth = 140;

  static const modes = <(String, String, IconData)>[
    ('system', 'System', Icons.smartphone_outlined),
    ('light', 'Light', Icons.light_mode_outlined),
    ('dark', 'Dark', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    Widget button(String id, String name, IconData icon) {
      final on = id == value;
      final fg = on ? palette.onPrimary : palette.mutedInk;
      return Semantics(
        button: true,
        inMutuallyExclusiveGroup: true,
        selected: on,
        label: name,
        excludeSemantics: true,
        child: Tooltip(
          message: name,
          child: InkWell(
            key: Key('appearance-$id'),
            customBorder: stacked ? const StadiumBorder() : const CircleBorder(),
            onTap: () => onChanged(id),
            child: Container(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              padding: stacked ? const EdgeInsets.symmetric(vertical: 4, horizontal: 2) : null,
              decoration: BoxDecoration(
                color: on ? palette.primary : Colors.transparent,
                shape: stacked ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: stacked ? BorderRadius.circular(999) : null,
              ),
              child: stacked
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: fg),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          maxLines: 1,
                          style: TextStyle(fontSize: 11, fontWeight: on ? FontWeight.w800 : FontWeight.w700, color: fg),
                        ),
                      ],
                    )
                  : Center(child: Icon(icon, size: 18, color: fg)),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: kAppearanceTitle,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: stacked ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final (i, (id, name, icon)) in modes.indexed) ...[
              if (i > 0) const SizedBox(width: 2),
              if (stacked) Expanded(child: button(id, name, icon)) else button(id, name, icon),
            ],
          ],
        ),
      ),
    );
  }
}
