import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// §WIDGET.CARD — the shared card surface (radius 18, `palette.card`, faint
/// `palette.deep` α 0.06 shadow on light only).
///
/// Scope: currently used by the Analytics and Paid to cards only. Other
/// screens (Settings, Profile, Manage classifications, Recently deleted and
/// the Home summary card) still draw their own card decoration and may
/// migrate to this widget later.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.palette,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.clip = false,
  });

  final AppPalette palette;
  final Widget child;
  final EdgeInsets padding;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }
}
