import 'package:flutter/material.dart';

import '../../../domain/parsing/parse_result.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../../domain/parsing/sms_parser.dart';
import '../../theme/app_colors.dart';

/// §ADD.PASTE — the paste-first card: a "Paste M-Pesa SMS" card that leads the M-Pesa form, a bottom sheet
/// with a paste box and "Fill it in" (using the EXISTING [SmsParser] — no
/// new parsing logic), and, once a parse has filled the form, a "Filled in
/// from your SMS. Check it below." strip with "Start over" in its place.
///
/// A parse failure shows INLINE in the sheet (`_PasteSheet`'s own `_error`
/// state) — this replaces the old dialog-based error
/// (`mpesa_tab_body.dart`'s `_showParseErrorDialog`, now retired with that
/// file).
///
/// T19 — when [hintAnchor] is non-null it wraps only the unfilled "Paste
/// M-Pesa SMS" button in a `CompositedTransformTarget`, so Add's contextual
/// hint floats just below the real control it names. Once [filled] is true
/// the button is gone (replaced by the strip) — the hint host's own rule
/// ("anchor not currently built -> bubble simply not shown, seen flag not
/// touched") takes care of hiding it without this widget doing anything
/// special.
class PasteCard extends StatelessWidget {
  const PasteCard({
    super.key,
    required this.filled,
    required this.onParsed,
    required this.onStartOver,
    this.hintAnchor,
  });

  final bool filled;

  /// Fired once a paste is successfully parsed — the shell applies every
  /// field (D1/D2/D3/D4 in the old `mpesa_tab_body.dart`, now this
  /// screen's own rules) and sets `filled = true`.
  final ValueChanged<ParsedSmsFields> onParsed;

  /// D2 — clears the whole form back to manual entry with the Type pills
  /// selectable again.
  final VoidCallback onStartOver;

  final LayerLink? hintAnchor;

  Future<void> _openSheet(BuildContext context) async {
    final fields = await showModalBottomSheet<ParsedSmsFields>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PasteSheet(),
    );
    if (fields != null) onParsed(fields);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (filled) {
      return Container(
        key: const Key('addFilledStrip'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: palette.tint, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: palette.tintInk),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Filled in from your SMS. Check it below.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: palette.tintInk),
              ),
            ),
            TextButton(
              key: const Key('addStartOverButton'),
              onPressed: onStartOver,
              style: TextButton.styleFrom(foregroundColor: palette.tintInk),
              child: const Text('Start over', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    }
    final button = Material(
      color: palette.tint,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: const Key('addPasteButton'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: palette.primary,
                child: Icon(Icons.sms_outlined, color: palette.onPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Parse M-Pesa message',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: palette.tintInk),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'We fill everything in. You check it before it’s saved.',
                      style: TextStyle(fontSize: 12, color: palette.tintInk.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return hintAnchor == null ? button : CompositedTransformTarget(link: hintAnchor!, child: button);
  }
}

/// The "Paste the M-Pesa SMS" bottom sheet — a paste textarea, an inline
/// error on a failed parse (never a dialog), and "Fill it in".
class _PasteSheet extends StatefulWidget {
  const _PasteSheet();

  @override
  State<_PasteSheet> createState() => _PasteSheetState();
}

class _PasteSheetState extends State<_PasteSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final result = SmsParser.parse(_controller.text);
    switch (result) {
      case ParseSuccess(:final fields):
        Navigator.of(context).pop(fields);
      case ParseError(:final reason):
        setState(() => _error = reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final border = OutlineInputBorder(borderSide: BorderSide(color: palette.line));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: palette.card,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Parse the M-Pesa message',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink),
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('addPasteTextField'),
                controller: _controller,
                maxLines: 6,
                style: TextStyle(color: palette.ink),
                cursorColor: palette.primary,
                // A stale "couldn't recognize" error goes as soon as the text changes.
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Long-press here and paste the whole confirmation message',
                  hintStyle: TextStyle(color: palette.mutedInk),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: palette.primary, width: 1.5)),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _error!,
                    key: const Key('addPasteError'),
                    style: const TextStyle(fontSize: 12, color: Color(0xFFE5484D)),
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('addPasteCancelButton'),
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.ink,
                        side: BorderSide(color: palette.line),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('addPasteSubmitButton'),
                      onPressed: _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.primary,
                        foregroundColor: palette.onPrimary,
                      ),
                      child: const Text('Parse'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
