import 'package:flutter/material.dart';

import '../../copy/settings_copy.dart';
import '../../theme/app_colors.dart';
import '../../widgets/palette_alert_dialog.dart';
import 'compact_choice_row.dart';
import 'settings_widgets.dart';

/// §SETTINGS.FIRST_DAY — the First day of the week row (title, current day,
/// chevron; 0.1.2 F4 from the approved mock `look-compact.html`) and its dialog
/// (seven days, the one-line regrouped note, Cancel). The row follows the
/// compact fallback rule of compact_choice_row.dart: when it is narrow the day
/// moves under the title.

/// First day of the week: icon, title, the current day and a chevron. When the
/// row is narrow the day moves under the title instead of squeezing it. The
/// limit uses the widest day name, so choosing another day never flips the
/// layout. The row is one button that opens the day dialog.
class FirstDayRow extends StatelessWidget {
  const FirstDayRow({
    super.key,
    required this.palette,
    required this.title,
    required this.dayNames,
    required this.day,
    required this.onTap,
  });

  final AppPalette palette;
  final String title;
  final List<String> dayNames;

  /// The current day name (Monday ... Sunday).
  final String day;
  final VoidCallback onTap;

  static const _valueStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

  /// The narrowest card that keeps the day beside the title (pure, for tables):
  /// the fixed part, the chevron (18) and its gap (12), the title column
  /// minimum, the day and a gap (12 is inside the fixed part for the icon only).
  static double sideLimit({required double textFactor, required double valueWidth}) =>
      kCompactFixedWidth + 12 + 18 + kCompactTitleMin * textFactor + valueWidth + kCompactSafety;

  @override
  Widget build(BuildContext context) {
    final factor = compactTextFactor(context);
    var widest = 0.0;
    for (final n in dayNames) {
      final w = compactMeasure(context, n, _valueStyle);
      if (w > widest) widest = w;
    }
    return LayoutBuilder(
      builder: (context, box) {
        final stacked = box.maxWidth < sideLimit(textFactor: factor, valueWidth: widest);
        final titleText = Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink));
        final value = Text(
          day,
          key: const Key('settingsRowValue'),
          style: _valueStyle.copyWith(color: palette.mutedInk),
        );
        return Semantics(
          button: true,
          container: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                child: Row(
                  children: [
                    SettingsRowIcon(icon: Icons.calendar_today_outlined, palette: palette),
                    const SizedBox(width: 12),
                    Expanded(
                      child: stacked
                          ? Column(
                              key: const Key('firstDayStacked'),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [titleText, const SizedBox(height: 2), value],
                            )
                          : titleText,
                    ),
                    if (!stacked) ...[const SizedBox(width: 12), value],
                    const SizedBox(width: 12),
                    Icon(Icons.chevron_right, size: 18, color: palette.mutedInk),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The First day of the week dialog: seven radio options, Monday tagged
/// Default, then the one-line note that past weeks are regrouped (shown here
/// only, in light weight), and Cancel. Tight (R21): no empty band between the
/// last day and Cancel; the list scrolls only when the screen is too short;
/// Cancel stays visible. Returns 1..7, or null when it closes without a choice
/// (Cancel, a tap outside, Back).
Future<int?> showFirstDayDialog(BuildContext context, {required int current}) {
  return showDialog<int>(
    context: context,
    builder: (ctx) {
      final palette = AppPalette.of(ctx);
      return PaletteAlertDialog(
        key: const Key('firstDayDialog'),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        title: const Text(kFirstDayTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Semantics(
              container: true,
              label: kFirstDayTitle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                          constraints: const BoxConstraints(minHeight: 44),
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
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 2),
                    child: Text(
                      kFirstDayRegrouped,
                      key: const Key('firstDayRegrouped'),
                      style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w400, color: palette.mutedInk),
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
