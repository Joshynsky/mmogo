@Tags(['autoread'])
library;

// 0.2.2 item 2 slice B-ARR, Kotlin side. There is no Kotlin unit-test project: these tests read the Kotlin source and
// pin the shape of B-2, B-4 and F-4 (the device behaviour itself is a phone check):
//  - F-4: the queued Auto-record alert pops up (POPUP channel, IMPORTANCE_HIGH, alerts every time) and its words never
//    say "recorded" (the app records it).
//  - B-4: AFTER the alert is posted (also when it could not be), the bridge pushes `onArrived` with no argument, on
//    the main thread, only to a live activity.
//  - B-2: the bridge's `cancelAlert` cancels only that item's notification (Notifier.cancel), never cancelAll; Change
//    category on the queued alert also clears it once the automatic mark is removed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _kt(String n) => File('$_k/$n').readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  final arrival = _kt('HardRuleArrival.kt');
  final bridge = _kt('AutoReadBridge.kt');

  group('F-4: the queued Auto-record alert', () {
    test('pops up: the popup builder, the HIGH channel, alerting every time', () {
      expect(arrival, contains('ParseNotifier.builder(ctx, nm, AskAlert.TEXT_QUEUED, popup = true)'));
      final pn = _kt('ParseNotifier.kt');
      expect(pn, contains('val channel = if (popup) Notifier.POPUP_CHANNEL_ID else Notifier.CHANNEL_ID'));
      expect(pn, contains('.setOnlyAlertOnce(!popup)'));
      final n = _kt('Notifier.kt');
      final ensure = n.substring(n.indexOf('fun ensurePopupChannel'), n.indexOf('internal fun ensureChannel'));
      expect(ensure, contains('NotificationManager.IMPORTANCE_HIGH'));
    });

    test('never says "recorded" before mmogo opens (the existing queued line)', () {
      final line = RegExp(r'const val TEXT_QUEUED = "([^"]*)"').firstMatch(_kt('AskFirstLogic.kt'))!.group(1)!;
      expect(line, 'Queued. It will be added when mmogo opens.');
      expect(line.toLowerCase(), isNot(contains('recorded')));
    });
  });

  group('B-4: the open app is told about the arrival', () {
    final post = arrival.substring(arrival.indexOf('fun postQueued'), arrival.indexOf('private fun changeAction'));

    test('onArrived runs in a finally, after the notify', () {
      final notify = post.indexOf('nm.notify(NotifierPure.notificationId(heldId), b.build())');
      final fin = post.indexOf('} finally {');
      expect(notify, greaterThan(0));
      expect(fin, greaterThan(notify));
      expect(post.indexOf('AutoReadBridge.onArrived()'), greaterThan(fin));
    });

    test('the bridge pushes "onArrived" with NO argument, on the main looper, only to a live activity, never throwing', () {
      final fn = bridge.substring(bridge.indexOf('private fun notifyArrived'), bridge.indexOf('private fun handlePermissionsResult'));
      expect(fn, contains('if (activity.isFinishing || activity.isDestroyed) return'));
      expect(fn, contains('Handler(Looper.getMainLooper()).post'));
      expect(fn, contains('channel.invokeMethod("onArrived", null)'));
      expect(fn, contains('catch (_: Throwable)'));
      final companion = bridge.substring(bridge.indexOf('fun onArrived()'), bridge.indexOf('private var pending'));
      expect(companion, contains('current?.notifyArrived()'));
      expect(companion, contains('catch (_: Throwable)'));
    });
  });

  group('B-2: the alert leaves the shade', () {
    test('"cancelAlert" cancels only this item (Notifier.cancel), never every alert', () {
      final i = bridge.indexOf('"cancelAlert" -> {');
      expect(i, greaterThan(0));
      final branch = bridge.substring(i, bridge.indexOf('"listHeldIds"'));
      expect(branch, contains('BridgeLogic.idArg(call.arguments)'));
      expect(branch, contains('if (id != null) Notifier.cancel(activity, id)'));
      expect(branch, isNot(contains('cancelAll')));
    });

    test('Notifier.cancel cancels one id only (a pinned notice of another feature keeps its own id)', () {
      final n = _kt('Notifier.kt');
      final c = n.substring(n.indexOf('fun cancel(context: Context, heldId: String)'), n.indexOf('fun cancelAll'));
      expect(c, contains('nm.cancel(NotifierPure.notificationId(heldId))'));
      expect(c, isNot(contains('activeNotifications')));
    });

    test('Change category on the queued alert clears it after the automatic mark is removed', () {
      final drop = arrival.substring(arrival.indexOf('fun dropOnChange'), arrival.indexOf('fun postQueued'));
      expect(drop.indexOf('Notifier.cancel(ctx, id)'), greaterThan(drop.indexOf('.remove(key).commit()')));
    });
  });
}
