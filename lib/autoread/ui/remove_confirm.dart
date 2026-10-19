/// §AUTOREAD.REMOVE_CONFIRM — the short question before an unreadable or gone
/// waiting item is removed (signed mock, "Remove this message?").
/// Autoread flavor only; reached from shared code inside `if (kAutoReadCompiled)`.
library;

import 'package:flutter/material.dart';

import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart';

/// Asks "Remove this message?". Returns true only when the user taps Remove;
/// Cancel, scrim and Back return false.
Future<bool> showRemoveConfirm(BuildContext context, {required WaitingItem item}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (_) => const _RemoveDialog(),
  );
  return r ?? false;
}

class _RemoveDialog extends StatelessWidget {
  const _RemoveDialog();

  @override
  Widget build(BuildContext context) {
    const minSize = Size(64, 44);
    return AlertDialog(
      title: const Text(kRemoveTitle),
      content: const Text(kRemoveBody),
      actions: [
        TextButton(
          key: const Key('removeCancel'),
          style: TextButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(kRemoveCancel),
        ),
        FilledButton(
          key: const Key('removeConfirm'),
          style: FilledButton.styleFrom(minimumSize: minSize),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text(kRemoveConfirm),
        ),
      ],
    );
  }
}
