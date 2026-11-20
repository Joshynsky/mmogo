/// §AUTOREAD.NOTHING_WAITING_LINE - the empty state of To do, placed as the mock shows it:
/// nothing waiting and no Recorded automatically item = the bold line with the signed
/// "All caught up" card lower down (bottom); with a Recorded automatically item = one quiet line
/// at the top, above that section. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../todo_copy.dart';
import 'notifications_rule_copy.dart';

class NothingWaitingLine extends StatelessWidget {
  const NothingWaitingLine({super.key, required this.top});

  /// True: one quiet line above Recorded automatically. False: the bottom card.
  final bool top;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    if (top) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
        child: Text(kNothingWaiting,
            key: const Key('nothing-waiting-top'),
            style: TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w600, color: p.mutedInk)),
      );
    }
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, (h * 0.15).clamp(24.0, 160.0), 12, 32),
      child: Semantics(
        container: true,
        key: const Key('todo-empty'),
        child: Column(
          children: [
            Text(kNothingWaiting, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: p.ink)),
            const SizedBox(height: 4),
            Text(kTodoEmptyTitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink)),
            const SizedBox(height: 4),
            Text(kTodoEmptyBody, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, height: 1.4, color: p.mutedInk)),
          ],
        ),
      ),
    );
  }
}
