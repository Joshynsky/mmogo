import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The two-part period pill: the left half (primary) picks the length, the
/// right half (on the track) picks which one (mock `.bperiod`).
///
/// Built for Analytics (T21); shared with Paid to (T22), which offers only
/// All time / Year / Month. The tap keys default to Analytics' own
/// (`analyticsGranularity` / `analyticsPeriodValue`, used by its tests).
class PeriodPill extends StatelessWidget {
  const PeriodPill({
    super.key,
    required this.palette,
    required this.granKey,
    required this.valueKey,
    required this.granularity,
    required this.value,
    required this.onGranularity,
    required this.onValue,
    this.granularityTapKey = const Key('analyticsGranularity'),
    this.valueTapKey = const Key('analyticsPeriodValue'),
  });

  final AppPalette palette;

  /// Anchors for [showPeriodMenu] (the popup opens under each half).
  final GlobalKey granKey;
  final GlobalKey valueKey;
  final String granularity;
  final String value;
  final VoidCallback onGranularity;
  final VoidCallback? onValue;
  final Key granularityTapKey;
  final Key valueTapKey;

  @override
  Widget build(BuildContext context) {
    const pill = BorderRadius.all(Radius.circular(999));
    final style = TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.3, color: palette.onPrimary);
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: palette.track, borderRadius: pill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: 'Length: $granularity. Pick another',
            excludeSemantics: true,
            child: Material(
              key: granKey,
              color: palette.primary,
              borderRadius: pill,
              child: InkWell(
                key: granularityTapKey,
                borderRadius: pill,
                onTap: onGranularity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(11, 5, 8, 5),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(granularity, style: style),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: palette.onPrimary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Semantics(
            button: onValue != null,
            label: onValue != null ? 'Period: $value. Pick another' : 'Period: $value',
            excludeSemantics: true,
            child: Material(
              key: valueKey,
              color: Colors.transparent,
              borderRadius: pill,
              child: InkWell(
                key: valueTapKey,
                borderRadius: pill,
                onTap: onValue,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
                  child: Text(value, style: style.copyWith(color: palette.ink)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pill's popup (mock `.bpop`): right-aligned 4px under [anchor], one
/// row per item (label, optional muted note, selected = tinted).
Future<T?> showPeriodMenu<T>(
  BuildContext context, {
  required GlobalKey anchor,
  required AppPalette palette,
  required List<(String label, String note, bool selected, T value)> items,
}) {
  final box = anchor.currentContext!.findRenderObject()! as RenderBox;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final w = overlay.size.width;
  final h = overlay.size.height;
  final right = math.max(w - rect.right, 8.0);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(w - right, rect.bottom + 4, right, h - rect.bottom - 4),
    color: palette.card,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shadowColor: const Color(0x66000000),
    menuPadding: const EdgeInsets.all(5),
    constraints: const BoxConstraints(minWidth: 150, maxHeight: 280),
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radius.circular(14)),
      side: BorderSide(color: palette.line),
    ),
    items: [
      for (final (label, note, selected, value) in items)
        PopupMenuItem<T>(
          value: value,
          height: 35,
          padding: EdgeInsets.zero,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: selected ? palette.tint : null,
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: selected ? palette.tintInk : palette.ink,
                    ),
                  ),
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Text(
                    note,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.mutedInk),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );
}
