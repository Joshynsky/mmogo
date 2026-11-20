// Wiring 2: the background Parse is given the REAL rule store and undone-codes list (preferences), and the
// default history (database read, then the summary). Kotlin is played by a pretend runner. Invented data.
@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/parse_entry.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/history/history_summary_codec.dart';
import 'package:mmogo/autoread/rules/prefs_rule_store.dart';
import 'package:mmogo/autoread/rules/prefs_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/sample_messages.dart';

const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _channel = MethodChannel(kBackgroundChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<Object?, Object?> done;

  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'peekHeld':
        return <String, Object?>{'id': _id, 'body': kSampleSendMoney, 'receivedAtMs': DateTime.now().millisecondsSinceEpoch};
      case 'claim':
        return true;
      case 'release':
        return null;
      case 'ackHeld':
        return 'acked';
      case 'done':
        done = Map<Object?, Object?>.of(call.arguments as Map);
        return null;
    }
    throw MissingPluginException();
  }

  Future<List<String>> pendingValues() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return [for (final k in p.getKeys().where((k) => k.startsWith(kPendingItemPrefix))) p.getString(k)!];
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    done = {};
    messenger.setMockMethodCallHandler(_channel, handle);
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('an Ask first person is labelled from the real preferences store (Ask first, with the key)', () async {
    await PrefsRuleStore().setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime.utc(2026, 11, 1));
    await runBackgroundEntry([_id], channel: _channel, rules: PrefsRuleStore(), undone: PrefsUndoneCodes());
    expect(done['outcome'], kBgParsed);
    final v = (await pendingValues()).single;
    expect(v, contains('"rl":"ask"'));
    expect(v, contains('"rk":"0712345678"'));
    expect(v, contains('"sg":[7]'));
  });

  test('a Suggested person with history gets the top categories from the preferences summary (database read unavailable)', () async {
    final p = await SharedPreferences.getInstance();
    await p.setString(kHistSummaryPrefKey, encodeHistSummary({'SM.0712345678': [4, 3]}));
    await runBackgroundEntry([_id], channel: _channel, rules: PrefsRuleStore(), undone: PrefsUndoneCodes());
    expect(done['outcome'], kBgParsed);
    expect((await pendingValues()).single, contains('"sg":[4,3]'));
  });

  test('a code in the real undone-codes list is a duplicate and is not stored', () async {
    await PrefsUndoneCodes().add('QWE1R2T3Y4', now: DateTime.now());
    await runBackgroundEntry([_id], channel: _channel, rules: PrefsRuleStore(), undone: PrefsUndoneCodes());
    expect(done['outcome'], kBgDuplicate);
    expect(await pendingValues(), isEmpty);
  });

  test('the entry point itself (parseEntry) hands both real stores to runBackgroundEntry', () {
    final src = File('lib/autoread/background/parse_entry.dart').readAsStringSync();
    expect(src, contains('runBackgroundEntry(args, reporter: out, rules: PrefsRuleStore(), undone: PrefsUndoneCodes())'));
  });
}
