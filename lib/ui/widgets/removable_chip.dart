import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// §WIDGET.REMOVABLE_CHIP — an active filter (mock `.bfchip`): label + ✕; a
/// tap removes it. [inkKey] goes on the `InkWell` (Analytics' T26 chips);
/// [key] goes on the widget (Paid to's chips).
class RemovableChip extends StatelessWidget {
  const RemovableChip({
    super.key,
    this.inkKey,
    required this.palette,
    required this.label,
    required this.semanticsLabel,
    required this.onTap,
  });

  final Key? inkKey;
  final AppPalette palette;
  final String label;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const pill = BorderRadius.all(Radius.circular(999));
    return Semantics(
      button: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Material(
        color: palette.primary,
        borderRadius: pill,
        child: InkWell(
          key: inkKey,
          borderRadius: pill,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.onPrimary),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.close_rounded, size: 13, color: palette.onPrimary.withValues(alpha: 0.85)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
