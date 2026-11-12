/// §AUTOREAD.AIRTIME_AUTO_UI — the "Auto-record airtime" switch card and the
/// "Recorded automatically" trail (0.2.0 S6; mock `notifications.js` autoAir /
/// recorded row). Autoread flavor only. Data and rules live in
/// `logic/airtime_auto.dart`; this file draws and forwards taps.
library;

import 'package:flutter/material.dart';

import '../../domain/format/money.dart';
import '../../ui/screens/notifications/news_row.dart';
import '../../ui/theme/app_colors.dart';
import '../../ui/widgets/notif_colors.dart';
import '../../ui/widgets/notif_shape_icon.dart';
import '../logic/airtime_auto.dart';
import 'airtime_kind_copy.dart';

/// The opt-in card: one title and two independent switches, "For my number"
/// (existing preference) and "For another number" (new, default OFF). Soft
/// only; Hard is shown as "comes in a later version" (mock `mk-air-switch.html`).
/// Shown on a parsed Airtime row and under the trail.
class AutoAirtimeSwitchCard extends StatelessWidget {
  const AutoAirtimeSwitchCard({
    super.key,
    required this.on,
    required this.onChanged,
    this.onOther = false,
    this.onChangedOther,
  });

  /// For my number.
  final bool on;
  final ValueChanged<bool> onChanged;

  /// For another number.
  final bool onOther;
  final ValueChanged<bool>? onChangedOther;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final anyOn = on || onOther;
    return Container(
      key: const Key('autoAirtimeCard'),
      decoration: BoxDecoration(
        color: p.textCard,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(kAutoAirtimeTitle,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: p.ink)),
                const SizedBox(height: 2),
                Text(kAutoAirtimeBody + (anyOn ? kAutoAirtimeOnTail : kAutoAirtimeOffTail),
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: p.mutedInk)),
              ],
            ),
          ),
          _KindRow(
            switchKey: const Key('autoAirtimeSwitch'),
            label: kAirKindMyselfLabel,
            sub: kAirKindMyselfSub,
            value: on,
            onChanged: onChanged,
          ),
          _KindRow(
            switchKey: const Key('autoAirtimeSwitchOther'),
            label: kAirKindOtherLabel,
            sub: kAirKindOtherSub,
            value: onOther,
            onChanged: onChangedOther,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 6),
            child: Text(kAirKindHardLater,
                key: const Key('autoAirtimeHardLater'),
                style: TextStyle(fontSize: 11.5, height: 1.35, color: p.mutedInk)),
          ),
        ],
      ),
    );
  }
}

class _KindRow extends StatelessWidget {
  const _KindRow({
    required this.switchKey,
    required this.label,
    required this.sub,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String label;
  final String sub;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: p.ink)),
                  Text(sub, style: TextStyle(fontSize: 12, height: 1.35, color: p.mutedInk)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            toggled: value,
            label: '$kAutoAirtimeTitle, $label',
            child: Switch(key: switchKey, value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}

/// One auto-recorded entry: what was recorded, when, and Undo.
class AutoRecordedRow extends StatelessWidget {
  const AutoRecordedRow({super.key, required this.entry, required this.now, required this.onUndo});

  final AutoRecorded entry;
  final DateTime now;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final amount = kshTrim(entry.amountCents);
    final title = autoRecordedTitle(amount);
    final age = rowAgeText(entry.at, now);
    final String foot;
    final NotifRowAction? action;
    if (entry.undone) {
      foot = kAutoRecordedUndone;
      action = null;
    } else if (entry.undoFailed) {
      foot = kAutoRecordedUndoFailed;
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
      footText: foot,
      action: action,
      dimmed: entry.undone || entry.undoFailed,
      spokenLabel: '$kAutoRecordedHeading. $title. $foot.',
    );
  }
}
