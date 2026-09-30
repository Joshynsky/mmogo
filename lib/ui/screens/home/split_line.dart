import 'dart:math' as math;

import 'package:flutter/material.dart';

/// §HOME.SPLIT_LINE — one line: a label taking the free space, an amount on the right.
///
/// One line with [start] taking the free space and [end] on the right at its
/// natural width — capped at [endMaxFraction] of the line, beyond which it
/// scales down (only at very large text sizes). So an amount never squeezes
/// its label to nothing and the line never overflows.
class HomeSplitLine extends StatelessWidget {
  const HomeSplitLine({
    super.key,
    required this.start,
    required this.end,
    this.gap = 8,
    this.crossAxisAlignment = CrossAxisAlignment.center,
    this.endAlignment = Alignment.centerRight,
  });

  final Widget start;
  final Widget end;
  final double gap;

  /// [end] never takes more than this share of the line.
  static const endMaxFraction = 0.5;
  final CrossAxisAlignment crossAxisAlignment;
  final Alignment endAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          Expanded(child: start),
          SizedBox(width: gap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: math.max(0, constraints.maxWidth * endMaxFraction)),
            child: FittedBox(fit: BoxFit.scaleDown, alignment: endAlignment, child: end),
          ),
        ],
      ),
    );
  }
}
