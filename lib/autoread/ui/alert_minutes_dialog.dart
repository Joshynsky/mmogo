/// §AUTOREAD.UI.ALERT_MINUTES (0.2.1 slice 12): the "Hide details after"
/// choice: its words and the picker dialog. The row sits in the Reading card
/// (reading_settings_section.dart) and shows only while "What alerts show" is
/// Show details. The choice is for the alert on screen only; how long a held
/// message is kept (kHeldWindow) never changes. Autoread flavor only.
library;

import 'package:flutter/material.dart';

import '../logic/reading_controller.dart';

// WORDING-DRAFT: the row title and the dialog title (PM 19-11-2026).
const String kAlertMinutesLabel = 'Hide details after';

// WORDING-DRAFT: the line under the dialog's choices.
const String kAlertMinutesNote = 'Only the details in the alert go away. The message stays in the list as before.';

/// "Never", "5 minutes", "15 minutes", "30 minutes", "1 hour".
// WORDING-DRAFT: the words of each choice.
String alertMinutesText(int minutes) => switch (minutes) {
      kAlertMinutesNever => 'Never',
      60 => '1 hour',
      _ => '$minutes minutes',
    };

/// Every word this file adds, for the wording check.
List<String> allAlertMinutesCopy() => [
      kAlertMinutesLabel,
      kAlertMinutesNote,
      for (final m in kAlertMinutesChoices) alertMinutesText(m),
    ];

/// Shows the picker; answers the minutes picked, or null when dismissed.
Future<int?> showAlertMinutesDialog(BuildContext context, int current) => showDialog<int>(
      context: context,
      builder: (_) => AlertMinutesDialog(current: current),
    );

class AlertMinutesDialog extends StatelessWidget {
  const AlertMinutesDialog({super.key, required this.current});
  final int current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return SimpleDialog(
      title: const Text(kAlertMinutesLabel),
      children: [
        for (final m in kAlertMinutesChoices)
          SimpleDialogOption(
            key: Key('alertMinutes-$m'),
            onPressed: () => Navigator.of(context).pop(m),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Icon(current == m ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  const SizedBox(width: 12),
                  Expanded(child: Text(alertMinutesText(m), style: theme.titleSmall)),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Text(kAlertMinutesNote, style: theme.bodySmall),
        ),
      ],
    );
  }
}
