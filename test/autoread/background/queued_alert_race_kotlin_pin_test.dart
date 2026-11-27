@Tags(['autoread'])
library;

// 0.2.2 item 2 slice I2b, Kotlin side. There is no Kotlin unit-test project: these tests read the Kotlin source and
// pin two fixes (the device behaviour itself is a phone check):
//  - B-ARR HANDOFF 1: a Yes tapped from the shade while mmogo is in front is imported at once. AskNotifier.postQueued
//    pushes `onArrived` (the same push HardRuleArrival.postQueued uses) in a finally, after the notify.
//  - B-ARR self-check race: a resume ingest between writing the mark and posting the "Queued" alert records the item
//    and cancels before the alert exists. Both queued alerts are now posted only while their mark is still stored,
//    and cleared again if the mark went during the post. The app removes the mark BEFORE it cancels (queued_yes.dart),
//    so either the app's cancel or Kotlin's re-check always removes the alert.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _kt(String n) => File('$_k/$n').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final ask = _kt('AskNotifier.kt');
  final runner = _kt('ParseRunner.kt');

  group('the Yes queued alert (AskNotifier.postQueued)', () {
    final post = ask.substring(ask.indexOf('fun postQueued'), ask.indexOf('private fun isLocked'));

    test('B-ARR HANDOFF 1: onArrived runs in a finally, after the notify, with no argument', () {
      final notify = post.indexOf('nm.notify(NotifierPure.notificationId(heldId), b.build())');
      final fin = post.indexOf('} finally {');
      expect(notify, greaterThan(0));
      expect(fin, greaterThan(notify));
      expect(post.indexOf('AutoReadBridge.onArrived()'), greaterThan(fin));
      expect(RegExp(r'AutoReadBridge\.onArrived\(\)').allMatches(ask), hasLength(1));
    });

    test('posted only while the Yes mark is stored; cleared again if the mark went during the post', () {
      final notify = post.indexOf('nm.notify(');
      final pre = post.indexOf('if (!yesMarkHeld(ctx, heldId)) return false');
      final reCheck = post.indexOf('if (!yesMarkHeld(ctx, heldId)) Notifier.cancel(ctx, heldId)');
      expect(pre, greaterThan(0));
      expect(pre, lessThan(notify));
      expect(reCheck, greaterThan(notify));
      // only this item's alert, never every alert
      expect(post, isNot(contains('cancelAll')));
    });

    test('the mark read is the Yes key in the plugin file and fails closed (unreadable: no alert)', () {
      final fn = ask.substring(ask.indexOf('private fun yesMarkHeld'));
      expect(fn, contains('ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE).all[AskStore.yesKey(heldId)] != null'));
      expect(fn, contains('catch (_: Throwable)'));
      expect(fn, contains('false'));
      // it reads only; nothing is written or removed here
      expect(fn, isNot(contains('.edit()')));
    });

    test('the receiver still queues the Yes before the alert (the mark exists when postQueued reads it)', () {
      final recv = _kt('ParseActionReceiver.kt');
      expect(recv, contains('if (AskFirstPrefs.writeYes(ctx, id, System.currentTimeMillis())) AskNotifier.postQueued(ctx, id) else Notifier.cancel(ctx, id)'));
    });
  });

  group('the Auto-record queued alert (ParseRunner)', () {
    test('posted only while the automatic mark is stored; cleared again if the mark went during the post', () {
      final q = runner.indexOf('if (parsed && HardRuleArrival.queueIfAuto(ctx, job.id, System.currentTimeMillis())) {');
      final pre = runner.indexOf('if (autoMarkHeld(ctx, job.id)) {');
      final post = runner.indexOf('HardRuleArrival.postQueued(ctx, job.id)');
      final reCheck = runner.indexOf('if (!autoMarkHeld(ctx, job.id)) Notifier.cancel(ctx, job.id)');
      expect(q, greaterThan(0));
      expect(pre, greaterThan(q));
      expect(post, greaterThan(pre));
      expect(reCheck, greaterThan(post));
      expect(RegExp(r'HardRuleArrival\.postQueued\(').allMatches(runner), hasLength(1));
    });

    test('the mark read accepts only an AUTOMATIC mark and fails closed', () {
      final fn = runner.substring(runner.indexOf('private fun autoMarkHeld'));
      expect(fn, contains('HardRuleLogic.isAutoMark(ctx.getSharedPreferences(AskStore.FLUTTER_PREFS, Context.MODE_PRIVATE).all[AskStore.yesKey(id)])'));
      expect(fn, contains('catch (_: Throwable)'));
      expect(fn, isNot(contains('.edit()')));
    });

    test('the flag is untouched: the mark is still written only behind AUTO_RECORD_LIVE', () {
      final arrival = _kt('HardRuleArrival.kt');
      final queue = arrival.substring(arrival.indexOf('fun queueIfAuto'), arrival.indexOf('fun autoHintCategory'));
      expect(queue, contains('if (!HardRuleLogic.AUTO_RECORD_LIVE) return false'));
      expect(_kt('HardRuleLogic.kt'), contains('const val AUTO_RECORD_LIVE = true'));
    });
  });

  test('the app removes a finished mark BEFORE it cancels the alert (the order both re-checks rely on)', () {
    final dart = File('lib/autoread/data/queued_yes.dart').readAsStringSync().replaceAll('\r\n', '\n');
    final rm = dart.indexOf('await marks.remove(finished);');
    expect(rm, greaterThan(0));
    expect(dart.indexOf('await _cancelAlerts(finished);', rm), greaterThan(rm));
    final rmAuto = dart.indexOf('await am.remove(finished);');
    expect(rmAuto, greaterThan(0));
    expect(dart.indexOf('await _cancelAlerts(finished);', rmAuto), greaterThan(rmAuto));
  });
}
