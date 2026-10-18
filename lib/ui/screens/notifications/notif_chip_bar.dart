import 'package:flutter/material.dart';

import '../../../domain/notifications/news_logic.dart' show capCount;
import '../../../domain/notifications/notif_chip.dart';
import '../../theme/app_colors.dart';

/// One chip of the Notifications chip bar. The caller injects the visible
/// [label] and the [spokenName] (this file carries no auto-read words).
class NotifChipSpec {
  const NotifChipSpec({
    required this.chip,
    required this.label,
    required this.spokenName,
    required this.count,
  });

  final NotifChip chip;
  final String label;
  final String spokenName;
  final int count;
}

/// The one-row chip bar of the Notifications page: never wraps, never
/// scrolls. Above 115 % text the count moves under the label inside the same
/// chip. Renders nothing for one chip or fewer.
class NotifChipBar extends StatelessWidget {
  const NotifChipBar({
    super.key,
    required this.chips,
    required this.selected,
    required this.onSelected,
  });

  final List<NotifChipSpec> chips;
  final NotifChip selected;
  final ValueChanged<NotifChip> onSelected;

  /// Text scale above which the count sits under the label.
  static const stackedAbove = 1.15;
  static const minChipHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    if (chips.length <= 1) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final stacked =
        MediaQuery.textScalerOf(context).scale(10) / 10 > stackedAbove;
    // Align (heightFactor 1) so a tight parent height cannot stretch the row.
    return Align(
      heightFactor: 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              // Wider labels get more room; the FittedBox in the chip is a safety net.
              Expanded(
                flex: chips[i].label.length + 3,
                child: _Chip(
                  key: Key('notif-chip-${chips[i].chip.name}'),
                  spec: chips[i],
                  selected: chips[i].chip == selected,
                  stacked: stacked,
                  palette: palette,
                  onTap: () => onSelected(chips[i].chip),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.spec,
    required this.selected,
    required this.stacked,
    required this.palette,
    required this.onTap,
  });

  final NotifChipSpec spec;
  final bool selected;
  final bool stacked;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zero = spec.count == 0;
    final fg = selected
        ? palette.onPrimary
        : (zero ? palette.mutedInk : palette.ink);
    final fill = selected ? palette.primary : palette.card;
    final border = selected ? palette.primary : palette.line;
    final weight = selected ? FontWeight.w800 : FontWeight.w600;
    final label = Text(
      spec.label,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 13,
        height: 1.15,
        fontWeight: weight,
        color: fg,
        // A cue that does not rely on colour.
        decoration: selected ? TextDecoration.underline : TextDecoration.none,
        decorationColor: fg,
        decorationThickness: 2,
      ),
    );
    final count = Text(
      capCount(spec.count),
      key: Key('notif-chip-count-${spec.chip.name}'),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: 12,
        height: 1.15,
        fontWeight: weight,
        color: fg,
      ),
    );
    final content = stacked
        ? Column(mainAxisSize: MainAxisSize.min, children: [label, count])
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [label, const SizedBox(width: 4), count],
          );

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '${spec.spokenName}, ${capCount(spec.count)}',
      onTap: onTap,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: zero && !selected ? 0.7 : 1,
          child: CustomPaint(
            foregroundPainter: _ChipBorder(color: border, dashed: zero),
            child: Material(
              color: fill,
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              child: InkWell(
                borderRadius: const BorderRadius.all(Radius.circular(22)),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: NotifChipBar.minChipHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Center(
                      child: FittedBox(fit: BoxFit.scaleDown, child: content),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid or dashed rounded outline (dashed = zero count).
class _ChipBorder extends CustomPainter {
  const _ChipBorder({required this.color, required this.dashed});

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)),
      );
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_ChipBorder old) =>
      old.color != color || old.dashed != dashed;
}
