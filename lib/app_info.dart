/// T17 — Profile's "App info" card. The app's name and version as plain
/// Dart constants rather than read at runtime via a plugin such as
/// `package_info_plus`: adding a new plugin would change the merged Android
/// manifest T11 already verified against this project's exact current
/// plugin set. [version] is kept in lock-step with `pubspec.yaml`'s own
/// `version:` line by `test/app_info_test.dart`, which fails the suite the
/// moment the two drift — bump both together.
class AppInfo {
  AppInfo._();

  static const name = 'My Money Go';

  /// Must equal `pubspec.yaml`'s `version:` value exactly (build-name +
  /// `+`build-number).
  static const version = '0.1.0+1';

  /// `0.1.0` — the user-facing build-name part of [version].
  static String get versionName => version.split('+').first;

  /// `1` — the build-number part of [version], or `null` if absent.
  static String? get buildNumber {
    final parts = version.split('+');
    return parts.length > 1 ? parts[1] : null;
  }

  /// `Version 0.1.0 (build 1)` — Profile's display string.
  static String get displayVersion =>
      buildNumber == null ? 'Version $versionName' : 'Version $versionName (build $buildNumber)';
}
