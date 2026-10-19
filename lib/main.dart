import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'app_startup.dart';
import 'autoread/autoread_feature.dart';
import 'autoread/ui/t1_test_host.dart';
import 'data/db/startup_open.dart';
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
import 'ui/shell/primary_shell.dart';
import 'ui/shell/routes.dart';
import 'ui/startup_gate.dart';
import 'ui/startup_notice.dart';
import 'ui/theme/app_colors.dart';
import 'ui/theme/app_palette_scope.dart';
import 'ui/theme/app_theme.dart';

/// T1 test scaffolding (§AUTOREAD.T1): only used when autoread is compiled in a debug build.
final GlobalKey<NavigatorState> _t1NavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

class _MpesaTrackerAppState extends State<MpesaTrackerApp> {
  // T23: the app-wide chosen palette (ocean | leaf | indigo), loaded from
  // AppPrefs once here and published down via AppPaletteScope. Starts at
  // ocean (AppPaletteController's own default) while the read is in flight.
  late final AppPaletteController _paletteController = widget.controller ?? AppPaletteController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _paletteController.load();
    // S9b-2 (A4): a start-up reset that did not finish gets one small notice.
    WidgetsBinding.instance.addPostFrameCallback((_) => StartupNotice.maybeShow());
  }

  @override
  void dispose() {
    if (widget.controller == null) _paletteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPaletteScope(
      controller: _paletteController,
      child: ListenableBuilder(
        listenable: _paletteController,
        builder: (context, _) => _app(),
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
      navigatorKey: kAutoReadCompiled && kDebugMode ? _t1NavigatorKey : null,
      builder: (context, child) => (kAutoReadCompiled && kDebugMode)
          ? T1TestHost(navigatorKey: _t1NavigatorKey, child: child ?? const SizedBox.shrink())
          : child ?? const SizedBox.shrink(),
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
        Routes.privacy: (_) => const PrivacyScreen(),
        Routes.rememberedRecipients: (_) => const RememberedScreen(),
      },
    );
  }
}
