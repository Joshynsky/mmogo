/// Named-route constants for the whole app. Single source of truth so no
/// screen hardcodes a route string that could drift from `main.dart`'s
/// route table.
class Routes {
  Routes._();

  /// T16 — the app's initial route on EVERY launch (PM direct decision,
  /// 2026-09-24). About 3s after it is first on screen, or on a tap, it
  /// replaces itself with [onboarding] while the onboarding-complete flag
  /// is unset, otherwise with [home].
  static const welcome = '/welcome';

  /// T16 — reached only from [welcome] while the onboarding-complete flag
  /// is unset; Skip / Get started set the flag and reset the stack to
  /// [home].
  static const onboarding = '/onboarding';

  // Primary destinations — the fixed 5-item bottom nav. T22 (PM direct
  // decision, 2026-09-25): Home | Analytics | Add FAB (center) | Paid to |
  // Settings (was Home | Parties | Add | Analytics | Settings, T2 AMENDED).
  static const home = '/home';
  static const analytics = '/analytics';
  static const add = '/add';

  /// "Paid to" (formerly Parties, T15; renamed in T22).
  static const paidTo = '/paid-to';

  /// B48 (PM 2026-10-01): Profile is the fifth bottom-nav tab (was Settings).
  static const profile = '/profile';

  /// Order matches the bottom nav's visual left-to-right layout, index 2
  /// being the centered FAB slot.
  static const primaryOrder = [home, analytics, add, paidTo, profile];

  // Secondary pages — two-tier chrome pattern (back-arrow + mini-FAB, not
  // the full 5-item bar).

  /// B48: no longer a tab; opened from the Profile page's Settings row.
  static const settings = '/settings';
  static const manageClassifications = '/manage-classifications';
  static const recentlyDeleted = '/recently-deleted';

  /// T25 — reached via the new bell button in the primary top bar
  /// (`primary_scaffold.dart`); a placeholder "Coming soon" page.
  static const notifications = '/notifications';
}
