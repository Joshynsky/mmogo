import 'package:flutter/material.dart';

import '../../../domain/format/money.dart';
import '../../theme/app_colors.dart';

/// §ADD.REVIEW_SHEET — the "Check before saving" sheet: a big amount, the
/// rows, "Nothing is saved until you confirm.", and Back / Confirm & save.
/// It is Add's only confirm surface: the confirm-before-save promise is kept
/// as a sheet rather than a separate full page.
///
/// Every field here is already resolved by the shell — this widget does no
/// DB work itself. [onConfirm] is the one seam into the shell's real save
/// (`add_screen.dart`'s `_save`): `null` back means "saved", a `String`
/// means "failed, show this inline."
class ReviewSheet extends StatefulWidget {
  const ReviewSheet({
    super.key,
    required this.isCash,
    required this.typeLabel,
    required this.amountCents,
    required this.counterpartyRowLabel,
    required this.counterpartyRowValue,
    required this.whenText,
    required this.code,
    required this.feeCents,
    required this.categoryName,
    required this.alwaysForThem,
    required this.onConfirm,
  });

  final bool isCash;
  final String typeLabel;
  final int amountCents;

  /// Both null (Cash, or M-Pesa with no name captured), or both non-null.
  final String? counterpartyRowLabel;
  final String? counterpartyRowValue;

  final String whenText;

  /// Empty for Cash.
  final String code;

  /// `null` for Cash.
  final int? feeCents;

  final String categoryName;

  /// Whether the "Always use" tick was checked for this counterparty — adds
  /// "· always for them" to the Category row, matching the mock's
  /// `aReview.onclick` exactly.
  final bool alwaysForThem;

  /// Returns `null` on success, an error message on failure.
  final Future<String?> Function() onConfirm;

  @override
  State<ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<ReviewSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _confirm() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await widget.onConfirm();
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _saving = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final rows = <(String, String)>[
      ('Type', widget.typeLabel),
      if (widget.counterpartyRowLabel != null) (widget.counterpartyRowLabel!, widget.counterpartyRowValue!),
      ('When', widget.whenText),
      if (!widget.isCash) ('Code', widget.code),
      if (widget.feeCents != null) ('Fee', formatKsh(widget.feeCents!)),
      ('Category', widget.categoryName + (widget.alwaysForThem ? ' · always for them' : '')),
    ];
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          key: const Key('addReviewSheet'),
          decoration: BoxDecoration(color: palette.card, borderRadius: const BorderRadius.vertical(top: Radius.circular(18))),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Check before saving', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: palette.ink)),
              const SizedBox(height: 12),
              Text(
                formatKsh(widget.amountCents),
                key: const Key('addReviewAmount'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: palette.ink),
              ),
              const SizedBox(height: 10),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(row.$1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.mutedInk)),
                      Flexible(
                        child: Text(
                          row.$2,
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                'Nothing is saved until you confirm.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11.5, color: palette.mutedInk),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    key: const Key('addReviewError'),
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFE5484D)),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('addReviewBackButton'),
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(foregroundColor: palette.ink, side: BorderSide(color: palette.line)),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('addReviewConfirmButton'),
                      onPressed: _saving ? null : _confirm,
                      style: FilledButton.styleFrom(backgroundColor: palette.primary, foregroundColor: palette.onPrimary),
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: palette.onPrimary),
                            )
                          : const Text('Confirm & save'),
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
