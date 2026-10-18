/// §AUTOREAD.BELL — the bell's spoken label for the build with auto-read.
/// Phrases from `ui-rework/bell.html` (function `spoken`, the fourth-icon mode
/// the PM took): "N messages waiting for a category", "N messages ready to
/// parse". Counts above 99 are spoken "99 or more" (as on the Notifications page).
library;

String _n(int n) => n > 99 ? '99 or more' : '$n';

String _msgs(int n) => n == 1 ? 'message' : 'messages';

/// For example "Notifications, 1 update available, 3 messages waiting for a
/// category, 2 messages ready to parse, 1 new notice".
String bellSpokenLabelAutoRead({
  required bool update,
  required bool newNotice,
  required int readyToParse,
  required int waiting,
}) {
  final parts = <String>[
    if (update) '1 update available',
    if (waiting > 0) '${_n(waiting)} ${_msgs(waiting)} waiting for a category',
    if (readyToParse > 0) '${_n(readyToParse)} ${_msgs(readyToParse)} ready to parse',
    if (newNotice) '1 new notice',
  ];
  return parts.isEmpty ? 'Notifications' : 'Notifications, ${parts.join(', ')}';
}
