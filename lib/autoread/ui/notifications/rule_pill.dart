/// §AUTOREAD.RULE_PILL - the small round button the Notifications rule parts share
/// (44 px high, filled or outlined). Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';

class RulePill extends StatelessWidget {
  const RulePill({super.key, required this.label, required this.onTap, this.fill = false, this.spoken});
  final String label;
  final VoidCallback? onTap;

  /// Filled primary look (the answer the row asks for).
  final bool fill;
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      button: true,
      label: spoken ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: fill ? p.primary : p.surface,
        shape: StadiumBorder(side: BorderSide(color: fill ? p.primary : p.line, width: 1.5)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: fill ? FontWeight.w800 : FontWeight.w700, color: fill ? p.onPrimary : p.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
