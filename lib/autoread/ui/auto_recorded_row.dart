/// §AUTOREAD.AUTO_RECORDED_ROW - one "Recorded automatically" trail row: what
/// was recorded, when, Undo, and the "Change in Settings" link. Autoread flavor
/// only. Data and rules live in `logic/airtime_auto.dart`; this file draws and
/// forwards taps.
library;

import 'package:flutter/material.dart';

import '../../domain/format/money.dart';
import '../../ui/screens/notifications/news_row.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/notif_colors.dart';
import '../../ui/widgets/notif_shape_icon.dart';
import '../logic/airtime_auto.dart';

/// One auto-recorded entry: what was recorded, when, and Undo.
class AutoRecordedRow extends StatelessWidget {
  const AutoRecordedRow({
    super.key,
    required this.entry,
    required this.now,
    required this.onUndo,
    this.onChangeInSettings,
  });

  final AutoRecorded entry;
  final DateTime now;
  final VoidCallback onUndo;

  /// Opens Settings on the auto-record switches. No link while null.
  final VoidCallback? onChangeInSettings;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amount = kshTrim(entry.amountCents);
    final party = entry.partyLabel;
    final category = entry.categoryName;
    final title = party != null ? '$party, $amount' : autoRecordedTitle(amount, other: entry.airtimeOther);
    final sub = category != null ? recordedAsSub(category) : kAutoRecordedSub;
    final age = rowAgeText(entry.at, now);
    final String foot;
    final NotifRowAction? action;
    if (entry.inRecentlyDeleted) {
      foot = kAutoRecordedUndone;
      action = null;
    } else {
      foot = '$age · $kAutoRecordedFoot';
      action = NotifRowAction(
        label: kAutoRecordedUndo,
        semantics: '$kAutoRecordedUndo: $title',
        onTap: onUndo,
      );
    }
    return NotifRowShell(
      key: Key('auto-recorded-${entry.rowId}'),
      icon: Icon(Icons.check_circle, size: 26, color: notifShapeColor(p, NotifShape.pill)),
      title: title,
      subtitle: sub,
      footText: foot,
      action: action,
      link: onChangeInSettings == null || party != null
          ? null
          : NotifRowAction(
              label: kAutoRecordedChangeInSettings,
              semantics: '$kAutoRecordedChangeInSettings: $title',
              onTap: onChangeInSettings!,
            ),
      dimmed: entry.inRecentlyDeleted,
      spokenLabel: '$title. $sub $foot.',
    );
  }
}
