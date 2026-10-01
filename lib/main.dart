import 'package:flutter/material.dart';

import 'ui/screens/add/add_screen.dart';
import 'ui/screens/manage_classifications_screen.dart';
import 'ui/screens/notifications_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/profile_screen.dart';
import 'ui/screens/recently_deleted_screen.dart';
import 'ui/screens/welcome_screen.dart';
import 'ui/shell/app_messenger.dart';
import 'ui/shell/primary_shell.dart';
import 'ui/shell/routes.dart';
import 'ui/theme/app_palette_scope.dart';
import 'ui/theme/app_theme.dart';

void main() {
  runApp(const MpesaTrackerApp());
}

/// The app root: the light [AppTheme] and the named-route table.
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
  const MpesaTrackerApp({super.key});

  @override
  State<MpesaTrackerApp> createState() => _MpesaTrackerAppState();
}

class _MpesaTrackerAppState extends State<MpesaTrackerApp> {
  // T23: the app-wide chosen palette (ocean | leaf | indigo), loaded from
  // AppPrefs once here and published down via AppPaletteScope. Starts at
  // ocean (AppPaletteController's own default) while the read is in flight.
  final _paletteController = AppPaletteController();

  @override
  void initState() {
    super.initState();
    _paletteController.load();
  }

  @override
  void dispose() {
    _paletteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppPaletteScope(
      controller: _paletteController,
      child: MaterialApp(
        title: 'mmogo',
        theme: AppTheme.theme,
        // Pinned to light: a dark phone must not half-darken screens that
        // haven't been reworked yet. The chosen palette now applies
        // app-wide (T26 "i think it should recolor the entire app",
        // superseding T23's "only reworked pages" rule): every reworked
        // page, including Welcome, onboarding and now Add (T27), follows it
        // via AppPalette.of. The page-by-page rework adds a darkTheme +
        // ThemeMode.system later.
        themeMode: ThemeMode.light,
        debugShowCheckedModeBanner: false,
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
          Routes.settings: (_) => const PrimaryShell(initialIndex: 4),
          Routes.profile: (_) => const ProfileScreen(),
          Routes.manageClassifications: (_) => const ManageClassificationsScreen(),
          Routes.recentlyDeleted: (_) => const RecentlyDeletedScreen(),
          Routes.notifications: (_) => const NotificationsComingSoonScreen(),
        },
      ),
    );
  }
}
