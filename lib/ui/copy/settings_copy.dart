// §COPY.SETTINGS
// Words for the Settings page (0.1.2 S9a) and the Remembered recipients page.
// Where a line is marked PLACEHOLDER the PM signs the final words later.

const kSettingsTitle = 'Settings';

// ---- section labels (mock M9) ----
const kSettingsLookGroup = 'Look';
const kSettingsAddingGroup = 'Adding entries';
const kSettingsDataGroup = 'Your data';
const kSettingsCarefulTag = 'careful';
const kSettingsAboutGroup = 'About';

// ---- Look ----
const kPaletteTitle = 'Colour palette';
const kPaletteSubtitle = 'Recolours the whole app.';
const kAppearanceTitle = 'Appearance';

/// F4 (R20, PM): the Appearance caption follows the choice.
const kAppearanceCaptionSystem = 'Follows your phone’s setting.';
const kAppearanceCaptionLight = 'Always light.';
const kAppearanceCaptionDark = 'Always dark.';

/// `mode` is `system` | `light` | `dark`; anything else reads as System.
String appearanceCaption(String mode) => switch (mode) {
  'light' => kAppearanceCaptionLight,
  'dark' => kAppearanceCaptionDark,
  _ => kAppearanceCaptionSystem,
};

const kFirstDayTitle = 'First day of the week';

/// F4 (R16): shown ONLY in the First day dialog, not on the row.
const kFirstDayRegrouped = 'Past weeks are regrouped to match. No transactions change.';

/// F4 (R22): the toast after the day was changed (not when the same day is picked again).
String weeksNowStartOnText(String dayName) => 'Weeks now start on $dayName.';
const kWeeksToastDuration = Duration(seconds: 2);
const kFirstDayDefaultTag = 'Default';
const kFirstDayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const kMonthChartTitle = 'Month chart';
const kMonthChartLine = 'One bar per day or week.';
const kYearViewTitle = 'Year view';
const kYearViewLine = 'Quarter or month totals.';
const kShowWithdrawalsTitle = 'Show withdrawals in the chart';
const kShowWithdrawalsSubtitle =
    'Withdrawals are not counted as spending. Turn this on to see them in the chart as a separate pattern.';
const kWhereStyleTitle = 'Where it went style';
const kWhereStyleLine = 'Buttons or a strip.';

/// PLACEHOLDER (CB13, PM signs the final words). The mock's older line
/// ("Saved on this phone only. Set again after restoring a backup.") is stale.
const kLookNote = 'Appearance is saved on this phone only. The other choices here are kept in your backups.';

// ---- Adding entries ----
const kAutoRecognizeLabel = 'Auto-recognize categories';
const kAutoRecognizeSubtitle = 'Suggest a category for repeat senders and receivers while you add';
const kManageCategoriesLabel = 'Manage categories';
const kManageCategoriesSubtitle = 'Create, rename, delete and restore';
const kRememberedRowLabel = 'Remembered recipients';
const kRememberedRowSubtitle = 'Name and type, kept on this phone';

// ---- Remembered recipients page (mock remembered.html) ----
const kRememberedTitle = 'Remembered recipients';

/// F3 (R26): the ONE always-visible line under the title. The long intro and
/// the bold sentence moved into the "?" sheet below.
const kRememberedIntro = 'Kept on this phone only.';

/// F3 (R27): the "?" sheet. R25: the switch is named once, in general words
/// (the Add screen words it per type, so no exact switch name is quoted).
const kRememberedHelpTitle = 'About remembered names';
const kRememberedHelpParagraphs = [
  'We remember a name and its type (Send Money or Pochi) so we do not ask again.',
  'They are not in backups and are never shared.',
  'A remembered name stays until you forget it, even if you turn off the “Also record” switch on Add.',
];
const kRememberedEmptyTitle = 'Nothing remembered yet.';
const kRememberedEmptyBody = 'When a message has a name but no phone number, we ask once and can remember your answer.';
const kRememberedEmptyNote = 'Names are remembered only when the “Also record” switch on Add is on.';
const kForgetAll = 'Forget all';
const kForgetAllTitle = 'Forget all remembered recipients?';
const kForgetAllBody = 'We will ask again next time.';
const kForgetOne = 'Forget';
const kRememberedCancel = 'Cancel';

/// Counts only; a name never goes into a message (addition to the mock).
String forgotRecipientsText(int n) => 'Forgot $n recipient${n == 1 ? '' : 's'}';

/// Error pattern A line (no name in it).
const kRememberedCouldNot = 'Could not update the remembered recipients. Please try again.';
