import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The amber warning panel (mock `.nwarn`): used for the unencrypted-file
/// warning (W1) and, later, the other data-safety notices.
class BackupWarning extends StatelessWidget {
  const BackupWarning({
    super.key,
    required this.palette,
    required this.text,
    this.bottomGap = 12,
    this.title,
    this.action,
  });

  final AppPalette palette;
  final String text;
  final double bottomGap;

  /// Bold lead-in before [text] (the paused banner).
  final String? title;

  /// A small button under the text (for example "Choose folder").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: bottomGap),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: palette.highlight,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        border: Border(left: BorderSide(color: palette.sun, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: palette.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      if (title != null) TextSpan(text: title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      TextSpan(text: text),
                    ],
                  ),
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: palette.ink),
                ),
                if (action != null) ...[const SizedBox(height: 8), action!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A rounded palette card with 16 px padding (mock `.acard.npad`).
class BackupCard extends StatelessWidget {
  const BackupCard({super.key, required this.palette, required this.children});

  final AppPalette palette;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: palette.brightness == Brightness.dark
            ? null
            : [BoxShadow(color: palette.deep.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 1))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

/// Body paragraph inside a [BackupCard] (mock `.np`).
class BackupPara extends StatelessWidget {
  const BackupPara(this.text, {super.key, required this.palette, this.bold = false, this.bottom = 9});

  final String text;
  final AppPalette palette;
  final bool bold;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: bold ? palette.ink : palette.softInk,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}
