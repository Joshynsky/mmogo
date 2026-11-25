import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import 'app_startup.dart';
import 'autoread/autoread_feature.dart';
import 'autoread/background/parse_entry.dart' show parseEntry;
import 'autoread/data/airtime_trail_store.dart';
import 'autoread/data/fuliza_event_saver.dart';
import 'data/db/sqlite_fuliza_repository.dart' show LazySqliteFulizaRepository;
import 'autoread/data/ingesting_launch_source.dart';
import 'autoread/data/real_waiting_repository.dart';
import 'autoread/model/waiting_repository.dart';
import 'autoread/runtime.dart';
import 'autoread/service/autoread_service.dart';
import 'autoread/wiring/rules_wiring.dart';
import 'autoread/ui/launch_router.dart';
import 'autoread/ui/remembered_wiring.dart';
import 'autoread/ui/waiting_bell_numbers.dart';
import 'data/db/app_database.dart';
import 'domain/paid_to/paid_to.dart' show PaidToGrouping;
import 'ui/shell/back_closes_keyboard.dart';
import 'ui/screens/analytics/edit_lock_parts.dart' show EditLockSwitch;
import 'domain/fuliza/fuliza_rebuild.dart' show FulizaRebuild;
import 'ui/screens/fuliza/fuliza_source.dart' show FulizaSource;
import 'data/db/startup_open.dart';
import 'data/updates/updates_inbox.dart';
import 'ui/restart_scope.dart';
import 'ui/screens/add/add_screen.dart';
import 'data/backup/restore_trail_hook.dart';
import 'ui/screens/backup/backup_screen.dart';
import 'ui/screens/manage_classifications_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/privacy/privacy_screen.dart';
import 'ui/screens/recently_deleted_screen.dart';
import 'ui/screens/remembered/remembered_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/updates/updates_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/shell/app_messenger.dart';
import 'ui/shell/bell_counts.dart';
import 'ui/shell/notifications_route.dart';
import 'ui/shell/notifications_scope.dart';
import 'ui/shell/updates_news_repository.dart';
import 'ui/shell/primary_shell.dart';
import 'ui/shell/routes.dart';
import 'ui/startup_gate.dart';
import 'ui/startup_notice.dart';
import 'ui/theme/app_colors.dart';
import 'ui/theme/app_palette_scope.dart';
import 'ui/theme/app_theme.dart';

/// Stage 2 ("Parse from the notification"): started BY NAME by the auto-read build's Kotlin in a short-lived
/// headless engine; nothing in Dart calls it. The entry point has to live in this library. Where
/// `kAutoReadCompiled` is false (the standard build) it returns at once and the background-parse code
/// is tree-shaken away.
@pragma('vm:entry-point')
void parseFromNotificationEntry(List<String> args) {
  if (kAutoReadCompiled) parseEntry(args);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BackClosesKeyboard.install(); // F6: Back with the keyboard open closes the keyboard first
  // Auto-read: the one bridge and controller, and the Delete data wipe hook,
  // are set BEFORE the reset resume so a cut-short Delete data is finished with
  // the auto-read wipe too.
  if (kAutoReadCompiled) {
    AutoReadRuntime.install();
    // 0.2.1 rules (Suggested + Ask first): the rules store, history, offers and the Settings and
    // Remembered rows are joined to the app here (preferences only; the database opens later).
    RulesWiring.install();
  }
  // 0.2.0 S8: Paid to groups a named Paybill by name (accounts paged in its sheet) in the debug flavor only.
  PaidToGrouping.paybillByName = kAutoReadCompiled;
  // 0.2.0 S9: the edit sheet shows a message row's own figures read-only, debug flavor only.
  EditLockSwitch.messageRowsReadOnly = kAutoReadCompiled;
  // 0.2.0 S9: invented Fuliza events for the UI check, only with --dart-define=MMOGO_FULIZA_DEMO=true (debug). No-op otherwise.
  await FulizaSource.installDemoIfOn(DateTime.now());
  FulizaSource.installReal(); // S12 D: the stored events (no-op when the demo installed its own)
  // S9b-1: a "Reset app" that was cut short is finished FIRST (before the
  // palette load and before anything opens the database), then S9a (AP1):
  // the palette and the Appearance are read BEFORE the first frame, so a dark
  // choice never flashes light. See bootstrapApp for the pinned order.
  final controller = await bootstrapApp();
  runApp(RestartScope(
    controller: controller,
    // S10c: the open-failure gate (OF1). A soft restart re-runs it (cheap: the
    // handle is already open, so the open returns at once).
    builder: (c) => StartupGate(
      controller: c,
      open: openAppDatabaseForStart,
      readStage: readAppOpenStage,
      closeDatabase: closeAppDatabaseForRetry,
      beforeOpen: prepareAppOpenSnapshot,
      classify: classifyAppOpenFailure,
      child: MpesaTrackerApp(controller: c),
    ),
  ));
}

