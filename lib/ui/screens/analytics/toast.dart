import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// §ANALYTICS.TOAST — the "moved to Recently Deleted" toast with Undo.
class AnalyticsToast extends StatelessWidget {
  const AnalyticsToast({super.key, required this.palette, required this.message, required this.onUndo});

  final AppPalette palette;
  final String message;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('analyticsToast'),
        padding: const EdgeInsets.fromLTRB(14, 7, 8, 7),
        decoration: BoxDecoration(
          color: palette.ink,
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            children: [
              Expanded(
                child: Text(message, style: TextStyle(fontSize: 12.5, color: palette.background)),
              ),
              const SizedBox(width: 10),
              TextButton(
                key: const Key('analyticsUndo'),
                onPressed: onUndo,
                style: TextButton.styleFrom(
                  foregroundColor: palette.toastAction,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                child: const Text('Undo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
