/// §ANALYTICS.COPY_BUTTON — the small "Copy" button beside the phone, account
/// and agent number fields of the edit sheet (0.2.0 S7, mock item 4 of
/// CHANGES-2026-11-03). The edit sheet shows it only while "Record receiver
/// details" is on and the field is not empty. It copies what the field shows now.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';

// WORDING-DRAFT: "Copy" and "Copied" are new UI labels (from the mock).
const String kCopyLabel = 'Copy';
const String kCopiedLabel = 'Copied';

/// Copies [controller]'s text to the clipboard; the label says "Copied" for two
/// seconds (an inline label, so it also shows inside a bottom sheet).
/// Hidden while the field is empty.
class CopyFieldButton extends StatefulWidget {
  const CopyFieldButton({super.key, required this.controller, required this.palette, required this.what});

  final TextEditingController controller;
  final AppPalette palette;

  /// Spoken name of the field: "phone number", "account number", "agent number".
  final String what;

  @override
  State<CopyFieldButton> createState() => _CopyFieldButtonState();
}

class _CopyFieldButtonState extends State<CopyFieldButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (widget.controller.text.trim().isEmpty) return const SizedBox.shrink();
        return Semantics(
          button: true,
          liveRegion: true,
          label: _copied ? '$kCopiedLabel: ${widget.what}' : '$kCopyLabel ${widget.what}',
          excludeSemantics: true,
          onTap: _copy,
          child: TextButton.icon(
            key: Key('copy-${widget.what}'),
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              foregroundColor: p.primary,
            ),
            onPressed: _copy,
            icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
            label: Text(_copied ? kCopiedLabel : kCopyLabel,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        );
      },
    );
  }
}
