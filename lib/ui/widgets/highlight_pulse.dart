import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// How long a linked area stays outlined.
const kHighlightDuration = Duration(seconds: 2);

/// §UI.WIDGETS.HIGHLIGHT — 0.2.1 #10. A link (What's new) names the area it wants lit just before it opens the page; the page takes
/// the request once in its `initState`, and it is gone, so a later visit is never lit by mistake.
class HighlightRequest {
  HighlightRequest._();

  static String? _id;

  static void set(String? id) => _id = id;

  /// The pending id, cleared by this read.
  static String? take() {
    final id = _id;
    _id = null;
    return id;
  }
}

/// Wraps one area of a page. While [active] (from the page's first build) it scrolls itself into
/// view and draws a primary outline for [kHighlightDuration], fading out. With animations turned
/// off the outline is steady and then simply goes. The outline is a border, so it does not rely
/// on colour alone.
class HighlightPulse extends StatefulWidget {
  const HighlightPulse({super.key, required this.active, required this.child, this.radius = 14, this.alignment = 0.3});

  final bool active;

  /// Where the area lands in the viewport (0 = its top at the top; tall areas use 0).
  final double alignment;
  final Widget child;
  final double radius;

  @override
  State<HighlightPulse> createState() => _HighlightPulseState();
}

class _HighlightPulseState extends State<HighlightPulse> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    if (!widget.active) return;
    _on = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, alignment: widget.alignment, duration: Duration.zero);
    });
    Future<void>.delayed(kHighlightDuration, () {
      if (mounted) setState(() => _on = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final color = AppPalette.of(context).primary;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _on ? 1 : 0,
              duration: still ? Duration.zero : const Duration(milliseconds: 400),
              child: DecoratedBox(
                key: const Key('highlightOutline'),
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2.5),
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
