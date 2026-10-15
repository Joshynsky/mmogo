import 'package:flutter/material.dart';

import '../../../data/prefs/recipient_memory.dart';
import '../../../domain/parsing/parsed_sms_fields.dart';
import '../../theme/app_colors.dart';
import '../../widgets/tap_target.dart';

/// §ADD.RECIPIENT_CHOOSER — 0.1.2 S8c-2 (NO4, mock `chooser()`). While typing in
/// the Name field of Send Money or Pochi, remembered names appear under the
/// field; tapping one fills the Name and switches the pill to its remembered
/// type. Names show here by design (name and type only); they never go in a
/// snackbar, error text, log or widget key.

const int kRecipientChooserMax = 4;

String recipientTypeName(SmsSourceType t) => t == SmsSourceType.pochi ? 'Pochi' : 'Send Money';

/// The entries to show: case-insensitive "contains" on what is typed, newest
/// first as [all] already is, an exact name + same type match hidden, at most 4.
/// [all] is the whole remembered list, loaded once when typing starts.
List<RecipientEntry> recipientChooserEntries(
  List<RecipientEntry> all, {
  required String typed,
  required SmsSourceType currentType,
}) {
  final q = typed.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final out = <RecipientEntry>[];
  for (final e in all) {
    final k = e.key.toLowerCase();
    if (!k.contains(q)) continue;
    if (k == q && e.rule.type == currentType) continue;
    out.add(e);
    if (out.length == kRecipientChooserMax) break;
  }
  return out;
}

/// "Type changed to Pochi, because NAME is remembered as Pochi." (the mock).
String recipientTypeChangedText(String name, SmsSourceType t) =>
    'Type changed to ${recipientTypeName(t)}, because $name is remembered as ${recipientTypeName(t)}.';

class RecipientChooser extends StatelessWidget {
  const RecipientChooser({super.key, required this.entries, required this.onPick, this.note = ''});

  final List<RecipientEntry> entries;
  final ValueChanged<RecipientEntry> onPick;

  /// The plain status line after a tap switched the type; empty = nothing.
  final String note;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          Divider(height: 1, color: palette.line),
          InkWell(
            key: Key('addChooserItem_$i'),
            onTap: () => onPick(entries[i]),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(entries[i].key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.ink)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      recipientTypeName(entries[i].rule.type),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: palette.mutedInk),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                note,
                key: const Key('addChooserNote'),
                style: TextStyle(fontSize: 12, height: 1.45, color: palette.mutedInk),
              ),
            ),
          ),
      ],
    );
  }
}
