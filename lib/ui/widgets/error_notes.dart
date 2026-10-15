import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// §WIDGET.ERROR_NOTE — error pattern A (signed 08-10-2026).
///
/// [FieldError]: a field error is red text with a small warning icon under the
/// field, no timer. [ErrorBox]: a sheet-level error is a light-red tinted box
/// with dark red text and the icon. Both are live regions so a screen reader
/// announces them. The box colours are the mock's `--err-box-bg/--err-box-text`
/// (light #FCE8E6 / #8C1D18, dark #4A1F22 / #FFC9CB).
class FieldError extends StatelessWidget {
  const FieldError(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(14, 2, 14, 8)});

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: padding,
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.warning_amber_rounded, size: 16, color: palette.error),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600, color: palette.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = AppPalette.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFFFC9CB) : const Color(0xFF8C1D18);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF4A1F22) : const Color(0xFFFCE8E6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.warning_amber_rounded, size: 18, color: ink),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, fontWeight: FontWeight.w600, color: ink)),
            ),
          ],
        ),
      ),
    );
  }
}
