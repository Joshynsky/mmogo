/// §AUTOREAD.COPY — every auto-read string of the signed Notifications page.
/// Verbatim from `ui-rework/notifications.html` and `notifications-notes.md`
/// unless marked NOT IN MOCK. No hour count is typed here: the held window
/// copy comes from `held_window.dart`.
library;

import '../held_window.dart';

// Chips: visible names and the full spoken names.
const String kChipParse = 'Parse';
const String kChipCategorize = 'Categorize';

/// Heading of the two groups (full words).
const String kHeadingToParse = 'To parse';
const String kHeadingToCategorize = 'To categorize';

String _spokenCount(int n) => n == 0 ? 'none' : (n > 99 ? '99 or more' : '$n');

/// "To parse, N" (N spoken: "none", "99 or more").
String parseChipSpoken(int n) => '$kHeadingToParse, ${_spokenCount(n)}';

/// "To categorize, N".
String categorizeChipSpoken(int n) => '$kHeadingToCategorize, ${_spokenCount(n)}';

// Row actions.
const String kActionParse = 'Parse';
const String kActionPaste = 'Paste';
const String kActionCategorize = 'Categorize';
const String kActionRemove = 'Remove';

// Row texts.
const String kReadyRowTitle = 'M-Pesa message ready';
const String kWaitingNotCounted =
    'Waiting items are not counted in your totals until you categorize them.';
const String kCouldNotRead = 'Could not read this one. Paste it instead.';
const String kGoneLine = 'This message is no longer available. Paste it instead.';

/// NOT IN MOCK (the Judge requires the gone copy to name the recovery).
const String kGoneRecovery =
    'Find the message in your phone’s Messages, copy it, then paste it in Add.';

/// NOT IN MOCK: the mock's gone footer still names an old hour count; none typed.
const String kGoneFooter = 'Expired';

/// "expires in N h" (or "under 1 h") for a readable ready row; [hours] comes
/// from `expiresInHours`, [underOneHour] from `expiresUnderOneHour`.
String expiresInLine({required int hours, required bool underOneHour}) =>
    'expires in ${underOneHour ? 'under 1 h' : '$hours h'}';

/// The quiet line for the held window, built from the constant.
String get kHeldWindowLine => kHeldWindowCopy;

// Remove confirmation (unreadable and gone rows).
const String kRemoveTitle = 'Remove this message?';
const String kRemoveBody =
    'The message stays in your phone’s Messages. You can paste it again.';
const String kRemoveCancel = 'Cancel';
const String kRemoveConfirm = 'Remove';

// Paste sheet.
const String kPasteSheetHeading = 'Copy the M-Pesa message first, then continue to Add.';
const String kPasteContinue = 'Continue to Add';
const String kPasteGoStraight = 'Already copied it? Go straight to Add.';

/// Flagged row line, from the brief (the mock's box says "Check this one."
/// plus a longer sentence).
const String kFlaggedLine = 'same code, different details, check your M-Pesa message';

/// The signed interim wording for forged messages (Judge condition 4); NOT IN
/// MOCK.
const String kFromMessageTextOnly =
    'From the message text only. mmogo cannot check it with M-Pesa.';

// Empty states (mock).
const String kEmptyParseTitle = 'Nothing to parse';
const String kEmptyParseBody = 'No M-Pesa messages are ready to parse.';
const String kEmptyCategorizeTitle = 'Nothing is waiting';
const String kEmptyCategorizeBody = 'Nothing is waiting for a category.';

// Toasts (mock).
const String kToastParsed = 'Parsed. It is now in To categorize. Nothing is saved yet.';
const String kToastRemoved =
    'Removed. The message stays in your phone’s Messages. You can paste it again.';

/// Every string above, for the banned-phrase test.
List<String> allAutoReadCopy() => [
      kChipParse,
      kChipCategorize,
      kHeadingToParse,
      kHeadingToCategorize,
      parseChipSpoken(3),
      categorizeChipSpoken(0),
      categorizeChipSpoken(120),
      kActionParse,
      kActionPaste,
      kActionCategorize,
      kActionRemove,
      kReadyRowTitle,
      kWaitingNotCounted,
      kCouldNotRead,
      kGoneLine,
      kGoneRecovery,
      kGoneFooter,
      expiresInLine(hours: 4, underOneHour: false),
      expiresInLine(hours: 1, underOneHour: true),
      kHeldWindowLine,
      kRemoveTitle,
      kRemoveBody,
      kRemoveCancel,
      kRemoveConfirm,
      kPasteSheetHeading,
      kPasteContinue,
      kPasteGoStraight,
      kFlaggedLine,
      kFromMessageTextOnly,
      kEmptyParseTitle,
      kEmptyParseBody,
      kEmptyCategorizeTitle,
      kEmptyCategorizeBody,
      kToastParsed,
      kToastRemoved,
    ];
