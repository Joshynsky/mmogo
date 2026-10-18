/// The shared words of the Notifications page (news side), taken from the
/// signed mock `notifications.html`. Shared by both flavors.
library;

const kNotificationsTitle = 'Notifications';

// Chip names shared by both flavors.
const kChipAll = 'All';
const kChipNews = 'News';

const kNewsHeading = 'News';

/// "News (3)": the count is the unread count, already capped (`capCount`).
String newsHeadingWithCount(String cappedCount) => '$kNewsHeading ($cappedCount)';

// Unread | Read switch.
const kNewsSwitchUnread = 'Unread';
const kNewsSwitchRead = 'Read';
const kNewsSwitchLabel = 'Show unread or read news';

// Empty states: title, then body.
const kNewsEmptyUnreadTitle = 'No unread news';
const kNewsEmptyUnreadBody = 'No new notices or updates right now. Read ones are under Read.';
const kNewsEmptyReadTitle = 'No read news';
const kNewsEmptyReadBody = 'Items you have read stay here for 30 days.';

// Spoken prefixes of a row.
const kSpokenNewNotice = 'New notice';
const kSpokenUpdateAvailable = 'Update available';
const kSpokenNewWhatsNew = 'New, what’s new';
const kSpokenReadNotice = 'Read notice';
const kSpokenReadUpdate = 'Read, update available';
const kSpokenReadWhatsNew = 'Read, what’s new';

// Row links and the age-line suffix of a read row.
const kNewsActionRead = 'Read';
const kNewsActionUpdate = 'Update';
const kNewsActionDismiss = 'Dismiss';
const kNewsActionRemove = 'Remove';
const kNewsAgeReadSuffix = ' · Read';

// Toasts after Dismiss and Remove.
const kNewsToastDismissed = 'Dismissed.';
const kNewsToastRemoved = 'Removed.';

// Update rows.
const kUpdateRowTitle = 'An update is available';
const kWhatsNewRowTitle = 'What’s new in this update';

/// Every string above, for the copy test.
const kNotificationsCopyAll = <String>[
  kNotificationsTitle,
  kChipAll,
  kChipNews,
  kNewsHeading,
  kNewsSwitchUnread,
  kNewsSwitchRead,
  kNewsSwitchLabel,
  kNewsEmptyUnreadTitle,
  kNewsEmptyUnreadBody,
  kNewsEmptyReadTitle,
  kNewsEmptyReadBody,
  kSpokenNewNotice,
  kSpokenUpdateAvailable,
  kSpokenNewWhatsNew,
  kSpokenReadNotice,
  kSpokenReadUpdate,
  kSpokenReadWhatsNew,
  kNewsActionRead,
  kNewsActionUpdate,
  kNewsActionDismiss,
  kNewsActionRemove,
  kNewsAgeReadSuffix,
  kNewsToastDismissed,
  kNewsToastRemoved,
  kUpdateRowTitle,
  kWhatsNewRowTitle,
];
