import 'package:flutter/material.dart';

import '../../../domain/analytics/analytics_period.dart';
import '../../theme/app_colors.dart';

/// §ANALYTICS.SHEET_PARTS — the shared sheet action row, field styling and picker theme.
/// Cancel (track) + primary action, 42px pills (mock `.acts`).
class AnalyticsSheetActions extends StatelessWidget {
  const AnalyticsSheetActions({
    super.key,
    required this.palette,
    required this.cancelKey,
    required this.primaryKey,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final AppPalette palette;
  final Key cancelKey;
  final Key primaryKey;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    Widget button(Key key, String label, Color bg, Color fg, VoidCallback? onTap) => Expanded(
      child: SizedBox(
        height: 42,
        child: FilledButton(
          key: key,
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: 0.5),
            disabledForegroundColor: fg.withValues(alpha: 0.7),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      ),
    );
    return Row(
      children: [
        button(cancelKey, 'Cancel', palette.track, palette.ink, () => Navigator.of(context).pop()),
        const SizedBox(width: 8),
        button(primaryKey, primaryLabel, palette.primary, palette.onPrimary, onPrimary),
      ],
    );
  }
}

String analyticsFmtFieldDate(DateTime d) => '${d.day} ${monthShort(d)} ${d.year}';

/// A mock-styled input box (`.sheet input`): mist fill, 1.5px line border,
/// radius 10.
BoxDecoration analyticsFieldBox(AppPalette p) => BoxDecoration(
  color: p.background,
  border: Border.all(color: p.line, width: 1.5),
  borderRadius: const BorderRadius.all(Radius.circular(10)),
);

Text analyticsFieldLabel(AppPalette p, String text) => Text(
  text,
  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: p.mutedInk),
);

/// F4: the (firstDate, lastDate) a Custom-sheet date picker offers. From:
/// [firstDate] .. today. To: the chosen From .. today.
(DateTime, DateTime) customRangePickerBounds({
  required DateTime from,
  required DateTime today,
  required DateTime firstDate,
  required bool pickingFrom,
}) => pickingFrom ? (firstDate, today) : (from.isAfter(today) ? today : from, today);

/// F3: the Theme for pickers and sub-sheets opened from Analytics — the
/// page's Ocean & Sun palette (light or dark), never the app's old green.
ThemeData analyticsPickerTheme(AppPalette p) {
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: p.onPrimary,
    secondary: p.primary,
    onSecondary: p.onPrimary,
    surface: p.card,
    onSurface: p.ink,
    onSurfaceVariant: p.mutedInk,
    outline: p.line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    colorScheme: scheme,
    fontFamily: 'Roboto',
    datePickerTheme: DatePickerThemeData(
      backgroundColor: p.card,
      surfaceTintColor: Colors.transparent,
      headerForegroundColor: p.ink,
    ),
    timePickerTheme: TimePickerThemeData(backgroundColor: p.card),
    textSelectionTheme: TextSelectionThemeData(cursorColor: p.primary, selectionHandleColor: p.primary),
  );
}
