// §AUTOREAD.HELD: the one held-window constant, the expiry rule and the copy.
// Tagged autoread so the tagged run covers it; it needs no define, so it also
// runs in the default run (never skipped).
@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/logic/reading_controller.dart' show kReadingConsentVersion;

void main() {
  final heldAt = DateTime.utc(2026, 10, 18, 8, 0);

  group('heldExpired', () {
    test('the window is 24 hours', () => expect(kHeldWindow, const Duration(hours: 24)));

    test('just inside the window is kept', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow - const Duration(seconds: 1))), isFalse);
    });

    test('exactly the window is gone', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow)), isTrue);
    });

    test('past the window is gone', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow + const Duration(days: 3))), isTrue);
    });

    test('just received is kept', () => expect(heldExpired(heldAt, heldAt), isFalse));

    test('a small future stamp (within skew) is kept', () {
      expect(heldExpired(heldAt, heldAt.subtract(kHeldClockSkew)), isFalse);
      expect(heldExpired(heldAt, heldAt.subtract(const Duration(minutes: 1))), isFalse);
    });

    test('a stamp in the future by more than the skew is gone', () {
      expect(heldExpired(heldAt, heldAt.subtract(kHeldClockSkew + const Duration(seconds: 1))), isTrue);
      expect(heldExpired(heldAt, heldAt.subtract(const Duration(days: 2))), isTrue);
    });

    test('the window parameter is honoured', () {
      const w = Duration(hours: 2);
      expect(heldExpired(heldAt, heldAt.add(const Duration(hours: 1)), window: w), isFalse);
      expect(heldExpired(heldAt, heldAt.add(w), window: w), isTrue);
    });
  });

  group('copy follows the constant', () {
    test('default copy', () {
      expect(kHeldWindowCopy, 'Kept up to 24 hours, removed the next time mmogo runs after that.');
      expect(kHeldWindowCopy, heldWindowCopy(kHeldWindow));
    });

    test('the hour count in the copy equals kHeldWindow.inHours', () {
      expect(kHeldWindowCopy, contains('${kHeldWindow.inHours} hours'));
    });

    test('changing the window through the parameter changes the copy', () {
      expect(heldWindowCopy(const Duration(hours: 12)), contains('Kept up to 12 hours,'));
      expect(heldWindowCopy(const Duration(hours: 12)), isNot(contains('24')));
      expect(heldWindowCopy(const Duration(hours: 1)), contains('Kept up to 1 hour,'));
    });

    test('the copy never says "within"', () {
      expect(kHeldWindowCopy.toLowerCase(), isNot(contains('within')));
    });
  });

  group('Kotlin mirror', () {
    test('HeldWindow.WINDOW_MS and CLOCK_SKEW_MS equal the Dart constants', () {
      final src = File('android/app/src/autoread/kotlin/app/mmogo/autoread/HeldId.kt').readAsStringSync();
      int ms(String name) {
        final m = RegExp('const val $name: Long = ([0-9L \\* ]+)').firstMatch(src);
        expect(m, isNotNull, reason: '$name not found');
        return m!.group(1)!.replaceAll('L', '').split('*').map((p) => int.parse(p.trim())).reduce((a, b) => a * b);
      }

      expect(ms('WINDOW_MS'), kHeldWindow.inMilliseconds);
      expect(ms('CLOCK_SKEW_MS'), kHeldClockSkew.inMilliseconds);
    });

    test('ConsentGate.CONSENT_VERSION equals kReadingConsentVersion (one bump, both sides)', () {
      final src = File('android/app/src/autoread/kotlin/app/mmogo/autoread/ConsentGate.kt').readAsStringSync();
      final m = RegExp(r'const val CONSENT_VERSION: Int = (\d+)').firstMatch(src);
      expect(m, isNotNull, reason: 'CONSENT_VERSION not found');
      expect(int.parse(m!.group(1)!), kReadingConsentVersion);
      expect(kReadingConsentVersion, 2);
    });

    test('the Kotlin receiver and notifier check consent and the SMS permission themselves', () {
      String read(String f) => File('android/app/src/autoread/kotlin/app/mmogo/autoread/$f').readAsStringSync();
      expect(read('SmsReceiver.kt'), contains('CaptureGuard.mayCapture(context)'));
      expect(read('Notifier.kt'), contains('CaptureGuard.mayCapture(context)'));
      final guard = read('CaptureGuard.kt');
      expect(guard, contains('Manifest.permission.RECEIVE_SMS'));
      expect(guard, contains('ConsentGate.mayCapture'));
      expect(read('AutoReadBridge.kt'), contains('AutoReadSwitch.hasCurrentConsent(activity)'));
    });

    test('Autostart: the MIUI screen with a fallback to the app settings page; no battery exemption, no new permission', () {
      String read(String f) => File(f).readAsStringSync();
      final bridge = read('android/app/src/autoread/kotlin/app/mmogo/autoread/AutoReadBridge.kt');
      expect(bridge, contains('com.miui.securitycenter'));
      expect(bridge, contains('com.miui.permcenter.autostart.AutoStartManagementActivity'));
      expect(bridge, contains('ACTION_APPLICATION_DETAILS_SETTINGS'));
      for (final f in [
        'android/app/src/autoread/AndroidManifest.xml',
        'android/app/src/main/AndroidManifest.xml',
        ...Directory('android/app/src/autoread/kotlin').listSync(recursive: true).whereType<File>().map((e) => e.path),
      ]) {
        final s = read(f);
        expect(s, isNot(contains('REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')), reason: f);
        expect(s, isNot(contains('ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')), reason: f);
        expect(s, isNot(contains('PowerManager')), reason: f);
      }
      final manifest = read('android/app/src/autoread/AndroidManifest.xml');
      expect(RegExp('<uses-permission ').allMatches(manifest).length, 2, reason: 'still exactly RECEIVE_SMS and POST_NOTIFICATIONS');
    });

    test('the Xiaomi family is decided in Kotlin: xiaomi, redmi, poco', () {
      final src = File('android/app/src/autoread/kotlin/app/mmogo/autoread/BridgeLogic.kt').readAsStringSync();
      for (final m in ['xiaomi', 'redmi', 'poco']) {
        expect(src, contains('"$m"'));
      }
    });
  });
}