/// The app root: the palette-driven light and dark [AppTheme] and the named-route table.
///
/// Every launch starts on Welcome (T16), which continues to Onboarding
/// while the onboarding-complete flag is unset, otherwise to Home. Home,
/// Analytics, Paid to and Settings are the primary destinations under the
/// fixed 5-item bottom nav (Home | Analytics | Add FAB (center) | Paid to |
/// Settings; T22 reorder of T2's); Add is the centre FAB's screen; Profile, Manage
/// Classifications and Recently Deleted are secondary pages with the
/// back-arrow + mini-FAB chrome; Welcome and Onboarding are full-screen,
/// with no app chrome. Route names live in [Routes].
class MpesaTrackerApp extends StatefulWidget {
  const MpesaTrackerApp({super.key, this.controller});

  /// Test seam: a controller already loaded. Null = a fresh one, loaded here.
  final AppPaletteController? controller;

  @override
  State<MpesaTrackerApp> createState() => _MpesaTrackerAppState();
}

class _MpesaTrackerAppState extends State<MpesaTrackerApp> with WidgetsBindingObserver {
  // T23: the app-wide chosen palette (ocean | leaf | indigo), loaded from
  // AppPrefs once here and published down via AppPaletteScope. Starts at
  // ocean (AppPaletteController's own default) while the read is in flight.
  late final AppPaletteController _paletteController = widget.controller ?? AppPaletteController();

  // F8/I1: the data the bell and the Notifications page read:
  // UpdatesNewsRepository over the Updates inbox, and (autoread build) the real
  // waiting repository over the per-item store, the parse service and the bridge.
  late final UpdatesNewsRepository _news = UpdatesNewsRepository(UpdatesInbox.instance);
  AutoReadWaitingRepository? _waiting;
  RealWaitingRepository? _realWaiting;
  AutoReadLaunchRouter? _launchRouter;
  late final BellCountsTracker _bell;

