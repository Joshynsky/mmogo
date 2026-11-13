/// §AUTOREAD.PRIVACY_COPY - the Privacy page's words that exist only in the
/// auto-read build. The Privacy page reaches this file only when it is built
/// for the auto-read version.
library;

/// SIGNED (PM 13-11-2026): the Privacy page sentence for the description of a
/// held message. Shown in the auto-read build only.
const String kPrivacyHeldDescription =
    'To show what a held message is, the app reads it on this phone. The description shows only what kind of '
    'message it looks like, its amount, time and code, and for a payment, who it was to. It is kept on screen '
    'only, never saved, never put in a notification and never sent anywhere. It is forgotten when you leave the '
    'page or close the app. A message the app cannot read shows only its code, amount and time. The held message '
    'itself stays on your phone for up to 24 hours, as before.';

/// SIGNED (PM 13-11-2026): the Privacy page sentence for messages the app keeps
/// for a feature that is not shown yet. Shown in the auto-read build only (the
/// only build that reads messages).
const String kPrivacyKeptNotShown =
    'mmogo keeps some messages from your mobile-money provider on this phone for a feature that is not shown yet; '
    'nothing is shown from them and they are never sent anywhere.';

/// SIGNED (PM 13-11-2026): the Privacy page sentence for the 24 h "Recorded
/// automatically" list (row numbers and times kept for 24 hours). Shown in the
/// auto-read build only.
const String kPrivacyAutoRecordedTrail =
    'For 24 hours mmogo remembers which airtime entries it recorded for you, so you can see and undo them. '
    'This list stays on your phone, is not in backups, and Delete data removes it.';
