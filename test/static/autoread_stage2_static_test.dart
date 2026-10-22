// Stage 2 (Wave C, "Parse from the notification") static guards.
//  1. The STANDARD build and its source sets/manifests carry none of it.
//  2. The autoread manifest gains exactly one non-exported, intent-filter-less, initially disabled
//     receiver and nothing else (no service, no new permission, no battery request).
//  3. The Kotlin parse code keeps the safety shape (immutable explicit PendingIntents, only
//     shared_preferences registered, no service/alarm/wake lock/power manager, no body in the notifier).
//  4. Dart and Kotlin shared constants and wording are pinned together.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/parse_entry.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart' show kActionParse, kCouldNotRead;

import '../support/static_scan.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _read(String p) => File(p).readAsStringSync();
String _policy() => _read('$_k/ParsePolicy.kt');
String _const(String src, String name) {
  final m = RegExp('const val $name(?:: [A-Za-z]+)? = ([^\\r\\n]+)').firstMatch(src);
  expect(m, isNotNull, reason: '$name not found');
  return m!.group(1)!.trim();
}

String _str(String name) {
  final m = RegExp('<string name="$name">([^<]*)</string>').firstMatch(_read('android/app/src/autoread/res/values/strings.xml'));
  expect(m, isNotNull, reason: 'string $name not found');
  return m!.group(1)!;
}

