import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §PAIDTO.PAGER_DOTS — the page dots shared by the ACCOUNTS pager and the swipeable All time
/// chart: one 44x44 tap box per page (the dot is 8 px, 16 px wide when current), no arrows.
/// [keyPrefix] + page number is each dot's key; [labelOf] is its screen-reader label.
class PaidToPagerDots extends StatelessWidget {
  const PaidToPagerDots({
    super.key,
    required this.palette,
    required this.count,
    required this.current,
    required this.onTap,
    required this.keyPrefix,
    required this.labelOf,
  });

  final AppPalette palette;
  final int count;
  final int current;
  final ValueChanged<int> onTap;
  final String keyPrefix;
  final String Function(int page) labelOf;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (var k = 0; k < count; k++)
          Semantics(
            button: true,
            selected: k == current,
            label: labelOf(k),
            excludeSemantics: true,
            child: GestureDetector(
              key: Key('$keyPrefix$k'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(k),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: k == current ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: k == current ? palette.primary : palette.line,
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
