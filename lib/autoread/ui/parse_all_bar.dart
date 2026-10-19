/// §AUTOREAD.PARSE_ALL_BAR — the "Parse all (n)" button of the To parse group
/// (signed mock). Counts only READABLE ready items (not unreadable or gone).
/// Hidden below 2; runs straight away at 2 or 3; asks above 3 with the real
/// number. Autoread flavor only. The parsing itself is the caller's callback.
library;

import 'package:flutter/material.dart';

import '../../domain/notifications/news_logic.dart' show capCount;
import '../logic/waiting_logic.dart';
import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart';

/// Above this many ready messages Parse all asks first (mock: "4 or more").
const int kParseAllAskAbove = 3;

/// The readable ready-to-parse items among [waiting] at [now], in list order.
List<WaitingItem> readableReady(Iterable<WaitingItem> waiting, DateTime now) => [
      for (final w in sortReadyToParse(waiting, now))
        if (effectiveKind(w, now) == WaitingKind.readyToParse) w,
    ];

class ParseAllBar extends StatelessWidget {
  const ParseAllBar({
    super.key,
    required this.waiting,
    required this.now,
    required this.onParseAll,
  });

  final List<WaitingItem> waiting;
  final DateTime now;
  final void Function(List<WaitingItem> items) onParseAll;

  Future<void> _tap(BuildContext context, List<WaitingItem> items) async {
    if (items.length > kParseAllAskAbove) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (_) => _ParseAllDialog(items.length),
      );
      if (yes != true) return;
    }
    onParseAll(items);
  }

  @override
  Widget build(BuildContext context) {
    final items = readableReady(waiting, now);
    if (items.length < 2) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: parseAllBarSpoken(items.length),
      excludeSemantics: true,
      child: OutlinedButton(
        key: const Key('parseAllBar'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
        onPressed: () => _tap(context, items),
        child: Text(parseAllBarLabel(capCount(items.length))),
      ),
    );
  }
}

class _ParseAllDialog extends StatelessWidget {
  const _ParseAllDialog(this.n);
  final int n;

  @override
  Widget build(BuildContext context) {
    const minSize = Size(64, 44);
    return AlertDialog(
      title: Text(parseAllTitle(n)),
      content: const Text(kParseAllBody),
      actions: [
        TextButton(
          key: const Key('parseAllCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kParseAllCancel),
        ),
        FilledButton(
          key: const Key('parseAllConfirm'),
          style: FilledButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kParseAllConfirm),
        ),
      ],
    );
  }
}
