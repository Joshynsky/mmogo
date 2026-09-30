// T17 — guards lib/app_info.dart's hand-maintained version constant
// against silently drifting from pubspec.yaml (the real build version
// Android's versionName/versionCode come from). No plugin is used to read
// the version at runtime — see AppInfo's doc comment — so this test is the
// only thing keeping the two in sync. `flutter test` runs with the project
// root as its working directory, so `pubspec.yaml` resolves directly.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/app_info.dart';

void main() {
  test('AppInfo.version matches pubspec.yaml\'s version: line exactly', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final versionLines = pubspec
        .where((l) => RegExp(r'^version:\s*').hasMatch(l))
        .toList();
    expect(versionLines, hasLength(1), reason: 'expected exactly one top-level version: line');
    final pubspecVersion = versionLines.single
        .replaceFirst(RegExp(r'^version:\s*'), '')
        .split('#')
        .first
        .trim();
    expect(AppInfo.version, pubspecVersion);
  });

  test('displayVersion splits build-name and build-number', () {
    expect(AppInfo.displayVersion, 'Version ${AppInfo.versionName} (build ${AppInfo.buildNumber})');
    expect(AppInfo.version, '${AppInfo.versionName}+${AppInfo.buildNumber}');
  });

  test('T20: this release is v0.1.0 (build 1)', () {
    expect(AppInfo.version, '0.1.0+1');
    expect(AppInfo.versionName, '0.1.0');
    expect(AppInfo.displayVersion, 'Version 0.1.0 (build 1)');
  });
}
