import 'package:flutter/material.dart';

import '../../../domain/paid_to/paid_to.dart';
import '../../theme/app_colors.dart';
import '../../widgets/removable_chip.dart';
import '../analytics_screen.dart' show analyticsPickerTheme;

/// §PAIDTO.SEARCH — the Search field + Filter button, and the removable active-filter chips.
class PaidToSearchRow extends StatelessWidget {
  const PaidToSearchRow({
    super.key,
    required this.palette,
    required this.controller,
    required this.activeFilters,
    required this.onChanged,
    required this.onFilter,
  });

  final AppPalette palette;
  final TextEditingController controller;

  /// Badge on the Filter button (category + non-default sort).
  final int activeFilters;
  final VoidCallback onChanged;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(12));
    final active = activeFilters;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: c, width: 1.5),
    );
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: Theme(
              data: analyticsPickerTheme(palette),
              child: TextField(
                key: const Key('paidToSearch'),
                controller: controller,
                onChanged: (_) => onChanged(),
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 13, color: palette.ink),
                decoration: InputDecoration(
                  hintText: 'Search',
                  semanticCounterText: '',
                  hintStyle: TextStyle(fontSize: 13, color: palette.mutedInk),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: palette.mutedInk),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  isDense: true,
                  filled: true,
                  fillColor: palette.card,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: border(palette.line),
                  focusedBorder: border(palette.primary),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: active == 0 ? 'Filter and sort' : 'Filter and sort, $active active',
          excludeSemantics: true,
          child: Material(
            color: palette.card,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: BorderSide(color: active > 0 ? palette.primary : palette.line, width: 1.5),
            ),
            child: InkWell(
              key: const Key('paidToFilterButton'),
              customBorder: const RoundedRectangleBorder(borderRadius: radius),
              onTap: onFilter,
              child: SizedBox(
                height: 40,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list_rounded, size: 16, color: active > 0 ? palette.primary : palette.ink),
                      const SizedBox(width: 6),
                      Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: active > 0 ? palette.primary : palette.ink,
                        ),
                      ),
                      if (active > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          key: const Key('paidToFilterBadge'),
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: palette.primary,
                            borderRadius: const BorderRadius.all(Radius.circular(9)),
                          ),
                          child: Text(
                            '$active',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: palette.onPrimary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The active filters as removable chips (category, non-default sort). The
/// shell builds it only when at least one filter is active.
class PaidToActiveChips extends StatelessWidget {
  const PaidToActiveChips({
    super.key,
    required this.palette,
    required this.cls,
    required this.sort,
    required this.onClearCategory,
    required this.onClearSort,
  });

  final AppPalette palette;
  final String? cls;
  final PaidToSort sort;
  final VoidCallback onClearCategory;
  final VoidCallback onClearSort;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (cls != null)
        RemovableChip(
          key: const Key('paidToChipCategory'),
          palette: palette,
          label: cls!,
          semanticsLabel: 'Category $cls. Remove',
          onTap: onClearCategory,
        ),
      if (sort != PaidToSort.amount)
        RemovableChip(
          key: const Key('paidToChipSort'),
          palette: palette,
          label: 'Sorted: ${paidToSortLabels[sort]}',
          semanticsLabel: 'Sorted by ${paidToSortLabels[sort]}. Remove',
          onTap: onClearSort,
        ),
    ];
    return Wrap(spacing: 6, runSpacing: 6, children: chips);
  }
}
