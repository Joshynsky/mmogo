import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ANALYTICS.TYPE_STRIP — the By-type tile strip's scrolling and pager.
/// The swipeable two-row tile strip with its two pager dots (mock `.tscr` and
/// `.dots`): page 1 = columns 1-2, page 2 = columns 3-4, the third column
/// peeks 14 px on page 1. Snaps to a page when a swipe ends.
class AnalyticsTypeStrip extends StatefulWidget {
  const AnalyticsTypeStrip({super.key, required this.palette, required this.columns});

  final AppPalette palette;
  final List<List<Widget>> columns;

  @override
  State<AnalyticsTypeStrip> createState() => _AnalyticsTypeStripState();
}

class _AnalyticsTypeStripState extends State<AnalyticsTypeStrip> {
  final _controller = ScrollController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncPage() {
    if (!_controller.hasClients) return;
    final p = _controller.position;
    final page = p.pixels > p.maxScrollExtent / 2 ? 1 : 0;
    if (page != _page) setState(() => _page = page);
  }

  void _go(int page) {
    if (!_controller.hasClients) return;
    _controller.animateTo(
      page == 0 ? 0 : _controller.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollEndNotification) {
      final p = n.metrics;
      final target = p.pixels > p.maxScrollExtent / 2 ? p.maxScrollExtent : 0.0;
      if ((p.pixels - target).abs() > 0.5) {
        // Deferred: the end notification is sent while the scroll activity is
        // still being replaced, so an animation started now would be dropped.
        Future.microtask(() {
          if (mounted && _controller.hasClients) {
            _controller.animateTo(target, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
          }
        });
      }
    }
    _syncPage();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final colW = (c.maxWidth - 8) / 2 - 14;
            return NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: SingleChildScrollView(
                key: const Key('analyticsTypeStrip'),
                controller: _controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (i, col) in widget.columns.indexed) ...[
                      if (i > 0) const SizedBox(width: 8),
                      SizedBox(
                        width: colW,
                        child: Column(
                          children: [
                            for (final (j, t) in col.indexed) ...[if (j > 0) const SizedBox(height: 8), t],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _PagerDot(
              key: const Key('analyticsTypeDot0'),
              palette: p,
              on: _page == 0,
              label: 'Show Send Money, Paybill, Buy Goods and Cash',
              onTap: () => _go(0),
            ),
            _PagerDot(
              key: const Key('analyticsTypeDot1'),
              palette: p,
              on: _page == 1,
              label: 'Show Pochi, Withdrawal and Airtime',
              onTap: () => _go(1),
            ),
          ],
        ),
      ],
    );
  }
}

/// One pager dot: the dot keeps its small look, the tap target is 44 x 44.
class _PagerDot extends StatelessWidget {
  const _PagerDot({super.key, required this.palette, required this.on, required this.label, required this.onTap});

  final AppPalette palette;
  final bool on;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: on ? 16 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: on ? palette.primary : palette.line,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
