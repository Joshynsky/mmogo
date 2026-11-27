/// §AUTOREAD.SETTINGS.SEARCH_ROWS - the Settings search entries for Reading messages and Auto-record (auto-read build
/// only). The standard build never installs them, so their names stay out of the standard binary.
library;

import '../../../ui/copy/settings_copy.dart';
import '../../../ui/screens/settings/search/settings_search_entry.dart';
import '../../../ui/screens/settings/search/settings_search_index.dart';
import '../alert_minutes_dialog.dart' show kAlertMinutesLabel;
import '../levels/hard_rule_copy.dart' show kHardPauseSettingsTitle;
import '../levels/levels_copy.dart' show kSuggestAfterLabel, kSuggestSwitchLabel;
import '../settings_autoread_copy.dart'
    show kAlertsLabel, kDeleteHeldLabel, kHelpRowLabel, kParseLabel, kReadLabel, kReadingSectionLabel;

const List<SettingsSearchEntry> _autoReadRows = [
  SettingsSearchEntry(id: 'reading.read', title: kReadLabel, sectionName: kReadingSectionLabel, keywords: ['sms', 'notification', 'on', 'off', 'turn on', 'permission'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'reading.parse', title: kParseLabel, sectionName: kReadingSectionLabel, keywords: ['notification', 'parse'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'reading.alerts', title: kAlertsLabel, sectionName: kReadingSectionLabel, keywords: ['alerts', 'alert', 'notification', 'privacy', 'details'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'reading.hide', title: kAlertMinutesLabel, sectionName: kReadingSectionLabel, keywords: ['minutes', 'alerts', 'hide', 'lock screen'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'reading.trouble', title: kHelpRowLabel, sectionName: kReadingSectionLabel, keywords: ['help', 'problem', 'restricted', 'cannot', 'permission'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'reading.deleteHeld', title: kDeleteHeldLabel, sectionName: kReadingSectionLabel, keywords: ['held', 'waiting', 'clear'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'auto.people', title: kPeopleRowLabel, sectionName: kSettingsAutoRecordGroup, keywords: ['auto-record', 'rules', 'remembered', 'keep'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'auto.pause', title: kHardPauseSettingsTitle, sectionName: kSettingsAutoRecordGroup, keywords: ['pause', 'stop', 'hold'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'auto.askFirst', title: kSuggestSwitchLabel, sectionName: kSettingsAutoRecordGroup, keywords: ['ask', 'offer', 'suggest'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'auto.afterN', title: kSuggestAfterLabel, sectionName: kSettingsAutoRecordGroup, keywords: ['offer', 'in a row', 'times', 'repeat'], requiresAutoRead: true),
  SettingsSearchEntry(id: 'auto.airtime', title: kAirtimeSwitchesSearchTitle, sectionName: kSettingsAutoRecordGroup, keywords: ['airtime', 'data bundles', 'fuliza', 'bundle'], requiresAutoRead: true),
];

/// Registers the rows with the search index (the auto-read wiring calls this once at start).
void installSettingsSearchRows() => SettingsSearchIndex.autoReadRows = () => _autoReadRows;

/// Removes them again (tests; the standard build never installs them).
void uninstallSettingsSearchRows() => SettingsSearchIndex.autoReadRows = null;
