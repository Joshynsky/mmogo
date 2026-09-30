import 'package:flutter/material.dart';

/// §WIDGET.TYPE_ICON — the icon for a transaction source type, and the 34x34
/// tinted tile (type colour at alpha 0.16, radius 11) that holds it.
IconData sourceTypeIcon(String code) => switch (code) {
  'SEND_MONEY' => Icons.arrow_forward_rounded,
  'PAYBILL' => Icons.receipt_long_outlined,
  'BUY_GOODS' => Icons.shopping_bag_outlined,
  _ => Icons.payments_outlined,
};

class TypeIconTile extends StatelessWidget {
  const TypeIconTile({super.key, required this.code, required this.color});

  /// The source type (`SEND_MONEY`, `PAYBILL`, `BUY_GOODS`, `CASH`).
  final String code;

  /// The type's colour (`palette.typeColor(code)`).
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: const BorderRadius.all(Radius.circular(11)),
      ),
      child: Icon(sourceTypeIcon(code), size: 18, color: color),
    );
  }
}
