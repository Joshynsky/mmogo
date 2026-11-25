/// §AUTOREAD.LEVELS.SEARCH: the search box of the Remembered page's second tab (layout A, 0.2.2 U5) and
/// the pure match rule: name, kind, the masked number (never the stored key) and category names, any case. While a
/// search text is present the folded sections open (levels_groups.dart).
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import 'hard_rule_copy.dart';
import 'levels_person_row.dart';

/// Whether [x] matches the search text [query] (trimmed, any case). An empty query matches everyone.
bool levelPersonMatches(LevelPerson x, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final hay = [
    x.name,
    receiverKindName(x.type),
    x.maskedNumber ?? '', // masked only: the stored key / full number is never matched (F2, no probing hidden digits)
    ...x.categoryNames,
  ].join('\n').toLowerCase();
  return hay.contains(q);
}

class LevelsSearchField extends StatelessWidget {
  const LevelsSearchField({super.key, required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: p.line, width: 1.5));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Semantics(
        textField: true,
        label: kHardSearchPlaceholder,
        child: TextField(
          key: const Key('levelsSearch'),
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 14, color: p.ink),
          decoration: InputDecoration(
            isDense: true,
            constraints: const BoxConstraints(minHeight: 44),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            hintText: kHardSearchPlaceholder,
            hintStyle: TextStyle(fontSize: 14, color: p.mutedInk),
            prefixIcon: Icon(Icons.search, size: 20, color: p.mutedInk),
            filled: true,
            fillColor: p.surface,
            border: border,
            enabledBorder: border,
            focusedBorder: border.copyWith(borderSide: BorderSide(color: p.primary, width: 2)),
          ),
        ),
      ),
    );
  }
}
