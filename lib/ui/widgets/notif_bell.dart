import 'package:flutter/material.dart';

import '../../domain/notifications/news_logic.dart' show capCount;
import '../theme/app_colors.dart';
import 'notif_colors.dart';
import 'notif_shape_icon.dart';

/// The bell icon button with up to four shape badges (signed mock `bell.html`,
/// variant D): arrow bottom right (update), star top left (new notice), number
/// pill top right ([pillCount]) and a clean diamond bottom left with its number
/// OUTSIDE it, to its left ([diamondCount]).
///
/// One control for the screen reader: the semantics label is exactly
/// [spokenLabel] and the badges add nothing. The tap area is at least 44 px.
/// The left margin grows with the diamond number's width so the number clears
/// the page title.
class NotifBell extends StatelessWidget {
  const NotifBell({
    super.key,
    required this.onTap,
    required this.spokenLabel,
    this.arrow = false,
    this.star = false,
    this.pillCount,
    this.diamondCount,
  });

  final VoidCallback onTap;
  final String spokenLabel;
  final bool arrow;
  final bool star;

  /// Number in the top-right pill; null or below 1 hides the pill.
  final int? pillCount;

  /// Number beside the bottom-left diamond; null or below 1 hides both.
  final int? diamondCount;

  /// Badges stop growing at this text scale so corners never collide.
  static const double maxBadgeScale = 1.15;

  /// Left margin for a diamond number of 0 to 3 characters.
  static const List<double> leftMargins = [0, 18, 24, 30];

  static bool _show(int? n) => n != null && n >= 1;

  /// The left margin (before text scale) for [diamondCount].
  static double marginFor(int? diamondCount) =>
      _show(diamondCount) ? leftMargins[capCount(diamondCount!).length] : 0;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final m = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, maxBadgeScale).toDouble();
    final showPill = _show(pillCount);
    final showDiamond = _show(diamondCount);

    final badges = <Widget>[
      if (star)
        Positioned(
          top: -5 * m,
          left: -9,
          child: NotifShapeIcon(
            shape: NotifShape.star,
            color: notifShapeColor(palette, NotifShape.star),
            ink: notifShapeInk(palette, NotifShape.star),
            size: 16,
          ),
        ),
      if (showPill)
        Positioned(
          top: -5 * m,
          right: -5,
          child: NotifShapeIcon(
            shape: NotifShape.pill,
            color: notifShapeColor(palette, NotifShape.pill),
            ink: notifShapeInk(palette, NotifShape.pill),
            label: capCount(pillCount!),
            size: 18,
          ),
        ),
      if (arrow)
        Positioned(
          bottom: -5 * m,
          right: -5,
          child: NotifShapeIcon(
            shape: NotifShape.arrow,
            color: notifShapeColor(palette, NotifShape.arrow),
            ink: notifShapeInk(palette, NotifShape.arrow),
            size: 16,
          ),
        ),
      if (showDiamond)
        Positioned(
          bottom: -4 * m,
          right: 44 - 7 * m,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                capCount(diamondCount!),
                key: const ValueKey('bell-diamond-number'),
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: notifShapeColor(palette, NotifShape.diamond),
                  fontSize: 10 * m,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              SizedBox(width: 1 * m),
              KeyedSubtree(
                key: const ValueKey('bell-diamond'),
                child: NotifShapeIcon(
                  shape: NotifShape.diamond,
                  color: notifShapeColor(palette, NotifShape.diamond),
                  size: 17,
                ),
              ),
            ],
          ),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(left: marginFor(diamondCount) * m),
      child: Semantics(
        container: true,
        button: true,
        label: spokenLabel,
        excludeSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Material(
            type: MaterialType.transparency,
            child: InkResponse(
              key: const ValueKey('bell-button'),
              onTap: onTap,
              radius: 22,
              containedInkWell: false,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      key: const ValueKey('bell-circle'),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: palette.surface, shape: BoxShape.circle),
                      child: Icon(Icons.notifications_outlined, size: 22, color: palette.ink),
                    ),
                    ...badges,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
