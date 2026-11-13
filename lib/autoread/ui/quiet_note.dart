/// §AUTOREAD.QUIET_NOTE - the one-line note at the top of the To do page. It
/// replaces toasts for ordinary actions: no timer, no button; it is announced
/// once and goes away on the next tap anywhere on the page.
library;

import 'package:flutter/material.dart';

import '../../ui/theme/app_colors.dart';

/// Wraps the page list. [note] holds the text to show (null = none). Whoever
/// handles an action sets `note.value`; the next pointer-down clears it.
class QuietNote extends StatelessWidget {
  const QuietNote({super.key, required this.note, required this.child});

  final ValueNotifier<String?> note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        if (note.value != null) note.value = null;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: note,
            builder: (context, text, _) => text == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                    child: Semantics(
                      liveRegion: true,
                      container: true,
                      child: Text(
                        text,
                        key: const Key('quiet-note'),
                        style: TextStyle(fontSize: 12, height: 1.4, fontWeight: FontWeight.w600, color: p.mutedInk),
                      ),
                    ),
                  ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
