/// §AUTOREAD.LEVELS.SEARCH: the search box and the pure match rules. 0.2.2 item 2 redesign (U-SETUP, reversal 3):
/// search left the Remembered page and moved into the Set up sheet ([setupRecipientMatches], [LevelsSearchField]).
/// F2 kept: a search never matches hidden digits. The Set up rule matches the shown name only (the port has no
/// categories; the stored key, which is the full phone number for Send Money, is never matched).
/// [levelPersonMatches] is the old page rule (name, kind, masked number, category names); no screen uses it
/// since U-PAGE (I2 may delete it with its test in levels_layout_a_pure_test.dart).
library;

import 'package:flutter/material.dart';

import '../../../ui/theme/app_colors.dart';
import 'hard_rule_copy.dart';
import 'levels_person_row.dart';
import 'setup_ports.dart';

/// Whether the Set up row [r] matches the search text [query] (trimmed, any case): the shown name only. An empty
/// query matches everyone. Never [SetupRecipient.key] (F2: typing a phone number finds nothing; only digits
/// already shown in a masked name can match).
bool setupRecipientMatches(SetupRecipient r, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return r.displayName.toLowerCase().contains(q);
}

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

/// The search box (a pill field, 44 px high). [hint] is also its spoken name.
class LevelsSearchField extends StatelessWidget {
  const LevelsSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hint = kHardSearchPlaceholder,
    this.fieldKey = const Key('levelsSearch'),
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final Key fieldKey;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide(color: p.line, width: 1.5));
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Semantics(
        textField: true,
        label: hint,
        child: TextField(
          key: fieldKey,
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 14, color: p.ink),
          decoration: InputDecoration(
            isDense: true,
            constraints: const BoxConstraints(minHeight: 44),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            hintText: hint,
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
