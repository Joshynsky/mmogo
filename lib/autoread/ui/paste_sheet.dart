/// §AUTOREAD.PASTE_SHEET — the small bottom sheet a Paste tap opens (signed
/// mock): "Copy the M-Pesa message first, then continue to Add." It does not
/// read the clipboard or open Add; the caller's callback does that.
/// Autoread flavor only.
library;

import 'package:flutter/material.dart';

import '../../ui/theme/app_colors.dart';
import 'notifications_autoread_copy.dart';

/// Opens the sheet. [onContinueToAdd] is called once, after the sheet has
/// closed, when the user taps Continue (or the quiet "Already copied it?"
/// button, which the mock also sends to Add). Close, scrim and Back call nothing.
Future<void> showPasteSheet(BuildContext context, {required VoidCallback onContinueToAdd}) async {
  final go = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const PasteSheet(),
  );
  if (go == true) onContinueToAdd();
}

class PasteSheet extends StatefulWidget {
  const PasteSheet({super.key});

  @override
  State<PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<PasteSheet> {
  bool _done = false;

  void _go() {
    if (_done) return; // double tap ignored
    _done = true;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final mq = MediaQuery.of(context);
    const minSize = Size.fromHeight(44);
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
                          kPasteSheetHeading,
                          style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w800, color: p.ink),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('pasteClose'),
                    tooltip: kPasteClose,
                    constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  key: const Key('pasteContinue'),
                  style: FilledButton.styleFrom(minimumSize: minSize),
                  onPressed: _go,
                  child: const Text(kPasteContinue),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 8),
                child: TextButton(
                  key: const Key('pasteGoStraight'),
                  style: TextButton.styleFrom(minimumSize: minSize),
                  onPressed: _go,
                  child: const Text(kPasteGoStraight, textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
