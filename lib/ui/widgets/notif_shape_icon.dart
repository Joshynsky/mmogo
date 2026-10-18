import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The generic shapes behind the bell badges and the Notifications rows.
/// Callers decide which kind of notice uses which shape.
enum NotifShape {
  /// Circle with an up-arrow.
  arrow,

  /// Rounded square with a star.
  star,

  /// Rounded pill, optionally with a number or short text.
  pill,

  /// Clean diamond (a rotated rounded square, nothing inside).
  diamond,

  /// Diamond with a dot in the middle (the list-row icon).
  diamondDot,
}

/// A solid shape icon drawn with a [CustomPainter] (no assets, no packages).
///
/// [size] is the height of every shape and the width of all but [NotifShape.pill],
/// which grows wider to fit its text. With [scaleWithText] the size follows the
/// text scale, capped at [maxTextScale] (the mock stops growing at 115 percent so
/// neighbouring corner badges never collide).
class NotifShapeIcon extends StatelessWidget {
  const NotifShapeIcon({
    super.key,
    required this.shape,
    required this.color,
    this.size = 20,
    this.ink,
    this.count,
    this.label,
    this.scaleWithText = true,
    this.maxTextScale = 1.15,
    this.excludeSemantics = true,
  });

  final NotifShape shape;

  /// Fill colour of the shape.
  final Color color;

  /// Colour of the glyph on the fill (arrow, star, number, dot). Defaults to
  /// white or near-black, whichever contrasts more with [color].
  final Color? ink;

  final double size;

  /// Number shown in a [NotifShape.pill] (ignored by other shapes).
  final int? count;

  /// Caller-supplied text for a pill (for example "99+"); wins over [count].
  final String? label;

  final bool scaleWithText;
  final double maxTextScale;

  /// When true (the default) the icon adds nothing to the semantics tree: the
  /// caller supplies one spoken label for the whole control.
  final bool excludeSemantics;

  static const Color _white = Color(0xFFFFFFFF);
  static const Color _nearBlack = Color(0xFF0A1114);

  String? get _text => shape == NotifShape.pill ? (label ?? (count == null ? null : '$count')) : null;

  @override
  Widget build(BuildContext context) {
    final scale = scaleWithText ? MediaQuery.textScalerOf(context).scale(1).clamp(1.0, maxTextScale).toDouble() : 1.0;
    final h = size * scale;
    final glyph = ink ?? _autoInk(color);
    final text = _text;
    var w = h;
    if (text != null && text.isNotEmpty) {
      w = math.max(h, _layoutText(text, h, glyph).width + h / 3);
    }
    final painter = NotifShapePainter(shape: shape, color: color, ink: glyph, text: text);
    final box = SizedBox(
      width: w,
      height: h,
      child: CustomPaint(painter: painter),
    );
    return excludeSemantics ? ExcludeSemantics(child: box) : box;
  }

  static Color _autoInk(Color fill) {
    final l = fill.computeLuminance();
    final withWhite = 1.05 / (l + 0.05);
    final withBlack = (l + 0.05) / (_nearBlack.computeLuminance() + 0.05);
    return withWhite >= withBlack ? _white : _nearBlack;
  }

  static TextPainter _layoutText(String text, double height, Color ink) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: ink, fontSize: height * 11 / 18, fontWeight: FontWeight.w800, height: 1),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
  }
}

/// Paints one [NotifShape] into the size it is given.
class NotifShapePainter extends CustomPainter {
  const NotifShapePainter({required this.shape, required this.color, required this.ink, this.text});

  final NotifShape shape;
  final Color color;
  final Color ink;
  final String? text;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final inkFill = Paint()
      ..color = ink
      ..isAntiAlias = true;
    final h = size.height;
    final center = Offset(size.width / 2, h / 2);
    switch (shape) {
      case NotifShape.arrow:
        canvas.drawCircle(center, h / 2, fill);
        final g = h * 0.625; // glyph box, 10 of 16 like the mock
        canvas.save();
        canvas.translate(center.dx - g / 2, center.dy - g / 2);
        canvas.scale(g / 24);
        final stroke = Paint()
          ..color = ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..isAntiAlias = true;
        canvas.drawPath(
          Path()
            ..moveTo(12, 20)
            ..lineTo(12, 5)
            ..moveTo(6, 11)
            ..lineTo(12, 5)
            ..lineTo(18, 11),
          stroke,
        );
        canvas.restore();
      case NotifShape.star:
        canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h * 0.25)), fill);
        final g = h * 0.625;
        canvas.save();
        canvas.translate(center.dx - g / 2, center.dy - g / 2);
        canvas.scale(g / 24);
        canvas.drawPath(
          Path()
            ..moveTo(12, 3)
            ..lineTo(14.6, 8.6)
            ..lineTo(20.6, 9.3)
            ..lineTo(16.2, 13.5)
            ..lineTo(17.4, 19.5)
            ..lineTo(12, 16.6)
            ..lineTo(6.6, 19.5)
            ..lineTo(7.8, 13.5)
            ..lineTo(3.4, 9.3)
            ..lineTo(9.4, 8.6)
            ..close(),
          inkFill,
        );
        canvas.restore();
      case NotifShape.pill:
        canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2)), fill);
        final t = text;
        if (t != null && t.isNotEmpty) {
          final tp = NotifShapeIcon._layoutText(t, h, ink);
          tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        }
      case NotifShape.diamond:
      case NotifShape.diamondDot:
        final side = h * 0.7; // diagonal is about the full height
        canvas.save();
        canvas.translate(center.dx, center.dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: side, height: side),
            Radius.circular(side * 0.2),
          ),
          fill,
        );
        canvas.restore();
        if (shape == NotifShape.diamondDot) {
          canvas.drawCircle(center, side * 0.15, inkFill);
        }
    }
  }

  @override
  bool shouldRepaint(NotifShapePainter old) =>
      old.shape != shape || old.color != color || old.ink != ink || old.text != text;
}
