import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'settings_widgets.dart';

/// §SETTINGS.COMPACT — the compact rows of the Settings Look group (0.1.2 F4,
/// finding R17, approved mock `look-compact.html`): an icon, a title and one
/// short line on the left, a small control on the right. When the card is too
/// narrow for the current text size the control takes its own full-width line
/// under the title (the icon stays beside the title). The decision is made on
/// REAL measured text, not on fixed widths alone.
///
/// Parts: [CompactSettingRow] (the layout and the fallback), [CompactChoiceRow]
/// (two text options: Days / Weeks, Quarter / Monthly, Button / Strip),
/// [compactStacks] (the rule, a pure function the tests and the report use).
/// The First day row, which follows the same rule, is in first_day.dart.

/// Page padding of a row (14 each side), the icon (34) and the two gaps (12
/// each): the fixed part of a row, as in the mock (86).
const double kCompactFixedWidth = 28 + 34 + 24;

/// The narrowest the title column may get before the control drops: 72 at text
/// size 1.0, scaled with the text (the mock's rule).
const double kCompactTitleMin = 72;

/// A little slack against rounding (the mock's "about 4 px of safety").
const double kCompactSafety = 4;

/// The three two-option rows set the control width by the widest pair, so the
/// controls line up in one column (mock round 2).
const kCompactWidestLabels = ['Quarter', 'Monthly'];

/// The rule: does a row with a control of [controlWidth] drop the control under
/// the title, for a card [cardWidth] wide at text factor [textFactor] (1.0,
/// 1.3, 1.6)? Pure, so it can be tabulated.
bool compactStacks({required double cardWidth, required double textFactor, required double controlWidth}) =>
    cardWidth < kCompactFixedWidth + kCompactTitleMin * textFactor + controlWidth + kCompactSafety;

/// How much the current text scale enlarges text (1.0 = normal).
double compactTextFactor(BuildContext context) => MediaQuery.textScalerOf(context).scale(100) / 100;

double compactMeasure(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

const _optionStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w800);

/// The width of a two-option text control for [labels] at the current text
/// scale: each option as wide as the widest label of the group plus 16, never
/// below the mock's minimum (8.8 em + 38). Equal for all three rows because the
/// widest pair is always included.
double compactChoiceWidth(BuildContext context, List<String> labels) {
  var widest = 0.0;
  for (final l in {...kCompactWidestLabels, ...labels}) {
    final w = compactMeasure(context, l, _optionStyle);
    if (w > widest) widest = w;
  }
  final option = widest + 16 < 44 ? 44.0 : widest + 16;
  final em = MediaQuery.textScalerOf(context).scale(13);
  final floor = 8.8 * em + 38;
  final measured = option * 2 + 6;
  return measured > floor ? measured : floor;
}

/// The icon tile, the title and the one short line, and the control. [control]
/// is built for the side-by-side layout (`stacked` false) or the fallback.
class CompactSettingRow extends StatelessWidget {
  const CompactSettingRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.line,
    required this.controlWidth,
    required this.control,
    this.lineKey,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String line;
  final Key? lineKey;

  /// The width of the control when it sits beside the title.
  final double controlWidth;
  final Widget Function(BuildContext context, bool stacked) control;

  @override
  Widget build(BuildContext context) {
    final factor = compactTextFactor(context);
    return LayoutBuilder(
      builder: (context, box) {
        final stacked = compactStacks(cardWidth: box.maxWidth, textFactor: factor, controlWidth: controlWidth);
        final text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: palette.ink)),
            const SizedBox(height: 2),
            Text(line, key: lineKey, style: TextStyle(fontSize: 12, height: 1.35, color: palette.mutedInk)),
          ],
        );
        return Container(
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.line))),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: stacked
              ? Column(
                  key: const Key('compactStacked'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SettingsRowIcon(icon: icon, palette: palette),
                        const SizedBox(width: 12),
                        Expanded(child: text),
                      ],
                    ),
                    const SizedBox(height: 8),
                    control(context, true),
                  ],
                )
              : Row(
                  key: const Key('compactBeside'),
                  children: [
                    SettingsRowIcon(icon: icon, palette: palette),
                    const SizedBox(width: 12),
                    Expanded(child: text),
                    const SizedBox(width: 12),
                    SizedBox(width: controlWidth, child: control(context, false)),
                  ],
                ),
        );
      },
    );
  }
}

/// A row with two TEXT options on the right (Days / Weeks, Quarter / Monthly,
/// Button / Strip). One radio group; each option at least 44 x 44; the chosen
/// option is filled with the primary colour AND set in heavier type, so it
/// reads without colour. Option keys are `<keyPrefix>-<option name>`.
class CompactChoiceRow<T> extends StatelessWidget {
  const CompactChoiceRow({
    super.key,
    required this.palette,
    required this.icon,
    required this.title,
    required this.line,
    required this.keyPrefix,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final AppPalette palette;
  final IconData icon;
  final String title;
  final String line;
  final String keyPrefix;
  final List<(T value, String name, String text)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return CompactSettingRow(
      palette: palette,
      icon: icon,
      title: title,
      line: line,
      controlWidth: compactChoiceWidth(context, [for (final o in options) o.$3]),
      control: (context, stacked) => Semantics(
        container: true,
        label: title,
        child: Container(
          key: Key('$keyPrefix-control'),
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: palette.track, borderRadius: BorderRadius.circular(999)),
          child: Row(
            children: [
              for (final (i, (v, name, text)) in options.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                    child: Semantics(
                      button: true,
                      inMutuallyExclusiveGroup: true,
                      selected: v == value,
                      label: text,
                      excludeSemantics: true,
                      child: Material(
                        color: v == value ? palette.primary : Colors.transparent,
                        shape: const StadiumBorder(),
                        child: InkWell(
                          key: Key('$keyPrefix-$name'),
                          customBorder: const StadiumBorder(),
                          onTap: () => onChanged(v),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  text,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: v == value ? FontWeight.w800 : FontWeight.w700,
                                    color: v == value ? palette.onPrimary : palette.mutedInk,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
