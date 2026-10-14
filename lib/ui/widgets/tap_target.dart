import 'package:flutter/material.dart';

/// §WIDGET.TAP_TARGET — TS1: the smallest tap target on a shared control.
const double kMinTapTarget = 44;

/// Grows the hit area of a small control to at least [kMinTapTarget] square
/// WITHOUT changing how big the control looks: [child] is centred in the
/// larger box and the box's own detector fires [onTap] for a tap on the ring
/// around it. The control inside keeps its own ripple and semantics; this
/// detector adds none (a tap inside [child] is won by the child).
class TapTarget extends StatelessWidget {
  const TapTarget({super.key, required this.onTap, required this.child, this.expandWidth = true});

  final VoidCallback? onTap;
  final Widget child;

  /// False for a control that is already wide (a pill): only the height grows.
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: expandWidth ? kMinTapTarget : 0, minHeight: kMinTapTarget),
        child: Center(widthFactor: 1, heightFactor: 1, child: child),
      ),
    );
  }
}
