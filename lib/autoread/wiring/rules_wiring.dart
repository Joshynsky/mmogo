/// §AUTOREAD.RULES_WIRING - joins the finished rule pieces to the running app (0.2.1: Suggested and Ask
/// first). `main.dart` calls [RulesWiring.install] once, inside `if (kAutoReadCompiled)`; it:
/// - builds the history reader (summary first, the live database read as a second chance), the history
///   summary writer, the offers list ([SuggestionsController]) and the ledger-event listener;
/// - sets `LevelsDeps.instance` (so Settings shows the Suggest rows and the Remembered page its second
///   tab lists people), with a real Suggest settings port and a "people with history" source;
/// - listens to the ledger hooks (add, edit, delete, restore, bulk) and to the "Record receiver
///   details" switch (OFF wipes the rules, the undone codes and the summary).
///
/// Everything is lazy (the database is opened by whoever asks first). Auto-read build only.
library;

import 'dart:async';

import 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

import '../../data/db/app_database.dart';
import '../../data/db/ledger_hooks.dart';
import '../../data/prefs/app_prefs.dart';
import '../data/all_category_choices.dart';
import '../data/known_people.dart';
import '../data/lazy_category_choices.dart';
import '../data/ledger_rule_events.dart';
import '../data/pending_items_store.dart';
import '../data/suggested_chips_source.dart';
import '../background/labelling_pending_store.dart';
import '../history/fallback_history_reader.dart';
import '../history/ffi_history_reader.dart';
import '../history/history_reader.dart';
import '../history/history_summary_writer.dart';
import '../history/rule_labeler.dart';
import '../history/summary_history_reader.dart';
import '../rules/prefs_suggest_settings.dart';
import '../rules/receiver_key.dart' show isRememberedPochi;
import '../runtime.dart';
import '../ui/levels/levels_deps.dart';
import '../ui/notifications/suggestions_controller.dart';

class RulesWiring {
  RulesWiring._();

  /// Where the wiring opens the ledger. The app's one database; a test swaps it for its own so no test can
  /// reach the real file.
  static Future<Database> Function() database = () => AppDatabase.instance.database;

  /// The history for the app's own screens and labelling: the summary the app keeps fresh first (cheap,
  /// no database open per person), then the live database read when there is no summary yet.
  static final HistoryReader appHistory = FallbackHistoryReader(SummaryHistoryReader(), FfiHistoryReader());

  /// The ledger -> preferences summary (rebuilt on open, record, undo, category change, restore).
  static final HistorySummaryWriter summary =
      HistorySummaryWriter(rows: () async => readHistoryRows(await database()));

  /// 0.2.2: the suggested chips of a waiting item, from the app's rules, history summary and details setting.
  static SuggestedChipsSource chipsSource() => SuggestedChipsSource(
        rules: AutoReadRuntime.ruleStore,
        history: appHistory,
        recordReceiverDetails: AppPrefs.readCaptureIdentityPreference,
      );

  /// The offers "Ask first next time?" (one list for the bell and the Notifications page).
  static SuggestionsController? suggestions;