  /// The navigator key of the autoread build (the launch router uses it). One
  /// per app instance, so a soft restart gets a NEW navigator.
  final GlobalKey<NavigatorState> _autoReadNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    appNavigatorKey = _autoReadNavigatorKey; // the pill toast reaches the root overlay through this
    if (kAutoReadCompiled) {
      // The ONE shared bridge and store (AutoReadRuntime), also used by the
      // Settings controller and the Delete data wipe.
      _realWaiting = RealWaitingRepository(
        bridge: AutoReadRuntime.bridge,
        // Home, Analytics and Paid to re-query after a Categorize save, as after Add.
        onSaved: () {
          PrimaryShell.active?.dataChanged();
          _realWaiting?.refreshUndecided(); // a new or decided withdrawal moves the bell
        },
        store: AutoReadRuntime.store,
        service: AutoReadService(
          bridge: AutoReadRuntime.bridge,
          // The in-app Parse labels what it saves (who, level, up to 2 categories), as the background does.
          store: RulesWiring.labelling(AutoReadRuntime.store),
          savedCodes: TransactionCodeLookup(() => AppDatabase.instance.database),
          now: DateTime.now,
        ),
        fulizaSaver: FulizaEventSaver(
            () async => LazySqliteFulizaRepository(() => AppDatabase.instance.database)),
        // The 24 h "Recorded automatically" list is kept in the phone's preferences.
        trailStore: AirtimeTrailStore(prefs: SharedTrailPrefs(), now: DateTime.now),
      );
      _waiting = _realWaiting;
      AutoReadRuntime.airtime = _realWaiting!.airtime; // the ONE switch controller: Notifications card, Remembered tab, Settings row
      // A Replace restore empties the shown trail AND sends every person back to Suggested (rules wiped,
      // history summary rebuilt). The hook is CHAINED, never overwritten. Merge never reaches it.
      final priorClear = AirtimeTrailRestoreHook.clearMemory;
      AirtimeTrailRestoreHook.clearMemory =
          RulesWiring.restoreHook(prior: priorClear, clearTrail: () => _realWaiting?.airtime.clearTrail());
      FulizaRebuild.hook = _realWaiting!.rebuildFromHeld; // S12: the Rebuild button on the Fuliza page
      WidgetsBinding.instance.addObserver(this);
      // Delete data rebuilds the rows through this once it has wiped.
      AutoReadRuntime.refresh = () async {
        _realWaiting!.airtime.clearTrail(); // the in-memory auto-record trail goes with the data
        _realWaiting!.clearDescriptions(); // so do the in-memory held-message descriptions
        await RulesWiring.afterDeleteData(); // the offers list and the summary follow the wipe
        await _realWaiting!.ingest();
        await _realWaiting!.refreshUndecided();
      };
      // Look at what is held once the first frame is up (on start), after the
      // fail-closed check of the switch against the consent version.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await AutoReadRuntime.reconcile();
        await _realWaiting?.ingest();
        await _realWaiting?.refreshUndecided();
        unawaited(RulesWiring.rebuildSummary()); // the people summary follows the ledger on open
      });
    }
    _bell = BellCountsTracker(
      news: _news.watchNews(),
      waiting: kAutoReadCompiled
          ? waitingBellNumbers(
              _waiting!,
              DateTime.now,
              undecided: _realWaiting?.undecided,
              // each "Ask first next time?" offer adds one to the pill, as on the To do chip
              offersChanged: RulesWiring.suggestions,
              offerCount: () => RulesWiring.suggestions?.offers.length ?? 0,
            )
          : null,
    );
    if (kAutoReadCompiled) {
      // F8: a tap on a phone notification opens the Notifications page.
      _launchRouter = AutoReadLaunchRouter(
        source: IngestingLaunchSource(BridgeLaunchSource(AutoReadRuntime.bridge), _realWaiting!),
        navigatorKey: _autoReadNavigatorKey,
        waiting: _waiting,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchRouter?.start());
    }
    if (widget.controller == null) _paletteController.load();
    // S9b-2 (A4): a start-up reset that did not finish gets one small notice.
    WidgetsBinding.instance.addPostFrameCallback((_) => StartupNotice.maybeShow());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kAutoReadCompiled && state == AppLifecycleState.resumed) {
      AutoReadRuntime.reconcile().then((_) => _realWaiting?.ingest()).then((_) => _realWaiting?.refreshUndecided());
      unawaited(RulesWiring.rebuildSummary());
    }
  }

  @override
  void dispose() {
    if (kAutoReadCompiled) {
      WidgetsBinding.instance.removeObserver(this);
      if (AutoReadRuntime.refresh == _realWaiting?.ingest) AutoReadRuntime.refresh = null;
      if (AutoReadRuntime.airtime == _realWaiting?.airtime) AutoReadRuntime.airtime = null;
      AirtimeTrailRestoreHook.clearMemory = null;
      _realWaiting?.dispose();
    }
    _launchRouter?.dispose();
    _bell.dispose();
    _news.dispose();
    if (widget.controller == null) _paletteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPaletteScope(
      controller: _paletteController,
      child: NotificationsScope(
        news: _news,
        waiting: _waiting,
        counts: _bell.value,
        child: ListenableBuilder(
          listenable: _paletteController,
          builder: (context, _) => _app(),
        ),
      ),
    );
  }

  Widget _app() {
    final set = AppPalettes.byId(_paletteController.value);
    return MaterialApp(
      title: 'mmogo',
      // S9a (AP1): a light and a dark Material theme from the chosen
      // palette; the Appearance (System | Light | Dark) picks between them
      // (System follows the phone). Pages read the same choice through
      // AppPalette.of.
      theme: AppTheme.forPalette(set.light),
      darkTheme: AppTheme.forPalette(set.dark),
      themeMode: switch (_paletteController.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      debugShowCheckedModeBanner: false,
      navigatorKey: _autoReadNavigatorKey,
      navigatorObservers: [if (kAutoReadCompiled) _launchRouter!.observer],
      // T27 — see app_messenger.dart's own doc comment.
      scaffoldMessengerKey: appMessengerKey,
      // T16: every launch starts on Welcome, which routes on to onboarding
      // (flag unset) or Home (flag set). Home's T13 purge/bootstrap still
      // runs in its own initState, i.e. before Home renders any data.
      initialRoute: Routes.welcome,
      routes: {
        Routes.welcome: (_) => const WelcomeScreen(),
        Routes.onboarding: (_) => const OnboardingScreen(),
        // F5: the four tab pages live together in one PrimaryShell route.
        Routes.home: (_) => const PrimaryShell(initialIndex: 0),
        Routes.analytics: (_) => const PrimaryShell(initialIndex: 1),
        Routes.add: (_) => const AddScreen(),
        Routes.paidTo: (_) => const PrimaryShell(initialIndex: 3),
        Routes.profile: (_) => const PrimaryShell(initialIndex: 4),
        Routes.settings: (_) => SettingsScreen(
              rememberedHook: kAutoReadCompiled && AutoReadRuntime.airtime != null
                  ? rememberedRowHookFor(AutoReadRuntime.airtime!)
                  : null,
            ),
        Routes.manageClassifications: (_) => const ManageClassificationsScreen(),
        Routes.recentlyDeleted: (_) => const RecentlyDeletedScreen(),
        Routes.backup: (_) => const BackupScreen(),
        Routes.updates: (_) => const UpdatesScreen(),
        Routes.notifications: (_) => const NotificationsRoute(),
        Routes.privacy: (_) => const PrivacyScreen(),
        Routes.rememberedRecipients: (ctx) => kAutoReadCompiled && AutoReadRuntime.airtime != null
            ? rememberedPageFor(AutoReadRuntime.airtime!,
                args: ModalRoute.of(ctx)?.settings.arguments, cleanup: AutoReadRuntime.ruleCleanup)
            : const RememberedScreen(), // standard build: the page as it was
      },
    );
  }
}
