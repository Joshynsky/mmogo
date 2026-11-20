// Auto-record S2b: the background Parse labels the waiting item, skips an undone code, never touches the
// database, and logs no message text. Invented messages only; Kotlin is played by a pretend runner.
@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/parse_entry.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/rule_labeler.dart';
import 'package:mmogo/autoread/rules/fake_rule_store.dart';
import 'package:mmogo/autoread/rules/fake_undone_codes.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/sample_messages.dart';

const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _channel = MethodChannel(kBackgroundChannel);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<Object?, Object?> done;
  late bool acked;
  late String held;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    switch (call.method) {
      case 'peekHeld':
        return <String, Object?>{'id': _id, 'body': held, 'receivedAtMs': DateTime.now().millisecondsSinceEpoch};
      case 'claim':
        return true;
      case 'release':
        return null;
      case 'ackHeld':
        acked = true;
        return 'acked';
      case 'done':
        done = Map<Object?, Object?>.of(args as Map);
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
    acked = false;
    held = kSampleSendMoney;
    messenger.setMockMethodCallHandler(_channel, handle);
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('with a rule store the stored item carries the labels (key from the phone, categories from history)', () async {
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime(2026, 11, 19));
    await runBackgroundEntry([_id],
        channel: _channel,
        undone: FakeUndoneCodes(),
        labeler: RuleLabeler(
            rules: rules,
            history: FakeHistoryReader(history: {'SM.0712345678': [4, 3]}),
            ));
    expect(done['outcome'], kBgParsed);
    final v = (await pendingValues()).single;
    expect(v, contains('"rl":"ask"'));
    expect(v, contains('"rk":"0712345678"'));
  });

  test('history unavailable falls back (labels from the rule only); the parse still succeeds', () async {
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime(2026, 11, 19));
    await runBackgroundEntry([_id],
        channel: _channel,
        labeler: RuleLabeler(rules: rules, history: FakeHistoryReader(unavailable: true)));
    expect(done['outcome'], kBgParsed);
    expect((await pendingValues()).single, contains('"sg":[7]'));
  });

  // 0.2.1 Ask first: done carries the category an Ask first person offers, so Kotlin asks the question.
  test('Ask first: done carries askCategoryId (a number, nothing else about the message)', () async {
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime(2026, 11, 19));
    await runBackgroundEntry([_id], channel: _channel, labeler: RuleLabeler(rules: rules, history: FakeHistoryReader()));
    expect(done['outcome'], kBgParsed);
    expect(done['askCategoryId'], 7);
    expect(done.keys.toSet(), {'outcome', 'waiting', 'askCategoryId'});
  });

  test('Suggested person, no rule, or no labeller: done carries no askCategoryId', () async {
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.suggested, at: DateTime(2026, 11, 19));
    await runBackgroundEntry([_id],
        channel: _channel, labeler: RuleLabeler(rules: rules, history: FakeHistoryReader(history: {'SM.0712345678': [4, 3]})));
    expect(done['outcome'], kBgParsed);
    expect(done.containsKey('askCategoryId'), isFalse);
    SharedPreferences.setMockInitialValues({});
    await runBackgroundEntry([_id], channel: _channel);
    expect(done.containsKey('askCategoryId'), isFalse);
  });

  test('an undone code (duplicate) never asks the question', () async {
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime(2026, 11, 19));
    final undone = FakeUndoneCodes();
    await undone.add('QWE1R2T3Y4', now: DateTime.now());
    await runBackgroundEntry([_id],
        channel: _channel, undone: undone, labeler: RuleLabeler(rules: rules, history: FakeHistoryReader()));
    expect(done['outcome'], kBgDuplicate);
    expect(done.containsKey('askCategoryId'), isFalse);
  });

  test('without a rule store the item is stored exactly as before (no hint fields)', () async {
    await runBackgroundEntry([_id], channel: _channel);
    final v = (await pendingValues()).single;
    expect(v, isNot(contains('"rk"')));
    expect(v, isNot(contains('"rl"')));
    expect(done['outcome'], kBgParsed);
  });

  test('a code in the undone list is a duplicate: not stored, held message acked', () async {
    final undone = FakeUndoneCodes();
    await undone.add('QWE1R2T3Y4', now: DateTime.now());
    await runBackgroundEntry([_id],
        channel: _channel,
        undone: undone,
        labeler: RuleLabeler(rules: FakeRuleStore(), history: FakeHistoryReader()));
    expect(done['outcome'], kBgDuplicate);
    expect(await pendingValues(), isEmpty);
    expect(acked, isTrue);
  });

  test('an expired undone code is offered again', () async {
    final undone = FakeUndoneCodes();
    await undone.add('QWE1R2T3Y4', now: DateTime.now().subtract(const Duration(hours: 25)));
    await runBackgroundEntry([_id],
        channel: _channel,
        undone: undone,
        labeler: RuleLabeler(rules: FakeRuleStore(), history: FakeHistoryReader()));
    expect(done['outcome'], kBgParsed);
    expect(await pendingValues(), hasLength(1));
  });

  test('Record receiver details OFF in preferences: the item is stored with no hint', () async {
    SharedPreferences.setMockInitialValues({'capture_identity_preference': false});
    final rules = FakeRuleStore();
    await rules.setLevel(ReceiverType.sendMoney, '0712345678',
        name: 'Jane', level: RuleLevel.askFirst, categoryId: 7, at: DateTime(2026, 11, 19));
    await runBackgroundEntry([_id],
        channel: _channel,
        labeler: RuleLabeler(
            rules: rules,
            history: FakeHistoryReader(history: {'SM.0712345678': [1]}),
            recordReceiverDetails: readRecordReceiverDetails));
    expect(done['outcome'], kBgParsed);
    expect((await pendingValues()).single, isNot(contains('"rk"')));
  });

  group('static: background only reads, logs nothing', () {
    final files = [
      ...Directory('lib/autoread/history').listSync().whereType<File>(),
      File('lib/autoread/background/labelling_pending_store.dart'),
      File('lib/autoread/background/parse_entry.dart'),
    ];

    test('no database write in the read side (history readers, labeler, background)', () {
      final write = RegExp(r'\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE)\b|\.execute\(|\.insert\(|\.update\(|\.delete\(|\.batch\(|rawInsert|rawUpdate|rawDelete');
      for (final f in files) {
        // The summary WRITER is app-only and writes preferences, not the database; it is checked separately.
        final text = f.readAsStringSync();
        expect(write.hasMatch(text), isFalse, reason: f.path);
      }
    });

    test('the background and the readers never import the app database or write a rule or the summary', () {
      for (final f in files) {
        if (f.path.endsWith('history_summary_writer.dart')) continue;
        final text = f.readAsStringSync();
        expect(text, isNot(contains('app_database.dart')), reason: f.path);
        expect(RegExp(r'\.(setLevel|forget|wipeAll)\(').hasMatch(text), isFalse, reason: f.path);
        expect(RegExp(r'\.setString\(|\.setInt\(|\.setBool\(|\.setStringList\(|prefs\.remove\(|p\.remove\(').hasMatch(text), isFalse, reason: f.path);
      }
    });

    test('no print, debugPrint or log call anywhere in these files', () {
      final log = RegExp(r'\bprint\(|debugPrint\(|\blog\(|developer\.|stderr|stdout');
      for (final f in files) {
        expect(log.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    });

    test('the standard build cannot reach them: only autoread code imports the history folder', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final p = f.path.replaceAll('\\', '/');
        if (p.startsWith('lib/autoread/')) continue;
        expect(f.readAsStringSync(), isNot(contains('autoread/history')), reason: p);
      }
    });
  });
}
