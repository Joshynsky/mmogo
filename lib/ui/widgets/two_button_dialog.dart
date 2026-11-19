import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'palette_alert_dialog.dart';

/// §WIDGET.TWO_BUTTON_DIALOG (0.2.1) — a question with two buttons side by side
/// (left = the safe or neutral choice, right = the main choice). Returns true when
/// the right button was tapped, false for the left one, null when dismissed.
/// [danger] paints the right button red (a delete).
Future<bool?> showTwoButtonDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String leftLabel,
  required String rightLabel,
  bool danger = false,
  Key? dialogKey,
}) {
  final p = AppPalette.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => PaletteAlertDialog(
      key: dialogKey,
      title: Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: p.ink)),
      content: Text(body, style: TextStyle(fontSize: 13, height: 1.4, color: p.softInk)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  key: const Key('twoButtonLeft'),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: FilledButton.styleFrom(
                    backgroundColor: p.track,
                    foregroundColor: p.ink,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Text(leftLabel, textAlign: TextAlign.center),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 44,
                child: FilledButton(
                  key: const Key('twoButtonRight'),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: danger ? p.diffUp : p.primary,
                    foregroundColor: danger ? p.onDelete : p.onPrimary,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: Text(rightLabel, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
