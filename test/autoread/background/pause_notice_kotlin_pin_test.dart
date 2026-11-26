@Tags(['autoread'])
library;

// 0.2.2 item 2 slice B-PAUSE, Kotlin side. There is no Kotlin unit-test project and the self-check runner is not
// this slice's (it compiles only pure files): these tests read the Kotlin source and pin the shape of the pinned
// paused notice. The device behaviour itself is a phone check.
//  - its OWN channel (never CHANNEL_ID / POPUP_CHANNEL_ID, which Notifier.cancelAll removes), a TAG and a NEGATIVE id
//    (NotifierPure.notificationId is always >= 0; Notifier.cancel cancels by id with no tag);
//  - ongoing, silent, not a foreground service; the words come from Dart only;
//  - Resume (PauseActionReceiver) writes the Dart key = false, fails closed, and the Kotlin decision mirrors the
//    Dart pauseResumeStep;
//  - Read off (setEnabled false) cancels it in FeatureHooks; the manifest receiver is not exported.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/pause_notice_bridge.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _read(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

/// The code without comments, so a comment can never satisfy a pin.
String _code(String src) =>
    src.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '').split('\n').map((l) => l.replaceFirst(RegExp(r'//.*$'), '')).join('\n');

void main() {
  final notice = _code(_read('$_k/PauseNotice.kt'));
  final receiver = _code(_read('$_k/PauseActionReceiver.kt'));
  final hooks = _code(_read('android/app/src/autoread/kotlin/app/mmogo/FeatureHooks.kt'));
  final notifier = _read('$_k/Notifier.kt');
  final manifest = _read('android/app/src/autoread/AndroidManifest.xml');

  String constOf(String src, String name) {
    final m = RegExp('const val $name = (.+)').firstMatch(src);
    expect(m, isNotNull, reason: name);
    return m!.group(1)!.trim();
  }

  group('the notice', () {
    test('its own channel id, different from both Notifier channels (cancelAll never reaches it)', () {
      final own = constOf(notice, 'CHANNEL_ID');
      expect(own, '"mmogo_autorecord_paused"');
      expect(own, isNot(constOf(notifier, 'CHANNEL_ID')));
      expect(own, isNot(constOf(notifier, 'POPUP_CHANNEL_ID')));
      expect(notice, contains('Notification.Builder(ctx, CHANNEL_ID)'));
      expect(notice, isNot(contains('Notifier.CHANNEL_ID')));
      expect(notice, isNot(contains('POPUP_CHANNEL_ID')));
      // cancelAll only cancels those two channels.
      expect(notifier, contains('if (ch == CHANNEL_ID || ch == POPUP_CHANNEL_ID) nm.cancel(sbn.tag, sbn.id)'));
    });

    test('a tag AND a negative id; posted and cancelled with both', () {
      expect(int.parse(constOf(notice, 'NOTIFICATION_ID')), lessThan(0));
      expect(constOf(notice, 'TAG'), isNotEmpty);
      expect(notice, contains('nm.notify(TAG, NOTIFICATION_ID, b.build())'));
      expect(notice, contains('cancel(TAG, NOTIFICATION_ID)'));
      // A held id's notification id is masked positive, so it can never be negative.
      expect(_read('$_k/NotifierPure.kt'), contains('and 0x7fffffff'));
    });

    test('ongoing, silent (low importance, alert once), not auto-cancelled; no foreground service', () {
      expect(notice, contains('.setOngoing(true)'));
      expect(notice, contains('.setAutoCancel(false)'));
      expect(notice, contains('.setOnlyAlertOnce(true)'));
      expect(notice, contains('NotificationManager.IMPORTANCE_LOW'));
      for (final f in ['startForeground', 'FOREGROUND_SERVICE', 'Service()']) {
        expect(notice, isNot(contains(f)), reason: f);
        expect(receiver, isNot(contains(f)), reason: f);
      }
    });

    test('words come from Dart only (title, Resume, channel name), checked; no string resource of its own', () {
      expect(notice, contains('cleanText(a?.get("title"))'));
      expect(notice, contains('cleanText(a?.get("resume"))'));
      expect(notice, contains('cleanText(a?.get("channelName"))'));
      expect(notice, contains('.setContentTitle(title)'));
      expect(notice, isNot(contains('R.string.')));
      expect(notice, isNot(contains('setContentText')), reason: 'mock al-paused: title and Resume only');
    });

    test('guards before posting: dormant flag, Read on with consent and SMS permission, notifications, stored pause; a "no" cancels', () {
      expect(notice, contains('HardRuleLogic.AUTO_RECORD_LIVE &&'));
      expect(notice, contains('CaptureGuard.mayCapture(ctx)'));
      expect(notice, contains('nm.areNotificationsEnabled()'));
      expect(notice, contains('Manifest.permission.POST_NOTIFICATIONS'));
      expect(notice, contains('storedPaused(ctx)'));
      expect(notice, contains('HardRuleLogic.pausedFrom(p.all[HardRuleLogic.PAUSED_KEY])'));
      expect(RegExp(r'if \(!ok\) \{\s*cancel\(ctx\)\s*return false').hasMatch(notice), isTrue);
    });

    test('the Resume PendingIntent is explicit, immutable, to the not-exported receiver, with no extras', () {
      expect(notice, contains('Intent(ctx, PauseActionReceiver::class.java).apply { action = ACTION_RESUME }'));
      expect(notice, isNot(contains('putExtra(')));
      expect(notice, contains('PendingIntent.FLAG_IMMUTABLE'));
    });

    test('the method channel name matches the Dart bridge', () {
      expect(constOf(notice, 'CHANNEL'), '"$kPauseNoticeChannel"');
    });
  });

  group('Resume (PauseActionReceiver)', () {
    test('acts only on its own action; reads the Dart key; an unreadable file keeps everything', () {
      expect(receiver, contains('if (intent.action != PauseNotice.ACTION_RESUME) return'));
      expect(receiver, contains('p.all[HardRuleLogic.PAUSED_KEY]'));
      expect(RegExp(r'catch \(_: Throwable\) \{\s*return').hasMatch(receiver), isTrue);
      expect(receiver, contains('PauseNotice.ResumeStep.KEEP -> return'));
    });

    test('writes false (Dart reads it as not paused), removes the notice only after a clean write and read-back', () {
      expect(receiver, contains('putBoolean(HardRuleLogic.PAUSED_KEY, false).commit()) return'));
      expect(receiver, contains('if (p.all[HardRuleLogic.PAUSED_KEY] == false) PauseNotice.cancel(ctx)'));
      expect(_read('$_k/HardRuleLogic.kt'), contains('const val PAUSED_KEY = "flutter.$kHardPausedPrefsKey"'));
    });

    test('the Kotlin decision mirrors pauseResumeStep (true -> resume; null/false -> already; else keep)', () {
      expect(notice, contains('if (unreadable) ResumeStep.KEEP else when (raw) {'));
      expect(notice, contains('true -> ResumeStep.RESUME'));
      expect(notice, contains('null, false -> ResumeStep.ALREADY'));
      expect(notice, contains('else -> ResumeStep.KEEP'));
      expect(pauseResumeStep(true), PauseResumeStep.resume);
      expect(pauseResumeStep(null), PauseResumeStep.already);
      expect(pauseResumeStep(false), PauseResumeStep.already);
      for (final odd in <Object>['true', 1, 0, 'yes', 1.0, <String>[]]) {
        expect(pauseResumeStep(odd), PauseResumeStep.keep, reason: '$odd');
      }
      expect(pauseResumeStep(true, unreadable: true), PauseResumeStep.keep);
      expect(PauseResumeStep.values.map((e) => e.name), ['resume', 'already', 'keep']);
    });
  });

  group('FeatureHooks and the manifest', () {
    test('Read off (setEnabled false) cancels the notice BEFORE the bridge handles the call; the notice channel is registered', () {
      expect(hooks, contains('call.method == "setEnabled" && BridgeLogic.enabledArg(call.arguments) == false'));
      final cancelAt = hooks.indexOf('PauseNotice.cancel(activity)');
      final bridgeAt = hooks.indexOf('bridge.onMethodCall(call, result)');
      expect(cancelAt, greaterThan(0));
      expect(bridgeAt, greaterThan(cancelAt));
      expect(hooks, contains('MethodChannel(engine.dartExecutor.binaryMessenger, PauseNotice.CHANNEL)'));
      expect(hooks, contains('.setMethodCallHandler(PauseNotice.Handler(activity.applicationContext))'));
    });

    test('PauseActionReceiver: declared once, not exported, no intent-filter, no permission', () {
      final m = RegExp(r'<receiver\s+android:name="app\.mmogo\.autoread\.PauseActionReceiver"([^>]*)/>').firstMatch(manifest);
      expect(m, isNotNull);
      expect(RegExp('PauseActionReceiver').allMatches(manifest), hasLength(1));
      expect(m!.group(1), contains('android:exported="false"'));
      expect(m.group(1), isNot(contains('android:permission')));
      expect(manifest, isNot(contains('<service')));
    });
  });
}
