/// §AUTOREAD.AUTO_GROUP - "Recorded automatically": the trail rows (newest
/// first), each with Undo and the "Change in Settings" link. The two switches
/// live in Settings, on the Remembered page's second tab. Autoread build only.
library;

import 'package:flutter/material.dart';

import '../logic/airtime_auto.dart';
import 'auto_recorded_row.dart';
import 'row_parts.dart';

/// Hidden while the trail is empty. [onChangeInSettings] is the link on every
/// trail row, so it is required: the trail never shows without it.
class AutoGroup extends StatelessWidget {
  const AutoGroup(this.c, this.now, {super.key, required this.onChangeInSettings});
  final AirtimeAutoController c;
  final DateTime now;
  final VoidCallback onChangeInSettings;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final trail = c.trailNewestFirst;
          if (trail.isEmpty) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeading(kAutoRecordedHeading),
              for (final e in trail)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AutoRecordedRow(
                      entry: e, now: now, onUndo: () => c.onUndo(e), onChangeInSettings: onChangeInSettings),
                ),
            ],
          );
        },
      );
}
