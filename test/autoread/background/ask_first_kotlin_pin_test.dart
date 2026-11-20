@Tags(['autoread'])
library;

// 0.2.1 Ask first, Kotlin side. There is no Kotlin unit-test project, so these tests read the Kotlin source and
// pin what must not drift: the strings Dart and Kotlin share, the decision order on arrival, the three buttons,
// the immutable PendingIntents, the timeout decision, and that no new component or permission appeared.
// The decision logic itself is run by tool/kotlin_selfcheck (AskFirstSelfCheck, plain JVM).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/parse_entry.dart';
import 'package:mmogo/autoread/bridge/method_channel_autoread_bridge.dart' show kLaunchCategorize;
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/model/rule_hint.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';

import '../../support/waiting_fakes.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _kt(String n) => File('$_k/$n').readAsStringSync().replaceAll('\r\n', '\n');
String _const(String src, String name) {
  final m = RegExp('const val $name(?:: [A-Za-z]+)? = "([^"\\n]*)"').firstMatch(src);
  expect(m, isNotNull, reason: '$name not found');
  return m!.group(1)!;
}

void main() {
  final logic = _kt('AskFirstLogic.kt');

  group('strings shared with Dart', () {
    test('rule key prefix, pending prefix, yes prefix, names key and details key', () {
      expect(_const(logic, 'RULE_KEY_PREFIX'), 'flutter.$kRuleKeyPrefix');
      expect(_const(logic, 'PENDING_PREFIX'), 'flutter.$kPendingItemPrefix');
      expect(_const(logic, 'YES_PREFIX'), 'flutter.$kYesMarkPrefix');
      expect(_const(logic, 'NAMES_KEY'), 'flutter.$kCategoryNamesKey');
      expect(_const(logic, 'DETAILS_KEY'), 'flutter.${AppPrefs.keyCaptureIdentityPreference}');
    });

    test('the launch action and the done argument names', () {
      expect(_const(logic, 'LAUNCH_CATEGORIZE'), kLaunchCategorize);
      expect(_kt('ParsePolicy.kt'), contains('args["askCategoryId"]'));
      expect(File('lib/autoread/background/parse_entry.dart').readAsStringSync(), contains("'askCategoryId': ?askCategoryId"));
    });

    test('the hint keys the Kotlin regexes read are the keys the Dart codec writes', () {
      expect(logic, contains('Regex("\\"rl\\"'));
      expect(logic, contains('ask'));
      expect(logic, contains('Regex("\\"sg\\"'));
      final json = encodePendingItem(sampleAskItem());
      expect(json, contains('"rl":"ask"'));
      expect(json, contains('"sg":[7]'));
      final rule = encodeRule(ReceiverRule(
          type: ReceiverType.sendMoney, key: 'k', name: 'n', level: RuleLevel.askFirst, categoryId: 7, created: DateTime(2026), changed: DateTime(2026)));
      expect(rule, contains('"v":1'));
      expect(rule, contains('"lv":1'));
    });
  });

  group('arrival: the Parse starts by itself only behind every guard', () {
    test('SmsReceiver decides once, before the thread, and hands the broadcast to the runner without double finish', () {
      final s = _kt('SmsReceiver.kt');
      expect(s, contains('ArrivalParser.wanted(app, true)'), reason: 'only inside the tracked-kind branch');
      expect(s, contains('ArrivalParser.start(app, id, pending)'));
      expect(s, contains('if (!handedOver)'), reason: 'the runner finishes the broadcast, not this thread');
      // The "ready" alert is still posted first; the parse starts after it.
      expect(s.indexOf('Notifier.post(app, id)'), lessThan(s.indexOf('ArrivalParser.start')));
      // The existing guards stay in place.
      expect(s, contains('CaptureGuard.mayCapture(context)'));
    });

    test('the decision needs tracked, the Parse guard, receiver details ON and an Ask first rule', () {
      final p = _kt('ArrivalParser.kt');
      for (final w in ['tracked = tracked', 'ParseGuard.mayParse(ctx)', 'AskFirstPrefs.receiverDetailsOn(ctx)', 'AskFirstPrefs.anyAskFirstRule(ctx)']) {
        expect(p, contains(w));
      }
      expect(logic, contains('tracked && mayParse && receiverDetailsOn && anyAskFirst'));
    });

    test('the runner is the existing one: claim first, no new engine, no service, no alarm', () {
      final p = _kt('ArrivalParser.kt');
      expect(p, contains('AutoReadStores.held(ctx).claim(id)'));
      expect(p, contains('ParseRunner.submit(ctx, id, pending)'));
      for (final w in ['FlutterEngine', 'startService', 'AlarmManager', 'WakeLock', 'JobScheduler', 'WorkManager']) {
        expect(p, isNot(contains(w)), reason: w);
      }
    });
  });

  group('the alert', () {
    final n = _kt('AskNotifier.kt');

    test('exactly three actions: Not now, Change category, Yes', () {
      expect(RegExp(r'\.addAction\(').allMatches(n), hasLength(3));
      // 0.2.1: Not now, Change category, Yes (Yes on the far right, as in the in-app rows)
      expect(n.indexOf('LABEL_NOT_NOW'), lessThan(n.indexOf('LABEL_CHANGE')));
      expect(n.indexOf('LABEL_CHANGE'), lessThan(n.indexOf('LABEL_YES')));
      expect(_const(logic, 'LABEL_YES'), 'Yes');
      expect(_const(logic, 'LABEL_CHANGE'), 'Change category');
      expect(_const(logic, 'LABEL_NOT_NOW'), 'Not now');
    });

    test('Yes is our own broadcast and asks for an unlocked phone; Change opens the app; Not now is the existing Later', () {
      expect(n, contains('ParseNotifier.receiverIntent(ctx, heldId, AskAlert.ACTION_YES), authRequired = true'));
      expect(n, contains('setAuthenticationRequired(true)'));
      expect(n, contains('ParseNotifier.openApp(ctx, heldId, AskAlert.ACTION_CHANGE)'));
      expect(n, contains('ParseNotifier.receiverIntent(ctx, heldId, ParseNotifier.ACTION_LATER)'));
    });

    test('the question is posted on the pop-up channel and pops up again; the plain Parsed line stays quiet', () {
      expect(n, contains('popup = true'));
      final pn = _kt('ParseNotifier.kt');
      expect(pn, contains('.setOnlyAlertOnce(!popup)'));
    });

    test('DECISION: the question follows "Hide details after" (never the 6 s self dismiss); only the plain Parsed line and the queued line self dismiss', () {
      expect(n, contains('AskAlert.timeoutMs(shown.detailed, HeldWindow.WINDOW_MS, AutoReadSwitch.alertMinutes(ctx))'));
      expect(logic, contains('AlertText.timeoutMs(!detailed, heldWindowMs, detailsMinutes)'));
      final postAsk = n.substring(n.indexOf('fun postAsk'), n.indexOf('fun postQueued'));
      expect(postAsk, isNot(contains('SELF_DISMISS_MS')));
      expect(n.substring(n.indexOf('fun postQueued'), n.indexOf('private fun isLocked')), contains('ParsePolicy.SELF_DISMISS_MS'));
    });

    test('the category name is used only with Show details on and an unlocked phone; no message text, amount or person', () {
      expect(n, contains('AutoReadSwitch.alertDetails(ctx) && unlocked'));
      for (final w in ['peek(', 'body', 'originatingAddress', 'Log.', 'println']) {
        expect(n, isNot(contains(w)), reason: w);
      }
      // The public (lock screen) version is the generic one: it comes from the shared builder.
      expect(_kt('ParseNotifier.kt'), contains('.setPublicVersion(publicBuilder.build())'));
    });

    test('the wording is a draft in one place, and the queued line says it is added when mmogo opens', () {
      expect(logic, contains('// WORDING-DRAFT'));
      expect(_const(logic, 'TEXT_QUEUED'), 'Queued. It will be added when mmogo opens.');
      expect(_const(logic, 'TEXT_GENERIC'), 'Record with your usual category?');
    });

    test('a done outcome of parsed with a category asks the question; every other outcome keeps the plain behaviour', () {
      final r = _kt('ParseRunner.kt');
      expect(r, contains('if (askCategoryId != null && code == ParsePolicy.Outcome.PARSED.code) AskNotifier.postAsk(ctx, job.id, askCategoryId)'));
      expect(r, contains('else ParseNotifier.postParsed(ctx, job.id, waiting, queuedCents)'));
    });
  });

  group('Yes is a deliberate tap and only queues', () {
    final recv = _kt('ParseActionReceiver.kt');
    final prefs = _kt('AskFirstPrefs.kt');

    test('the receiver handles Yes with the Parse guard and writes one mark; it records nothing itself', () {
      final yes = recv.substring(recv.indexOf('private fun yes('), recv.indexOf('private fun parse('));
      expect(yes, contains('ParseGuard.mayParse(ctx)'));
      expect(yes, contains('AskFirstPrefs.writeYes(ctx, id, System.currentTimeMillis())'));
      expect(yes, contains('AskNotifier.postQueued(ctx, id)'));
      for (final w in ['ParseRunner', 'peek(', 'insert', 'sqlite']) {
        expect(yes, isNot(contains(w)), reason: w);
      }
    });

    test('a mark is written only when the stored item still carries an Ask first hint with a category', () {
      final w = prefs.substring(prefs.indexOf('fun writeYes'));
      expect(w, contains('AskStore.itemAsksFirst('));
      expect(w, contains('HeldId.isValid(heldId)'));
      expect(w, contains('.commit()'));
    });

    test('the Dart side never trusts a category from Kotlin: it records the item\'s own hint category', () {
      final dart = File('lib/autoread/data/queued_yes.dart').readAsStringSync();
      expect(dart, contains('_first(hint)'));
      expect(dart, isNot(contains('askCategoryId')));
    });

    test('no auto-record path: the Auto-record level is not acted on anywhere in the new Kotlin', () {
      for (final f in ['AskFirstLogic.kt', 'AskFirstPrefs.kt', 'AskNotifier.kt', 'ArrivalParser.kt']) {
        final t = _kt(f);
        expect(t, isNot(contains('autoRecord')), reason: f);
        expect(t, isNot(contains('auto_apply')), reason: f);
      }
    });
  });

  group('security shape', () {
    test('the manifest is unchanged: the two receivers, two permissions, no new component, nothing exported but the app', () {
      final m = File('android/app/src/autoread/AndroidManifest.xml').readAsStringSync();
      expect(RegExp('<receiver').allMatches(m), hasLength(2));
      expect(RegExp('<uses-permission ').allMatches(m), hasLength(2));
      expect(m, isNot(contains('<service')));
      expect(m, isNot(contains('<provider')));
      expect(m, isNot(contains('<activity')));
      expect(RegExp(r'android:name="app\.mmogo\.autoread\.ParseActionReceiver"[^>]*android:exported="false"').hasMatch(m), isTrue);
    });

    test('every PendingIntent in the new Kotlin is built by the shared immutable helpers', () {
      for (final f in ['AskNotifier.kt', 'AskFirstPrefs.kt', 'ArrivalParser.kt', 'AskFirstLogic.kt']) {
        expect(_kt(f), isNot(contains('PendingIntent.get')), reason: f);
        expect(_kt(f), isNot(contains('FLAG_MUTABLE')), reason: f);
      }
      final pn = _kt('ParseNotifier.kt');
      expect(RegExp('FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT').allMatches(pn), hasLength(2));
    });

    test('the new Kotlin logs nothing', () {
      for (final f in ['AskFirstLogic.kt', 'AskFirstPrefs.kt', 'AskNotifier.kt', 'ArrivalParser.kt']) {
        expect(_kt(f), isNot(matches(RegExp(r'\bLog\.|println\(|printStackTrace'))), reason: f);
      }
    });
  });

  group('the launch bridge', () {
    test('Change category is turned into one action, cleared once read, and pushed with the id', () {
      final b = _kt('AutoReadBridge.kt');
      expect(b, contains('"takeLaunchAction" -> result.success(takeLaunchAction())'));
      expect(b, contains('intent.action == AskAlert.ACTION_CHANGE'));
      expect(b, contains('intent.action = null'));
      expect(b, contains('mapOf("id" to id, "action" to action)'));
    });
  });

  group('the background result', () {
    test('only Ask first with a category asks the question', () {
      RuleHint h(RuleLevel l, List<int> s) => RuleHint(level: l, type: ReceiverType.sendMoney, key: 'k', suggested: s);
      expect(askCategoryOf(h(RuleLevel.askFirst, [7, 3])), 7);
      expect(askCategoryOf(h(RuleLevel.askFirst, const [])), isNull);
      expect(askCategoryOf(h(RuleLevel.suggested, [7])), isNull);
      expect(askCategoryOf(null), isNull);
    });
  });
}

WaitingItem sampleAskItem() => WaitingItem(
      id: heldIdFor(1),
      kind: WaitingKind.waitingCategory,
      heldAt: DateTime(2026, 11, 19),
      parsed: sampleFields(1, DateTime(2026, 11, 19)),
      hint: const RuleHint(level: RuleLevel.askFirst, type: ReceiverType.sendMoney, key: 'k', suggested: [7]),
    );
