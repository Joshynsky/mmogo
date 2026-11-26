/// §AUTOREAD.RECORDED_AUTO_SECTION - "Recently recorded" (0.2.2 F-5, signed kHardRecentlyRecorded; was
/// "Recorded automatically"): ONE list of the 24 h trail rows (newest first) - airtime auto-records,
/// chip records and Ask first Yes rows - with Undo and the "Change in Settings" link. Hidden while
/// [entries] is empty. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../../logic/airtime_auto.dart';
import '../auto_recorded_row.dart';
import '../levels/hard_rule_copy.dart' show kHardRecentlyRecorded;
import '../row_parts.dart';

class RecordedAutoSection extends StatelessWidget {
  const RecordedAutoSection({super.key, required this.entries, required this.now, required this.onUndo, required this.onChangeInSettings});
  final List<AutoRecorded> entries;
  final DateTime now;
  final void Function(AutoRecorded entry) onUndo;
  final VoidCallback onChangeInSettings;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    // N6: the count is the entries still recorded; undone rows stay listed (dimmed) but are not counted.
    final active = entries.where((e) => !e.inRecentlyDeleted).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(active == 0 ? kHardRecentlyRecorded : '$kHardRecentlyRecorded ($active)'),
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AutoRecordedRow(entry: e, now: now, onUndo: () => onUndo(e), onChangeInSettings: onChangeInSettings),
          ),
      ],
    );
  }
}
