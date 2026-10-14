import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/tap_target.dart';

/// Shared small round icon-button (a light-grey circle (#eef1f4)
/// with a dark icon) — used by both
/// [PrimaryScaffold]'s top-right Profile button and [SecondaryScaffold]'s
/// top-left back-arrow, so the one visual language isn't duplicated across
/// two near-identical private widgets.
class IconCircleButton extends StatelessWidget {
  const IconCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 32,
    this.background = AppColors.iconBtnBg,
    this.foreground = AppColors.text,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  /// Circle fill. Defaults to the secondary pages' light grey; the primary
  /// top bar passes the card colour (T20, seamless top bar).
  final Color background;

  /// Icon colour.
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.53, color: foreground),
        ),
      ),
    );
    // TS1: the visible circle keeps its size; the tap target grows to at
    // least 44 x 44 (the outer detector covers the ring around the circle,
    // the InkWell inside keeps the ripple).
    final target = TapTarget(onTap: onTap, child: button);
    return tooltip == null ? target : Tooltip(message: tooltip!, child: target);
  }
}
