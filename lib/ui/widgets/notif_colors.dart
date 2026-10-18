import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'notif_shape_icon.dart';

/// Colours for [NotifShapeIcon], per palette and brightness.
///
/// Update uses the palette's primary and the diamonds use its deep colour (both
/// existing tokens). The pill and new-notice colours are not palette tokens yet,
/// so they are the signed mock's BADGE values, kept here as named constants
/// ([NotifBadgeColors]). Ink on a fill is white in light and near-black in dark.

/// The two colours the palettes do not carry, for one palette in one brightness.
@immutable
class NotifBadgeColors {
  const NotifBadgeColors({required this.pill, required this.notice});

  /// Number pill fill (warm accent family).
  final Color pill;

  /// Star fill (a third hue of the palette family).
  final Color notice;
}

// Signed mock values (bell.html BADGE table), light and dark per palette.
const NotifBadgeColors kNotifOceanLight = NotifBadgeColors(pill: Color(0xFF9A5B00), notice: Color(0xFF5B4FC4));
const NotifBadgeColors kNotifOceanDark = NotifBadgeColors(pill: Color(0xFFF2B33D), notice: Color(0xFF8479E8));
const NotifBadgeColors kNotifLeafLight = NotifBadgeColors(pill: Color(0xFF8A6400), notice: Color(0xFF1F6F8B));
const NotifBadgeColors kNotifLeafDark = NotifBadgeColors(pill: Color(0xFFE8B923), notice: Color(0xFF5FB8D6));
const NotifBadgeColors kNotifIndigoLight = NotifBadgeColors(pill: Color(0xFFB5502A), notice: Color(0xFF0F766E));
const NotifBadgeColors kNotifIndigoDark = NotifBadgeColors(pill: Color(0xFFFFAB84), notice: Color(0xFF4FD1C5));

/// Badge ink in light and dark (mock INK_L, INK_D).
const Color kNotifInkLight = Color(0xFFFFFFFF);
const Color kNotifInkDark = Color(0xFF0A1114);

/// The extra colours for [p]. An unknown palette falls back to Ocean.
NotifBadgeColors notifBadgeColors(AppPalette p) {
  final dark = p.brightness == Brightness.dark;
  if (identical(p, AppPalette.leafLight) || identical(p, AppPalette.leafDark)) {
    return dark ? kNotifLeafDark : kNotifLeafLight;
  }
  if (identical(p, AppPalette.indigoLight) || identical(p, AppPalette.indigoDark)) {
    return dark ? kNotifIndigoDark : kNotifIndigoLight;
  }
  return dark ? kNotifOceanDark : kNotifOceanLight;
}

/// Fill colour for [shape] in palette [p].
Color notifShapeColor(AppPalette p, NotifShape shape) {
  switch (shape) {
    case NotifShape.arrow:
      return p.primary;
    case NotifShape.star:
      return notifBadgeColors(p).notice;
    case NotifShape.pill:
      return notifBadgeColors(p).pill;
    case NotifShape.diamond:
    case NotifShape.diamondDot:
      return p.deep;
  }
}

/// Glyph colour on the fill (arrow, star, number, dot) for [shape] in [p].
Color notifShapeInk(AppPalette p, NotifShape shape) {
  switch (shape) {
    case NotifShape.diamond:
    case NotifShape.diamondDot:
      return p.background; // the mock's --b-rdy-ink
    case NotifShape.arrow:
    case NotifShape.star:
    case NotifShape.pill:
      return p.brightness == Brightness.dark ? kNotifInkDark : kNotifInkLight;
  }
}
