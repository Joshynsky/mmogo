import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ADD.SRC_SEGMENT — the M-Pesa | Cash switch at the top of Add. Moved out of
/// `add_screen.dart` (0.1.2 S8c-1 step 0). S11b (TS2): the track's 4 px padding
/// now sits INSIDE each segment's tap area (same look), so each segment is
/// 45 px high to the finger instead of 37.
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
      decoration: BoxDecoration(color: dark ? palette.card : palette.track, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Expanded(child: _segment(context, palette, 'M\u2011Pesa', 'MPESA', const EdgeInsets.all(4).copyWith(right: 0))),
          Expanded(child: _segment(context, palette, 'Cash', 'CASH', const EdgeInsets.all(4).copyWith(left: 0))),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, AppPalette palette, String label, String value, EdgeInsets outer) {
    final active = src == value;
    return GestureDetector(
      key: Key('addSrcSeg_$value'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(value),
      child: Padding(
        padding: outer,
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
      ),
    );
  }
}
