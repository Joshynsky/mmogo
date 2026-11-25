/// §AUTOREAD.LEVELS.CATEGORY_PICK_CHIP: one chip of the category chips picker (0.2.2 item 2, slice U-PICK;
/// mock-remembered-v2 pick-multi / pick-one). Chosen = filled + a check mark (not colour only). A dot marks a
/// category used before; screen readers hear "{name}, Used before". The check slot is always reserved, so a
/// chip keeps its width when tapped and no chip moves.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import 'hard_rule_copy.dart';

/// Size of the check mark; its slot is kept even when the chip is not chosen.
const double kPickChipCheckSize = 16;

/// The "used before" dot (8 x 8), shared by the chip and the picker's key line.
class PickUsedDot extends StatelessWidget {
  const PickUsedDot({super.key, required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class CategoryPickChip extends StatelessWidget {
  const CategoryPickChip({
    super.key,
    required this.name,
    required this.chosen,
    required this.usedBefore,
    required this.single,
    required this.dimmed,
    required this.onTap,
  });

  final String name;
  final bool chosen;
  final bool usedBefore;

  /// One choice (radio-like) rather than up to N (checkbox-like).
  final bool single;

  /// Not chosen and the limit is reached: drawn faded; a tap still answers (the picker shows the limit line).
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final fg = chosen ? p.onPrimary : p.ink;
    final chip = Material(
      color: chosen ? p.primary : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: chosen ? p.primary : p.line, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 14, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: kPickChipCheckSize,
                  child: chosen ? Icon(Icons.check, size: kPickChipCheckSize, color: fg) : null,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg, height: 1.2),
                  ),
                ),
                if (usedBefore) ...[const SizedBox(width: 6), PickUsedDot(color: chosen ? p.onPrimary : p.primary)],
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      checked: chosen,
      inMutuallyExclusiveGroup: single,
      label: usedBefore ? '$name, $kHardPickerUsedBefore' : name,
      excludeSemantics: true,
      onTap: onTap,
      child: Opacity(opacity: dimmed ? 0.45 : 1, child: chip),
    );
  }
}