void main() {
  group('the standard build has none of stage 2', () {
    const words = ['ParseActionReceiver', 'ParseRunner', 'ParseNotifier', 'ParseGuard', 'ParsePolicy', 'autoread_bg', 'parse_entry', 'parseEntry'];
    final rules = [for (final w in words) ScanRule(w, RegExp(RegExp.escape(w)))];

    test('src/main and src/standard (manifests, Kotlin, resources) name none of the stage 2 words', () {
      final files = [
        ...filesUnder('android/app/src/main', {'.kt', '.xml', '.java'}),
        ...filesUnder('android/app/src/standard', {'.kt', '.xml', '.java'}),
      ];
      expect(files, isNotEmpty);
      final hits = scanFiles(files, rules);
      expect(hits, isEmpty, reason: 'stage 2 words in a standard source set:\n${hits.join('\n')}');
    });

    test('lib/ outside lib/autoread (main.dart apart) names none of the stage 2 words, the background folder or the headless channel', () {
      final extra = [...rules, ScanRule('background folder', RegExp(r'autoread/background')), ScanRule('headless channel', RegExp(r'autoread_bg'))];
      final files = filesUnder('lib', {'.dart'})
          .where((f) => !normPath(f.path).contains('lib/autoread/') && !normPath(f.path).endsWith('lib/main.dart'))
          .toList();
      expect(files.length, greaterThanOrEqualTo(100));
      final hits = scanFiles(files, extra);
      expect(hits, isEmpty, reason: 'stage 2 words outside lib/autoread:\n${hits.join('\n')}');
    });

    test('main.dart: the one entry point, guarded by the flag, and the one import of the background folder', () {
      final main = _read('lib/main.dart').replaceAll('\r\n', '\n');
      expect(RegExp(r"import 'autoread/background/parse_entry\.dart' show parseEntry;").allMatches(main), hasLength(1));
      expect(RegExp('autoread/background').allMatches(main), hasLength(1));
      final m = RegExp(r"@pragma\('vm:entry-point'\)\nvoid parseFromNotificationEntry\(List<String> args\) \{\n  if \(kAutoReadCompiled\) parseEntry\(args\);\n\}").firstMatch(main);
      expect(m, isNotNull, reason: 'the entry must be one guarded call, so the standard build tree-shakes the rest');
      expect(RegExp(r'\bparseEntry\(').allMatches(main), hasLength(1), reason: 'nothing else in main.dart may call the background parse');
      expect(RegExp('entry-point').allMatches(main), hasLength(1));
    });

    test('the APK checker knows the stage 2 receiver only in the autoread flavor and bans stage 2 strings in the standard libapp', () {
      final ps = _read('tool/check_apk_manifest.ps1');
      expect(ps, contains('app.mmogo.autoread.ParseActionReceiver'));
      expect(ps, contains("'autoread_bg'"));
      expect(ps, contains("'autoread/background/parse_entry'"));
    });
  });

  group('the autoread manifest', () {
    final manifest = _read('android/app/src/autoread/AndroidManifest.xml');
    final recv = RegExp(r'<receiver\s+android:name="app\.mmogo\.autoread\.ParseActionReceiver"([^>]*)/>').firstMatch(manifest);

    test('declares ParseActionReceiver once: disabled, not exported, no intent-filter, no permission attribute', () {
      expect(recv, isNotNull);
      expect(RegExp('ParseActionReceiver').allMatches(manifest), hasLength(1));
      final attrs = recv!.group(1)!;
      expect(attrs, contains('android:enabled="false"'));
      expect(attrs, contains('android:exported="false"'));
      expect(attrs, isNot(contains('intent-filter')));
      // No intent-filter anywhere inside it: it is a self-closing element.
      expect(recv.group(0)!.endsWith('/>'), isTrue);
    });

    test('still exactly two permissions, no service, no foreground service, no battery request, no wake lock, no boot receiver', () {
      expect(RegExp('<uses-permission ').allMatches(manifest), hasLength(2));
      expect(manifest, isNot(contains('<service')));
      for (final w in ['FOREGROUND_SERVICE', 'REQUEST_IGNORE_BATTERY_OPTIMIZATIONS', 'WAKE_LOCK', 'RECEIVE_BOOT_COMPLETED', 'SCHEDULE_EXACT_ALARM', 'USE_FULL_SCREEN_INTENT']) {
        expect(manifest, isNot(contains(w)), reason: w);
      }
      expect(RegExp('<receiver').allMatches(manifest), hasLength(2), reason: 'SmsReceiver and ParseActionReceiver only');
    });
  });

  group('the Kotlin parse code keeps its safety shape', () {
    final names = ['ParseActionReceiver.kt', 'ParseRunner.kt', 'ParseNotifier.kt', 'ParseGuard.kt', 'ParsePolicy.kt'];
    final src = {for (final n in names) n: _read('$_k/$n')};

    test('every PendingIntent in the autoread Kotlin is immutable and none is mutable', () {
      final all = Directory('android/app/src/autoread/kotlin').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.kt'));
      var calls = 0;
      for (final f in all) {
        final text = f.readAsStringSync();
        for (final m in RegExp(r'PendingIntent\.get(Activity|Broadcast|Service|Activities)\(([\s\S]*?)\)\s*[\r\n]').allMatches(text)) {
          calls++;
          expect(m.group(2), contains('FLAG_IMMUTABLE'), reason: '${f.path}: ${m.group(0)}');
        }
        expect(text, isNot(contains('FLAG_MUTABLE')), reason: f.path);
      }
      expect(calls, greaterThanOrEqualTo(3));
    });

    test('PendingIntents are explicit: our own component or class, never an implicit action only', () {
      final n = src['ParseNotifier.kt']!;
      expect(n, contains('Intent(context, ParseActionReceiver::class.java)'));
      expect(n, contains('component = ComponentName(context, MAIN_ACTIVITY)'));
      expect(n, isNot(contains('Intent(Intent.')));
    });

    test('the only extra is the hidden held id; the notifier never touches message text', () {
      final n = src['ParseNotifier.kt']!;
      expect(RegExp(r'putExtra\(').allMatches(n), hasLength(2));
      for (final m in RegExp(r'putExtra\(([^,]+),').allMatches(n)) {
        expect(m.group(1), 'Notifier.EXTRA_HELD_ID');
      }
      expect(n, isNot(contains('.peek(')), reason: 'the notifier must not read the held body');
      for (final f in ['ParseNotifier.kt', 'ParseActionReceiver.kt']) {
        expect(src[f], isNot(contains('.body')), reason: f);
      }
    });

    test('the headless engine registers ONLY shared_preferences', () {
      final r = src['ParseRunner.kt']!;
      expect(RegExp(r'FlutterEngine\(job\.ctx, null, false\)').hasMatch(r), isTrue, reason: 'automaticallyRegisterPlugins must be false');
      expect(RegExp(r'plugins\.add\(').allMatches(r), hasLength(1));
      expect(r, contains('plugins.add(SharedPreferencesPlugin())'));
      expect(r, isNot(contains('GeneratedPluginRegistrant')));
      expect(r, isNot(contains('registerWith')));
    });

    test('no service, work manager, alarm, wake lock, power manager, boot receiver in the autoread Kotlin', () {
      final rules = [
        ScanRule('Service', RegExp(r'\b(startForeground|startForegroundService|ForegroundService|JobService|JobScheduler|IntentService|android\.app\.Service)\b')),
        ScanRule('WorkManager', RegExp(r'WorkManager|WorkRequest')),
        ScanRule('AlarmManager', RegExp(r'AlarmManager|setExact|setAlarmClock')),
        ScanRule('WakeLock', RegExp(r'WakeLock|PowerManager')),
        ScanRule('battery', RegExp(r'IGNORE_BATTERY|BatteryOptimization', caseSensitive: false)),
        ScanRule('boot', RegExp(r'BOOT_COMPLETED')),
      ];
      final files = filesUnder('android/app/src/autoread', {'.kt', '.xml'});
      final hits = scanFiles(files, rules);
      expect(hits, isEmpty, reason: 'forbidden in the autoread sources:\n${hits.join('\n')}');
    });

    test('the receiver checks the id, the switches and the held message, and takes the claim before any engine', () {
      final r = src['ParseActionReceiver.kt']!;
      final iId = r.indexOf('Notifier.heldIdFrom(intent)');
      final iGuard = r.indexOf('ParseGuard.mayParse(ctx)');
      final iPeek = r.indexOf('store.peek(id)');
      final iClaim = r.indexOf('store.claim(id)');
      final iSubmit = r.indexOf('ParseRunner.submit');
      expect(iId, greaterThan(-1));
      expect([iId, iGuard, iPeek, iClaim, iSubmit], orderedEquals([iId, iGuard, iPeek, iClaim, iSubmit]..sort()));
      expect([iGuard, iPeek, iClaim, iSubmit].every((i) => i > -1), isTrue);
    });

    test('the runner acks only through the generation and switch check, and has a watchdog and a rate limit', () {
      final r = src['ParseRunner.kt']!;
      expect(r, contains('ParsePolicy.ackAllowed('));
      expect(r, contains('ParsePolicy.WATCHDOG_MS'));
      expect(r, contains('ParseScheduler()'));
      expect(r, contains('engine?.destroy()'));
      // The ack is the only place the held copy is deleted by the runner.
      expect(RegExp(r'\.ack\(').allMatches(r), hasLength(1));
    });

    test('the Parse button is added only behind the switch and consent check, in Notifier.post', () {
      final n = _read('$_k/Notifier.kt');
      final iGuard = n.indexOf('CaptureGuard.mayCapture(context)');
      final iParse = n.indexOf('ParseGuard.mayParse(context)');
      final iAction = n.indexOf('ParseNotifier.parseAction(context, heldId)');
      expect(iGuard, greaterThan(-1));
      expect(iParse, greaterThan(iGuard));
      expect(iAction, greaterThan(iParse));
    });

    test('the self-check runner includes the stage 2 logic', () {
      final run = _read('tool/kotlin_selfcheck/run.ps1');
      expect(run, contains("'ParsePolicy.kt'"));
      expect(run, contains("'ParseSelfCheck.kt'"));
      expect(_read('tool/kotlin_selfcheck/SelfCheckMain.kt'), contains('ParseSelfCheck.runAll()'));
    });
  });

  group('Dart and Kotlin are pinned together', () {
    final policy = _policy();

    test('the headless channel, the entry library and function', () {
      expect(_const(policy, 'BG_CHANNEL'), '"$kBackgroundChannel"');
      expect(_const(policy, 'ENTRY_LIBRARY'), '"package:mmogo/main.dart"');
      expect(_const(policy, 'ENTRY_FUNCTION'), '"parseFromNotificationEntry"');
      expect(_read('lib/main.dart'), contains('void parseFromNotificationEntry(List<String> args)'));
      expect(_read('lib/autoread/background/parse_entry.dart'), contains('void parseEntry(List<String> args)'));
    });

    test('the generation key is the Dart key under the shared_preferences "flutter." prefix', () {
      expect(_const(policy, 'GENERATION_KEY'), '"flutter.$kPendingGenerationKey"');
    });

    test('the outcome codes Dart sends are exactly the Kotlin ones (plus the Kotlin-only watchdog)', () {
      final kotlin = RegExp(r'[A-Z_]+\("([a-z_]+)"\)').allMatches(policy.substring(policy.indexOf('enum class Outcome'), policy.indexOf('fun outcomeOf'))).map((m) => m.group(1)!).toList();
      expect(kotlin.toSet(), {...kBackgroundOutcomeCodes, 'watchdog'});
    });

    test('timings: watchdog under the 10 s broadcast limit, self-dismiss about 6 s', () {
      expect(int.parse(_const(policy, 'WATCHDOG_MS').replaceAll('L', '').replaceAll('_', '')), lessThan(10000));
      expect(int.parse(_const(policy, 'WATCHDOG_MS').replaceAll('L', '')), 8000);
      expect(int.parse(_const(policy, 'SELF_DISMISS_MS').replaceAll('L', '')), 6000);
    });

    test('the notification action and could-not-read words equal the Dart copy', () {
      expect(_str('autoread_action_parse'), kActionParse);
      expect(_str('autoread_could_not_read'), kCouldNotRead);
      expect(_str('autoread_action_categorize'), 'Categorize now');
      expect(_str('autoread_action_later'), 'Later');
      expect(_str('autoread_parsed_text'), r'Parsed. %1$d waiting for a category');
      // The wave A wording stays.
      expect(_str('autoread_notification_title'), 'M-Pesa message received');
      expect(_str('autoread_notification_text'), 'An M-Pesa message is waiting. Tap to parse it.');
    });

    test('no notification string carries an amount, a name or message text', () {
      final xml = _read('android/app/src/autoread/res/values/strings.xml');
      for (final s in RegExp(r'<string name="autoread_(?:action|parsed|could|notification)[^>]*>([^<]*)</string>').allMatches(xml)) {
        final v = s.group(1)!;
        expect(v, isNot(matches(RegExp(r'Ksh|KES|\d{3,}'))), reason: v);
      }
    });
  });
}