  static LedgerRuleEvents? _events;
  static Future<void> _tail = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() op) {
    final run = _tail.then((_) => op());
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  static bool get installed => _events != null;

  /// Safe to call twice. Sets the hooks, [LevelsDeps.instance] and [suggestions].
  static void install() {
    if (installed) return;
    final controller = suggestions ??= SuggestionsController(engine: AutoReadRuntime.ruleEngine, store: AutoReadRuntime.ruleStore);
    final events = _events = LedgerRuleEvents(
      engine: AutoReadRuntime.ruleEngine,
      store: AutoReadRuntime.ruleStore,
      undone: AutoReadRuntime.undoneCodes,
      summary: summary,
      database: () => database(),
      detailsOn: AppPrefs.readCaptureIdentityPreference,
      pochiRemembered: (name) => isRememberedPochi(name),
    );
    LedgerHooks.onInserted = (id) => unawaited(_serial(() => events.inserted(id)));
    LedgerHooks.onEdited = (id) => unawaited(_serial(() => events.edited(id)));
    LedgerHooks.onRemoved = (id) => unawaited(_serial(() => events.removed(id)));
    LedgerHooks.onRestored = (id) => unawaited(_serial(() => events.ledgerChanged(id)));
    LedgerHooks.onBulk = () => unawaited(_serial(() => events.ledgerChanged()));
    AppPrefs.onCaptureIdentityWritten = (on) {
      if (!on) unawaited(_detailsOff());
    };
    LevelsDeps.instance = LevelsDeps(
      store: AutoReadRuntime.ruleStore,
      history: appHistory,
      categories: AllCategoryChoices(() => database()),
      categoriesFor: (t) => LazyCategoryChoices(() => database(), sourceTypeOfReceiver(t)),
      suggest: PrefsSuggestSettings(onChanged: () => unawaited(controller.refresh())),
      known: KnownPeopleSource(database: () => database(), detailsOn: AppPrefs.readCaptureIdentityPreference).call,
    );
  }

  /// Removes the hooks (tests, or a restart of the app object). Leaves the stored data alone.
  static void uninstall() {
    LedgerHooks.onInserted = null;
    LedgerHooks.onEdited = null;
    LedgerHooks.onRemoved = null;
    LedgerHooks.onRestored = null;
    LedgerHooks.onBulk = null;
    AppPrefs.onCaptureIdentityWritten = null;
    LevelsDeps.instance = null;
    suggestions?.dispose();
    suggestions = null;
    _events = null;
    _tail = Future<void>.value(); // a stuck earlier step must not block the next install
  }

  /// "Record receiver details" went OFF: no rule, undone code or summary may be kept.
  static Future<void> _detailsOff() => _serial(() async {
        await AutoReadRuntime.ruleGuard.wipe();
        await summary.clear();
        await suggestions?.refresh();
      });

  /// The app opened (or came back): the summary follows the ledger.
  static Future<void> rebuildSummary() => _serial(() async {
        await summary.rebuild(recordReceiverDetails: await AppPrefs.readCaptureIdentityPreference());
      });

  /// A Replace restore committed: every person goes back to Suggested (rules, undone codes and the old
  /// summary removed), then the summary is rebuilt from the restored ledger. A Merge restore never
  /// calls this (it only rebuilds the summary, through the bulk hook).
  static Future<void> afterReplaceRestore() => _serial(() async {
        await AutoReadRuntime.ruleGuard.afterReplaceRestore();
        await summary.rebuild(recordReceiverDetails: await AppPrefs.readCaptureIdentityPreference());
        await suggestions?.refresh();
      });

  /// The after-Replace-restore hook main installs: it CHAINS what was there ([prior]), empties the
  /// shown airtime trail ([clearTrail]) and sends every person back to Suggested. Never overwrites.
  static void Function() restoreHook({void Function()? prior, required void Function() clearTrail}) => () {
        try {
          prior?.call();
        } catch (_) {}
        try {
          clearTrail();
        } catch (_) {}
        unawaited(afterReplaceRestore());
      };

  /// Delete data finished: the summary is already wiped with the rules; nothing is rebuilt (no rows).
  static Future<void> afterDeleteData() => _serial(() async {
        await summary.clear();
        await suggestions?.refresh();
      });

  /// A store that labels what it saves (who, level, up to 2 categories) for the in-app Parse; the
  /// background engine builds its own labeller (it has no app objects).
  static PendingItemsStore labelling(PendingItemsStore inner) => LabellingPendingStore(
        inner,
        RuleLabeler(
          rules: AutoReadRuntime.ruleStore,
          history: appHistory,
          recordReceiverDetails: AppPrefs.readCaptureIdentityPreference,
        ),
      );
}
