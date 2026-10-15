import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../theme/app_colors.dart';
import 'category_chips.dart';

/// §ADD.CATEGORY_SECTION — the "Category" heading and its chips on the Add form
/// (moved out of `add_screen.dart` in 0.1.2 S8c-2 with the same behaviour).
/// Withdrawal and Airtime show one muted line (`Category: X`, key
/// `addFixedCategory`) instead of the heading and chips; nothing to choose.
class CategorySection extends StatelessWidget {
  const CategorySection({
    super.key,
    required this.db,
    required this.fixed,
    required this.fixedLabel,
    required this.sourceType,
    required this.counterpartyKey,
    required this.counterpartyDisplayName,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
    required this.autoApplyChecked,
    required this.onAutoApplyChanged,
    this.tourKey,
  });

  final Database db;

  /// True for Withdrawal and Airtime (the built-in, locked category).
  final bool fixed;
  final String fixedLabel;
  final String sourceType;
  final String counterpartyKey;
  final String counterpartyDisplayName;
  final int? selectedId;
  final String? selectedName;
  final void Function(int id, String name) onSelected;
  final bool autoApplyChecked;
  final ValueChanged<bool> onAutoApplyChanged;
  final GlobalKey? tourKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        if (!fixed) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: palette.ink)),
          ),
          const SizedBox(height: 8),
        ],
        KeyedSubtree(
          key: tourKey,
          child: fixed
              ? Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                  child: Text(
                    'Category: ${selectedName ?? fixedLabel}',
                    key: const Key('addFixedCategory'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.mutedInk),
                  ),
                )
              : CategoryChips(
                  db: db,
                  sourceType: sourceType,
                  counterpartyKey: counterpartyKey,
                  counterpartyDisplayName: counterpartyDisplayName,
                  selectedId: selectedId,
                  selectedName: selectedName,
                  onSelected: onSelected,
                  autoApplyChecked: autoApplyChecked,
                  onAutoApplyChanged: onAutoApplyChanged,
                ),
        ),
      ],
    );
  }
}
