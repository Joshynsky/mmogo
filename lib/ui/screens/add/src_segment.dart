import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ADD.SRC_SEGMENT — the M-Pesa | Cash switch at the top of Add. Moved out of
/// `add_screen.dart` (0.1.2 S8c-1 step 0), unchanged.
class SrcSegment extends StatelessWidget {
  const SrcSegment({super.key, required this.src, required this.onChanged});

  final String src;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // In the dark palettes `track` and `surface` equal the page colour, so the
    // toggle would be invisible: use the card colour for the track there.
    final dark = palette.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: dark ? palette.card : palette.track, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _segment(context, palette, 'M-Pesa', 'MPESA')),
          Expanded(child: _segment(context, palette, 'Cash', 'CASH')),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, AppPalette palette, String label, String value) {
    final active = src == value;
    return GestureDetector(
      key: Key('addSrcSeg_$value'),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: active ? (palette.brightness == Brightness.dark ? palette.line : palette.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? palette.ink : palette.mutedInk),
        ),
      ),
    );
  }
}
