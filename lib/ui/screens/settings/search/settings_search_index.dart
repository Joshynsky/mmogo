import '../../../copy/data_copy.dart';
import '../../../copy/delete_data_copy.dart';
import '../../../copy/other_version_copy.dart' show kOtherVersionSettingsLabel;
import '../../../copy/privacy_copy.dart';
import '../../../copy/settings_copy.dart';
import '../../fuliza/fuliza_visible.dart';
import 'settings_search_entry.dart';
import 'settings_search_matcher.dart';

/// Chips under the search field, in order. Each is a query; chips whose query finds nothing in this build are dropped.
const kSettingsSearchChips = ['Backup', 'Dark mode', 'Export', 'Delete', 'Auto-record', 'Alerts', 'Categories', 'Updates'];

const kSettingsSearchHint = 'Search settings';
const kSettingsSearchNothing = 'Nothing found. Try Backup or Alerts.';
const kSettingsSearchLabel = 'Search settings';
const kSettingsSearchBack = 'Close search';

/// The agreed order of Settings (decisions 26-11-2026). Ids are the scroll-and-pulse ids: each is the `id` of a
/// SettingsRowTarget on the page (a test checks every row on the page has an entry here).
const List<SettingsSearchEntry> _beforeAutoRead = [
  SettingsSearchEntry(id: 'look.palette', title: kPaletteTitle, sectionName: kSettingsLookGroup, keywords: ['colour', 'color', 'theme', 'recolour']),
  SettingsSearchEntry(id: 'look.appearance', title: kAppearanceTitle, sectionName: kSettingsLookGroup, keywords: ['dark', 'light', 'dark mode', 'night', 'theme', 'black', 'pure black', 'amoled', 'oled']),
  SettingsSearchEntry(id: 'look.firstDay', title: kFirstDayTitle, sectionName: kSettingsLookGroup, keywords: ['monday', 'sunday', 'week', 'start']),
  SettingsSearchEntry(id: 'look.monthChart', title: kMonthChartTitle, sectionName: kSettingsLookGroup, keywords: ['chart', 'bars', 'graph']),
  SettingsSearchEntry(id: 'look.yearView', title: kYearViewTitle, sectionName: kSettingsLookGroup, keywords: ['quarter', 'month', 'totals']),
  SettingsSearchEntry(id: 'look.withdrawals', title: kShowWithdrawalsTitle, sectionName: kSettingsLookGroup, keywords: ['withdraw', 'cash', 'chart']),
  SettingsSearchEntry(id: 'look.whereStyle', title: kWhereStyleTitle, sectionName: kSettingsLookGroup, keywords: ['buttons', 'strip', 'where it went']),
  SettingsSearchEntry(id: 'adding.autoRecognize', title: kAutoRecognizeLabel, sectionName: kSettingsAddingGroup, keywords: ['suggest', 'category', 'repeat']),
  SettingsSearchEntry(id: 'adding.receiver', title: kCaptureReceiverLabel, sectionName: kSettingsAddingGroup, keywords: ['name', 'phone', 'number', 'remember', 'remembered', 'recipient']),
  SettingsSearchEntry(id: 'adding.fuliza', title: kShowFulizaLabel, sectionName: kSettingsAddingGroup, keywords: ['fuliza', 'overdraft', 'loan'], requiresFuliza: true),
  SettingsSearchEntry(id: 'adding.categories', title: kManageCategoriesLabel, sectionName: kSettingsAddingGroup, keywords: ['create', 'rename', 'restore', 'categories']),
  SettingsSearchEntry(id: 'adding.remembered', title: kRememberedRowLabel, sectionName: kSettingsAddingGroup, keywords: ['names', 'receivers', 'forget', 'remember'], standardOnly: true),
];

/// Your data and About: always after the Auto-read rows (Reading messages, Auto-record).
const List<SettingsSearchEntry> _afterAutoRead = [
  SettingsSearchEntry(id: 'data.backup', title: kPrivacyBackupRowTitle, sectionName: kSettingsDataGroup, keywords: ['backup', 'restore', 'save', 'copy', 'import']),
  SettingsSearchEntry(id: 'data.csv', title: kExportCsvLabel, sectionName: kSettingsDataGroup, keywords: ['csv', 'export', 'spreadsheet', 'excel', 'download']),
  SettingsSearchEntry(id: 'data.recentlyDeleted', title: kRecentlyDeletedLabel, sectionName: kSettingsDataGroup, keywords: ['bin', 'trash', 'undo', 'restore']),
  SettingsSearchEntry(id: 'data.delete', title: kDeleteDataTitle, sectionName: kSettingsDataGroup, keywords: ['delete', 'remove', 'reset', 'clear', 'careful']),
  SettingsSearchEntry(id: 'about.privacy', title: kPrivacyTitle, sectionName: kSettingsAboutGroup, keywords: ['privacy', 'data', 'safe']),
  SettingsSearchEntry(id: 'about.updates', title: kUpdatesTitle, sectionName: kSettingsAboutGroup, keywords: ['update', 'new', 'version', 'whats new']),
  SettingsSearchEntry(id: 'about.otherVersion', title: kOtherVersionSettingsLabel, sectionName: kSettingsAboutGroup, keywords: ['auto-read', 'autoread', 'download', 'website'], standardOnly: true),
  SettingsSearchEntry(id: 'about.feedback', title: kSendFeedbackLabel, sectionName: kSettingsAboutGroup, keywords: ['feedback', 'contact', 'report', 'bug', 'email']),
];

/// The index for this build: Auto-read rows are dropped in the standard build, standard-only rows in the Auto-read build,
/// and Show Fuliza while Fuliza is hidden.
class SettingsSearchIndex {
  const SettingsSearchIndex._();

  /// The Auto-read rows (Reading messages, Auto-record), set by the auto-read wiring only
  /// (lib/autoread/ui/settings/settings_search_autoread_rows.dart). The standard build never sets it, so
  /// none of those row names are in the standard binary.
  static List<SettingsSearchEntry> Function()? autoReadRows;

  /// All entries in Settings order, for the given build ([autoRead] defaults to "the auto-read wiring is installed").
  static List<SettingsSearchEntry> entries({bool? autoRead}) {
    final on = autoRead ?? autoReadRows != null;
    return [
      for (final e in _beforeAutoRead)
        if ((!on || !e.standardOnly) && (fulizaVisible || !e.requiresFuliza)) e,
      if (on && autoReadRows != null) ...autoReadRows!(),
      for (final e in _afterAutoRead)
        if ((!on || !e.standardOnly) && (fulizaVisible || !e.requiresFuliza)) e,
    ];
  }

  /// Chips whose query still finds something in this build.
  static List<String> chips({bool? autoRead}) {
    final list = entries(autoRead: autoRead);
    return [for (final c in kSettingsSearchChips) if (matchSettingsSearch(c, list).isNotEmpty) c];
  }
}
