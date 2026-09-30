import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

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
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
