import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ANALYTICS.PARTS — the Analytics empty-state text and round icon button.
class AnalyticsEmpty extends StatelessWidget {
  const AnalyticsEmpty({super.key, required this.palette, required this.text});

  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
    child: Text(
      text,
      key: const Key('analyticsEmpty'),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.5, color: palette.mutedInk),
    ),
  );
}

class AnalyticsRoundButton extends StatelessWidget {
  const AnalyticsRoundButton({
    super.key,
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final double iconSize;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
