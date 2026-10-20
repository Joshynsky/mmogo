import 'package:flutter/material.dart';

import 'app_startup.dart';
import 'autoread/autoread_feature.dart';
import 'autoread/data/ingesting_launch_source.dart';
import 'autoread/data/real_waiting_repository.dart';
import 'autoread/model/waiting_repository.dart';
import 'autoread/runtime.dart';
import 'autoread/service/autoread_service.dart';
import 'autoread/ui/launch_router.dart';
import 'autoread/ui/waiting_bell_numbers.dart';
import 'data/db/app_database.dart';
import 'data/db/startup_open.dart';
import 'data/updates/updates_inbox.dart';
import 'ui/restart_scope.dart';
import 'ui/screens/add/add_screen.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Auto-read: the one bridge and controller, and the Delete data wipe hook,
  // are set BEFORE the reset resume so a cut-short Delete data is finished with
  // the auto-read wipe too.
  if (kAutoReadCompiled) AutoReadRuntime.install();
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
    if (kAutoReadCompiled) {
      // The ONE shared bridge and store (AutoReadRuntime), also used by the
      // Settings controller and the Delete data wipe.
      _realWaiting = RealWaitingRepository(
        bridge: AutoReadRuntime.bridge,
        // Home, Analytics and Paid to re-query after a Categorize save, as after Add.
        onSaved: () => PrimaryShell.active?.dataChanged(),
        store: AutoReadRuntime.store,
        service: AutoReadService(
          bridge: AutoReadRuntime.bridge,
          store: AutoReadRuntime.store,
          savedCodes: TransactionCodeLookup(() => AppDatabase.instance.database),
          now: DateTime.now,
        ),
      );
      _waiting = _realWaiting;
      WidgetsBinding.instance.addObserver(this);
      // Delete data rebuilds the rows through this once it has wiped.
      AutoReadRuntime.refresh = _realWaiting!.ingest;
      // Look at what is held once the first frame is up (on start).
      WidgetsBinding.instance.addPostFrameCallback((_) => _realWaiting?.ingest());
    }
    _bell = BellCountsTracker(
      news: _news.watchNews(),
      waiting: kAutoReadCompiled ? waitingBellNumbers(_waiting!, DateTime.now) : null,
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
      _realWaiting?.ingest();
    }
  }

  @override
  void dispose() {
    if (kAutoReadCompiled) {
      WidgetsBinding.instance.removeObserver(this);
      if (AutoReadRuntime.refresh == _realWaiting?.ingest) AutoReadRuntime.refresh = null;
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
      navigatorKey: kAutoReadCompiled ? _autoReadNavigatorKey : null,
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
        Routes.settings: (_) => const SettingsScreen(),
        Routes.manageClassifications: (_) => const ManageClassificationsScreen(),
        Routes.recentlyDeleted: (_) => const RecentlyDeletedScreen(),
        Routes.backup: (_) => const BackupScreen(),
        Routes.updates: (_) => const UpdatesScreen(),
        Routes.notifications: (_) => const NotificationsRoute(),
        Routes.privacy: (_) => const PrivacyScreen(),
        Routes.rememberedRecipients: (_) => const RememberedScreen(),
      },
    );
  }
}
