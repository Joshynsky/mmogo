/// The words of the "Other version of mmogo" pieces (standard build only): the
/// one-time bell notice, its permanent place in Notifications, and the
/// Settings > About row. The body sentence is ONE constant so the notice and the
/// row can never drift. "SMS permission" is plain user text; nothing else here
/// names the second version's parts.
library;

/// The sentence both places end with.
const kOtherVersionPermissionSentence = 'It asks for SMS permission, so it is separate and optional.';

const kOtherVersionNoticeTitle = 'Another version of mmogo';
const kOtherVersionNoticeBody =
    'You have the standard version of mmogo. There is a second version that can read and parse '
    'your M\u2011Pesa messages for you. $kOtherVersionPermissionSentence';
const kOtherVersionNoticeAction = 'See what it does';

/// What a screen reader says for the action (the link opens the browser).
const kOtherVersionNoticeActionSpoken = 'See what it does. Opens the mmogo web page in your browser.';

const kOtherVersionSettingsLabel = 'Other version of mmogo';
const kOtherVersionSettingsSubtitle =
    'A second version can read and parse your M\u2011Pesa messages. $kOtherVersionPermissionSentence';

/// Shown when the browser could not be opened.
const kOtherVersionCouldNotOpen = 'Could not open the browser.';
