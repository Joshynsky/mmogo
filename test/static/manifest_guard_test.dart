// B6: static guards on the main Android manifest and its backup rules.
// Source side only; the merged-manifest proof is B39 (signed-build check).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _manifestPath = 'android/app/src/main/AndroidManifest.xml';
const _rulesPath = 'android/app/src/main/res/xml/data_extraction_rules.xml';

void main() {
  late String manifest;
  late String rules;
  setUpAll(() {
    manifest = File(_manifestPath).readAsStringSync();
    rules = File(_rulesPath).readAsStringSync();
  });

  test('exactly one uses-permission, and it is INTERNET', () {
    final perms = RegExp(r'<uses-permission\b[^>]*>').allMatches(manifest).map((m) => m.group(0)!).toList();
    expect(perms, hasLength(1));
    expect(perms.single, contains('android:name="android.permission.INTERNET"'));
  });

  test('application: backups stay off, extraction rules wired, no cleartext traffic', () {
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
  });

  test('the <queries> block is unchanged (PROCESS_TEXT only)', () {
    final queries = RegExp(r'<queries>.*?</queries>', dotAll: true).allMatches(manifest).toList();
    expect(queries, hasLength(1));
    final body = queries.single.group(0)!;
    expect(body, contains('android.intent.action.PROCESS_TEXT'));
    expect(body, contains('text/plain'));
    expect('<intent>'.allMatches(body), hasLength(1));
  });

  test('data_extraction_rules excludes every domain in both cloud-backup and device-transfer', () {
    const domains = ['root', 'file', 'database', 'sharedpref', 'external'];
    for (final section in ['cloud-backup', 'device-transfer']) {
      final m = RegExp('<$section>(.*?)</$section>', dotAll: true).firstMatch(rules);
      expect(m, isNotNull, reason: 'missing <$section>');
      final body = m!.group(1)!;
      for (final d in domains) {
        expect(body, contains('<exclude domain="$d" path="."/>'), reason: '$section must exclude $d');
      }
      expect('<exclude '.allMatches(body), hasLength(domains.length));
      expect(body, isNot(contains('<include')));
    }
  });
}
