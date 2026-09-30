import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// §WIDGET.BOTTOM_SHEET_SHELL — the shared bottom-sheet shell (mock `.sheet`):
/// keyboard inset, card surface, 22px top corners, 16/16/22 padding, 12px gaps.
class BottomSheetShell extends StatelessWidget {
  const BottomSheetShell({super.key, required this.palette, required this.children});

  final AppPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: palette.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
