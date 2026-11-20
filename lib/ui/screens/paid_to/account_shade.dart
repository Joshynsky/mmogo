import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §PAIDTO.ACCOUNT_SHADE — 0.2.1 #4 (MK-12, PM 12-11-2026 A): the two ALTERNATING shades of the
/// Paybill colour that tell the accounts of one name apart: the round dot on an ACCOUNTS row and the
/// segments of a stacked chart bar. Even places in the list (biggest first) get the Paybill colour,
/// odd places a lighter mix of it (a darker mix in the dark theme).
Color paidToAccountShade(AppPalette p, int index) {
  if (index.isEven) return p.typePaybill;
  final toward = p.brightness == Brightness.light ? Colors.white : Colors.black;
  return Color.lerp(p.typePaybill, toward, p.brightness == Brightness.light ? 0.58 : 0.55)!;
}
