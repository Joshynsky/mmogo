/// §WIDGET.COLLAPSING_PADDING: padding that is only there while its child draws something. For a slot
/// whose widget may draw nothing (a banner shown only while paused, a line shown only with a count): the
/// space around it goes with it, so a hidden banner leaves no gap. A child of zero height takes no room.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class CollapsingPadding extends SingleChildRenderObjectWidget {
  const CollapsingPadding({super.key, required this.padding, super.child});

  final EdgeInsetsGeometry padding;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderCollapsingPadding(padding.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr));

  @override
  void updateRenderObject(BuildContext context, RenderCollapsingPadding renderObject) =>
      renderObject.padding = padding.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr);
}

/// The render box of [CollapsingPadding].
class RenderCollapsingPadding extends RenderShiftedBox {
  RenderCollapsingPadding(this._padding) : super(null);

  EdgeInsets _padding;
  set padding(EdgeInsets v) {
    if (v == _padding) return;
    _padding = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.deflate(_padding), parentUsesSize: true);
    final data = c.parentData! as BoxParentData;
    if (c.size.height == 0) {
      data.offset = Offset.zero;
      size = constraints.constrain(Size(c.size.width, 0));
    } else {
      data.offset = Offset(_padding.left, _padding.top);
      size = constraints.constrain(Size(c.size.width + _padding.horizontal, c.size.height + _padding.vertical));
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final s = c.getDryLayout(constraints.deflate(_padding));
    if (s.height == 0) return constraints.constrain(Size(s.width, 0));
    return constraints.constrain(Size(s.width + _padding.horizontal, s.height + _padding.vertical));
  }

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicH(child?.getMinIntrinsicHeight(width - _padding.horizontal));

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicH(child?.getMaxIntrinsicHeight(width - _padding.horizontal));

  double _intrinsicH(double? h) => h == null || h == 0 ? 0 : h + _padding.vertical;

  @override
  double computeMinIntrinsicWidth(double height) => (child?.getMinIntrinsicWidth(height) ?? 0) + _padding.horizontal;

  @override
  double computeMaxIntrinsicWidth(double height) => (child?.getMaxIntrinsicWidth(height) ?? 0) + _padding.horizontal;
}
