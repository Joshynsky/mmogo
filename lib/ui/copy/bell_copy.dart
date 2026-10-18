/// The bell's spoken label for the standard build (strings from
/// `ui-rework/bell.html`, function `spoken`).
library;

/// "Notifications" plus each kind that is present, for example
/// "Notifications, 1 update available, 1 new notice". Nothing present gives
/// just "Notifications".
String bellSpokenLabel({required bool update, required bool newNotice}) {
  final parts = <String>[
    if (update) '1 update available',
    if (newNotice) '1 new notice',
  ];
  return parts.isEmpty ? 'Notifications' : 'Notifications, ${parts.join(', ')}';
}
