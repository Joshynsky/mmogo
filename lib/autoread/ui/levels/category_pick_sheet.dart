/// §AUTOREAD.LEVELS.CATEGORY_PICK_SHEET: the small bottom sheet behind the level
/// sheet's "Choose a category" row. It lists the categories it is given (the
/// person's own group only, see LevelsDeps.choicesFor), marks the current one,
/// and scrolls inside a compact frame with the title pinned. A tap on a row
/// returns that category's id.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import '../category_choices.dart';
import 'levels_copy.dart';

/// Opens the picker; null when closed without a choice.
Future<int?> showCategoryPickSheet(BuildContext context, {required List<CategoryChoice> categories, int? selected}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CategoryPickSheet(categories: categories, selected: selected),
  );
}

class CategoryPickSheet extends StatelessWidget {
  const CategoryPickSheet({super.key, required this.categories, this.selected});
  final List<CategoryChoice> categories;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final h = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.min(h * 0.6, h - MediaQuery.viewInsetsOf(context).bottom - 8)),
      child: Container(
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 30, offset: Offset(0, -8))],
        ),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Semantics(
                header: true,
                child: Text(kCategoryPickTitle,
                    key: const Key('categoryPickTitle'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: p.ink)),
              ),
            ),
            Flexible(
              child: categories.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                      child: Text(kLevelSheetNoCategories, style: TextStyle(fontSize: 13, color: p.mutedInk)),
                    )
                  : ListView(
                      key: const Key('categoryPickList'),
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        for (final c in categories)
                          if (int.tryParse(c.id) != null) _row(context, p, c),
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, AppPalette p, CategoryChoice c) {
    final id = int.parse(c.id);
    final on = selected == id;
    return Semantics(
      button: true,
      selected: on,
      label: c.name,
      excludeSemantics: true,
      onTap: () => Navigator.of(context).pop(id),
      child: InkWell(
        key: Key('levelCat.$id'),
        onTap: () => Navigator.of(context).pop(id),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          color: on ? p.tint : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(
              child: Text(c.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? p.tintInk : p.ink)),
            ),
            if (on) Icon(Icons.check, size: 20, color: p.tintInk),
          ]),
        ),
      ),
    );
  }
}
