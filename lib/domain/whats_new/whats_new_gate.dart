/// B31: decides whether the What's-new modal shows. Pure: no storage, no UI.
class WhatsNewGate {
  WhatsNewGate._();

  /// True when the modal should show now:
  ///  - the installed version has bundled content ([hasContentFor]);
  ///  - the stored "seen" version differs from the installed one;
  ///  - and either a version was stored before, or onboarding is complete
  ///    (0.1.0 never wrote the key, so "unset + onboarding done" is an upgrade
  ///    from 0.1.0; "unset + onboarding not done" is a fresh install and never
  ///    shows).
  static bool pending({
    required String? seenVersion,
    required String installedVersionName,
    required bool onboardingComplete,
    required bool Function(String versionName) hasContentFor,
  }) {
    if (!hasContentFor(installedVersionName)) return false;
    if (seenVersion == installedVersionName) return false;
    return seenVersion != null || onboardingComplete;
  }
}
