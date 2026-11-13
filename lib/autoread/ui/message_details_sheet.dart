/// §AUTOREAD.MESSAGE_DETAILS_SHEET — the bottom sheet a waiting row's Details
/// link opens (mock item 7 of CHANGES-2026-11-03). Autoread flavor only.
///
/// It shows [MessageDetails] (built by `buildMessageDetails`): sender, time
/// received, amount, what mmogo understood, exact time left. It never shows the
/// raw message. For a message that could not be read it shows only the code,
/// amount and time the light reader found, and Remove.
library;

import 'package:flutter/material.dart';

import '../../ui/theme/app_colors.dart';
import '../logic/message_details.dart';
import '../model/waiting_item.dart';
import 'notifications_autoread_copy.dart' show kActionRemove;

/// Opens the sheet with [details] (null: the row is gone from the list).
/// [onRemove] (shown for an unreadable message only) is called after the sheet
/// closed with Remove; asking "Remove this message?" is the caller's job.
Future<void> showMessageDetailsSheet(BuildContext context,
    {required MessageDetails? details, VoidCallback? onRemove}) async {
  final remove = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MessageDetailsSheet(details: details, canRemove: onRemove != null),
  );
  if (remove == true) onRemove?.call();
}

class MessageDetailsSheet extends StatelessWidget {
  const MessageDetailsSheet({super.key, required this.details, this.canRemove = false});

  final MessageDetails? details;

  /// Show Remove (unreadable messages only).
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    final d = details;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewPadding.bottom),
      child: Material(
        color: p.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Semantics(
                        header: true,
                        child: Text(
                          kDetailsTitle,
                          style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('detailsClose'),
                    tooltip: kDetailsClose,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (d == null)
                Text(kDetailsMissing, style: TextStyle(fontSize: 14, height: 1.4, color: p.mutedInk))
              else ...[
                for (final l in d.lines) _Line(l),
                if (d.note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, right: 8),
                    child: Text(d.note!, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
                  ),
                if (d.fine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: Text(d.fine!, style: TextStyle(fontSize: 12, height: 1.4, color: p.mutedInk)),
                  ),
                if (canRemove && d.kind == WaitingKind.unreadable)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: const Key('detailsRemove'),
                          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text(kActionRemove),
                        ),
                        TextButton(
                          key: const Key('detailsCloseButton'),
                          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text(kDetailsClose),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.line);
  final DetailLine line;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Semantics(
      container: true,
      label: '${line.label}: ${line.value}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: p.mutedInk)),
            Text(line.value, style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w700, color: p.ink)),
          ],
        ),
      ),
    );
  }
}
