import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ADD.REVIEW_BAR — the sticky bottom "Review & save" bar:
/// disabled until there is an
/// amount, a valid code (M-Pesa) and a category; the hint line ("Still needed: ...")
/// names only what is missing and keeps its one line of height when empty.
class ReviewBar extends StatelessWidget {
  const ReviewBar({super.key, required this.enabled, required this.hint, required this.onTap});

  final bool enabled;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(color: palette.background, border: Border(top: BorderSide(color: palette.line))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                key: const Key('addReviewButton'),
                onPressed: enabled ? onTap : null,
                style: FilledButton.styleFrom(backgroundColor: palette.primary, disabledBackgroundColor: palette.line),
                child: Text(
                  'Review & save',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: enabled ? palette.onPrimary : palette.mutedInk),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // F2 (R29/R39): the hint line always takes (at least) one line of height, so the
            // button above never moves when the words appear or go.
            if (hint.isNotEmpty)
              Text(hint, key: const Key('addReviewHint'), style: TextStyle(fontSize: 11, color: palette.mutedInk))
            else
              ExcludeSemantics(
                child: Text('\u00A0', key: const Key('addReviewHintSlot'), style: TextStyle(fontSize: 11, color: palette.mutedInk)),
              ),
          ],
        ),
      ),
    );
  }
}
