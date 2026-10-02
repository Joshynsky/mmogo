// B31: the pure What's-new gate (gate_cases) and the fresh-install marker.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/domain/whats_new/whats_new_gate.dart';
import 'package:mmogo/ui/whats_new/whats_new_content.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _has011(String v) => v == '0.1.1';

bool _pending({String? seen, String installed = '0.1.1', bool onboarded = true, bool Function(String)? has}) =>
    WhatsNewGate.pending(
      seenVersion: seen,
      installedVersionName: installed,
      onboardingComplete: onboarded,
      hasContentFor: has ?? _has011,
    );

void main() {
  group('gate_cases', () {
    test('0.1.0 upgrader (nothing stored, onboarding done) shows', () {
      expect(_pending(seen: null, onboarded: true), isTrue);
    });
    test('fresh install (nothing stored, onboarding not done) never shows', () {
      expect(_pending(seen: null, onboarded: false), isFalse);
    });
    test('the same version already seen never shows', () {
      expect(_pending(seen: '0.1.1'), isFalse);
      expect(_pending(seen: '0.1.1', onboarded: false), isFalse);
    });
    test('an older stored version shows (even if onboarding is somehow not done)', () {
      expect(_pending(seen: '0.1.0'), isTrue);
      expect(_pending(seen: '0.1.0', onboarded: false), isTrue);
    });
    test('a version without content never shows', () {
      expect(_pending(seen: null, installed: '0.1.2'), isFalse);
      expect(_pending(seen: '0.1.1', installed: '0.1.2'), isFalse);
      expect(_pending(seen: null, has: (_) => false), isFalse);
    });
  });

  test('bundled content exists for 0.1.1 only', () {
    expect(hasWhatsNewContentFor('0.1.1'), isTrue);
    expect(hasWhatsNewContentFor('0.1.0'), isFalse);
    expect(hasWhatsNewContentFor('0.1.2'), isFalse);
  });

  group('seen-version storage', () {
    test('read returns null until written; write then read round-trips', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), isNull);
      expect(await UpdatePrefs.writeWhatsNewSeenVersion('0.1.1'), isTrue);
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), '0.1.1');
      expect(UpdatePrefs.keyWhatsNewSeenVersion, 'whatsnew_seen_version');
    });

    test('markWhatsNewSeenForFreshInstall writes when unset', () async {
      SharedPreferences.setMockInitialValues({});
      await UpdatePrefs.markWhatsNewSeenForFreshInstall('0.1.1');
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), '0.1.1');
    });

    test('markWhatsNewSeenForFreshInstall never overwrites an older stored version', () async {
      SharedPreferences.setMockInitialValues({'whatsnew_seen_version': '0.1.0'});
      await UpdatePrefs.markWhatsNewSeenForFreshInstall('0.1.1');
      expect(await UpdatePrefs.readWhatsNewSeenVersion(), '0.1.0');
    });
  });
}
