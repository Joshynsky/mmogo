/// T17 — Profile's "App info" card. The app's name and version as plain
/// Dart constants rather than read at runtime via a plugin such as
/// `package_info_plus`: adding a new plugin would change the merged Android
/// manifest T11 already verified against this project's exact current
/// plugin set. [version] is kept in lock-step with `pubspec.yaml`'s own
/// `version:` line by `test/app_info_test.dart`, which fails the suite the
/// moment the two drift — bump both together.
class AppInfo {
  AppInfo._();

  static const name = 'mmogo';

  /// Must equal `pubspec.yaml`'s `version:` value exactly (build-name +
  /// `+`build-number).
  static const version = '0.2.1+6';

  /// `0.2.1` — the user-facing build-name part of [version].
  static String get versionName => version.split('+').first;

  /// T2 (0.2.0): a debug build made with `flutter build apk --build-number N`
  /// has versionCode N, but the constant above still says the pubspec number.
  /// Pass `--dart-define=MMOGO_BUILD_NUMBER=N` with it and Profile shows N.
  /// Unset (every release build) = the pubspec number, as before.
  static const _buildNumberOverride = String.fromEnvironment('MMOGO_BUILD_NUMBER');

  /// `6` — the build-number part of [version], or `null` if absent. The
  /// `MMOGO_BUILD_NUMBER` define, when set, wins (see above).
  static String? get buildNumber {
    if (_buildNumberOverride.isNotEmpty) return _buildNumberOverride;
    final parts = version.split('+');
    return parts.length > 1 ? parts[1] : null;
  }

  /// `Version 0.2.1 (build 6)` — Profile's display string.
  static String get displayVersion =>
      buildNumber == null ? 'Version $versionName' : 'Version $versionName (build $buildNumber)';
}
