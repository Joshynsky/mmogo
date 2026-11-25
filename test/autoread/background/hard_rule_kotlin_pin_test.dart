@Tags(['autoread'])
library;

// 0.2.2 item 2 slice B2c, Kotlin side. There is no Kotlin unit-test project: these tests read the Kotlin source and
// pin the shape of the Auto-record arrival (the decision logic itself runs in tool/kotlin_selfcheck against the
// shared case table). The alert: the existing queued line, ONLY "Change category", no Yes, no Undo; written only
// behind the flag and the native decision; Change category removes the automatic mark before the app imports.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _kt(String n) => File('$_k/$n').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final arrival = _kt('HardRuleArrival.kt');

  group('the queued Auto-record alert', () {
    final post = arrival.substring(arrival.indexOf('fun postQueued'), arrival.indexOf('private fun changeAction'));

    test('one action only: Change category (no Yes, no Not now, no Undo)', () {
      expect(RegExp(r'\.addAction\(').allMatches(arrival), hasLength(1));
      expect(arrival, contains('AskAlert.LABEL_CHANGE'));
      for (final w in ['LABEL_YES', 'ACTION_YES', 'LABEL_NOT_NOW', 'ACTION_LATER', 'Undo']) {
        expect(post, isNot(contains(w)), reason: w);
      }
      expect(post, contains('ParseNotifier.openApp(ctx, heldId, AskAlert.ACTION_CHANGE)'));
    });

    test('the words are the existing queued line (no new string), the generic timeout, never the 6 s self dismiss', () {
      expect(post, contains('AskAlert.TEXT_QUEUED'));
      expect(arrival, isNot(contains('const val TEXT')));
      expect(post, contains('AskAlert.timeoutMs(false, HeldWindow.WINDOW_MS, AutoReadSwitch.alertMinutes(ctx))'));
      expect(post, isNot(contains('SELF_DISMISS_MS')));
    });

    test('no category name, amount, person or message text on it; PendingIntents only from the shared helpers', () {
      for (final w in ['categoryName', 'amount', 'peek(', 'body', 'PendingIntent.get', 'FLAG_MUTABLE', 'Log.', 'println']) {
        expect(post, isNot(contains(w)), reason: w);
      }
      expect(arrival, isNot(contains('PendingIntent.get')));
    });
  });

  group('the mark is written only behind the flag and the native decision', () {
    final queue = arrival.substring(arrival.indexOf('fun queueIfAuto'), arrival.indexOf('fun autoHintCategory'));

    test('flag first, then the decision from one snapshot of the stored values, then a committed string mark', () {
      expect(queue.indexOf('if (!HardRuleLogic.AUTO_RECORD_LIVE) return false'), lessThan(queue.indexOf('HardRuleLogic.mayRecord(')));
      expect(queue, contains('val all = p.all'));
      expect(queue, contains('HardRuleLogic.mayRecord(all[AskStore.PENDING_PREFIX + heldId] as? String) { k -> all[k] }'));
      expect(queue, contains('putString(AskStore.yesKey(heldId), HardRuleLogic.autoMarkValue(nowMs)).commit()'));
      expect(queue, contains('catch (_: Throwable)'));
    });

    test('the runner tries Auto-record first only for a fresh parse; otherwise today\'s Ask first or Parsed alert', () {
      final r = _kt('ParseRunner.kt');
      final i = r.indexOf('HardRuleArrival.queueIfAuto(ctx, job.id, System.currentTimeMillis())');
      expect(i, greaterThan(0));
      expect(r, contains('if (parsed && HardRuleArrival.queueIfAuto('));
      expect(r.indexOf('HardRuleArrival.postQueued(ctx, job.id)'), greaterThan(i));
      expect(r.indexOf('AskNotifier.postAsk(ctx, job.id, askCategoryId)'), greaterThan(i));
      expect(r, contains('val askCategoryId = dartAskCategoryId ?: if (parsed) HardRuleArrival.autoHintCategory(ctx, job.id) else null'));
    });
  });

  group('Change category keeps the item for the user', () {
    test('the automatic mark (only that kind) is removed when the app is opened by Change category', () {
      final drop = arrival.substring(arrival.indexOf('fun dropOnChange'), arrival.indexOf('fun postQueued'));
      expect(drop, contains('intent?.action != AskAlert.ACTION_CHANGE'));
      expect(drop, contains('HardRuleLogic.isAutoMark(p.all[key])'));
      expect(drop, contains('.remove(key).commit()'));
    });

    test('the bridge removes it on a cold start (constructor) and before it tells the app about a new intent', () {
      final b = _kt('AutoReadBridge.kt');
      final init = b.substring(b.indexOf('init {'), b.indexOf('private val store'));
      expect(init, contains('HardRuleArrival.dropOnChange(activity, activity.intent)'));
      final ni = b.substring(b.indexOf('private fun handleNewIntent'));
      expect(ni.indexOf('HardRuleArrival.dropOnChange(activity, intent)'), lessThan(ni.indexOf('channel.invokeMethod("onTapped"')));
    });
  });

  test('a Yes on an `auto` item Kotlin did not record is valid (same question); the manifest is unchanged', () {
    expect(_kt('AskFirstLogic.kt'), contains(r'''Regex("\"rl\"\\s*:\\s*\"(ask|auto)\"")'''));
    final m = File('android/app/src/autoread/AndroidManifest.xml').readAsStringSync();
    expect(RegExp('<receiver').allMatches(m), hasLength(2));
    expect(RegExp('<uses-permission ').allMatches(m), hasLength(2));
  });
}
