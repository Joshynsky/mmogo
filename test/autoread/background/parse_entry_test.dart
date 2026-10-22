// The background parse: the Dart entry the headless engine runs for "Parse from the notification".
// A pretend Kotlin runner answers the channel (invented messages only, fake preferences). It checks
// the order the Judge's NARROW conditions demand: peek, parse, write, read back, THEN ack.
@Tags(['autoread'])
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/background/parse_entry.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/sample_messages.dart';

const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
const _id2 = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
const _channel = MethodChannel(kBackgroundChannel);

/// Plays Kotlin's ParseRunner for one engine: it answers only for [jobId], keeps the held bodies,
/// records every call (never a body) and checks what the real one checks.
class _FakeKotlin {
  _FakeKotlin(this.jobId);
  final String jobId;
  final Map<String, String> held = {};
  final List<String> calls = [];
  final List<Map<Object?, Object?>> doneArgs = [];
  bool ackRefused = false;
  bool bumpGenerationOnAck = false;
  Object? peekError;
  bool itemWrittenAtAck = false;

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments;
    final id = args is Map ? args['id'] : null;
    calls.add(call.method);
    switch (call.method) {
      case 'peekHeld':
        if (peekError != null) throw peekError!;
        final body = id == jobId ? held[jobId] : null;
        return body == null ? null : <String, Object?>{'id': id, 'body': body, 'receivedAtMs': DateTime.now().millisecondsSinceEpoch};
      case 'claim':
        return id == jobId;
      case 'release':
        return null;
      case 'ackHeld':
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        itemWrittenAtAck = prefs.getKeys().any((k) => k.startsWith(kPendingItemPrefix));
        if (bumpGenerationOnAck) {
          await prefs.setInt(kPendingGenerationKey, (prefs.getInt(kPendingGenerationKey) ?? 0) + 1);
        }
        final current = prefs.getInt(kPendingGenerationKey) ?? 0;
        if (ackRefused || (args as Map)['generation'] != current) return 'stale';
        held.remove(jobId);
        return 'acked';
      case 'done':
        doneArgs.add(Map<Object?, Object?>.of(args as Map));
        return null;
    }
    throw MissingPluginException();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _FakeKotlin kotlin;

  Future<Set<String>> pendingKeys() async {
    final p = await SharedPreferences.getInstance();
    await p.reload();
    return p.getKeys().where((k) => k.startsWith(kPendingItemPrefix)).toSet();
  }

  Future<void> run([String id = _id]) async {
    await runBackgroundEntry([id], channel: _channel);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    kotlin = _FakeKotlin(_id);
    messenger.setMockMethodCallHandler(_channel, kotlin.handle);
  });
  tearDown(() => messenger.setMockMethodCallHandler(_channel, null));

  test('a readable message: peek, write, read back, ack, then done(parsed, 1)', () async {
    kotlin.held[_id] = kSampleSendMoney;
    await run();
    // The service claims first (Kotlin's runner answers true for its own id), then peeks.
    expect(kotlin.calls.take(2), ['claim', 'peekHeld']);
    expect(kotlin.calls.indexOf('peekHeld'), lessThan(kotlin.calls.indexOf('ackHeld')));
    expect(kotlin.calls.where((c) => c == 'ackHeld'), hasLength(1));
    expect(kotlin.itemWrittenAtAck, isTrue, reason: 'the waiting item must be in preferences before the ack');
    expect(kotlin.calls.last, 'done');
    expect(kotlin.doneArgs.single, {'outcome': 'parsed', 'waiting': 1});
    expect(kotlin.held, isEmpty, reason: 'acked: the held copy is gone');
    expect(await pendingKeys(), {'$kPendingItemPrefix$_id'});
  });

  test('the parsed item is exactly what the app would store: parsed fields only, never the text', () async {
    kotlin.held[_id] = kSampleSendMoney;
    await run();
    final p = await SharedPreferences.getInstance();
    final stored = p.getString('$kPendingItemPrefix$_id')!;
    final item = decodePendingItem(stored)!;
    expect(item.id, _id);
    expect(item.parsed!.code, 'QWE1R2T3Y4');
    expect(item.parsed!.amountCents, 50000);
    expect(stored, isNot(contains('Confirmed')));
  });

  test('every reported value is a code and a number: no body, no id', () async {
    kotlin.held[_id] = kSampleSendMoney;
    await run();
    final d = kotlin.doneArgs.single;
    expect(d.keys.toSet(), {'outcome', 'waiting'});
    expect(d['outcome'], isIn(kBackgroundOutcomeCodes));
    expect(d['waiting'], isA<int>());
  });

  test('text that is not an M-Pesa message: nothing written, no ack, still held, done(unreadable)', () async {
    kotlin.held[_id] = 'Lunch at one? Bring the notes.';
    await run();
    expect(await pendingKeys(), isEmpty);
    expect(kotlin.calls, isNot(contains('ackHeld')));
    expect(kotlin.held.containsKey(_id), isTrue);
    expect(kotlin.doneArgs.single['outcome'], 'unreadable');
  });

  test('a message over 2,000 characters is unreadable, nothing written', () async {
    kotlin.held[_id] = '$kSampleSendMoney${' ' * 2000}';
    await run();
    expect(await pendingKeys(), isEmpty);
    expect(kotlin.held.containsKey(_id), isTrue);
    expect(kotlin.doneArgs.single['outcome'], 'unreadable');
  });

  test('the same payment held twice: the second ends as a duplicate, acked, one waiting item', () async {
    kotlin.held[_id] = kSampleSendMoney;
    await run();
    final k2 = _FakeKotlin(_id2)..held[_id2] = kSampleSendMoney;
    messenger.setMockMethodCallHandler(_channel, k2.handle);
    await run(_id2);
    expect(k2.doneArgs.single, {'outcome': 'duplicate', 'waiting': 1});
    expect(k2.held, isEmpty, reason: 'the duplicate is acked (the same item is already waiting)');
    expect(await pendingKeys(), {'$kPendingItemPrefix$_id'});
  });

  test('a message that expired or is gone: done(gone), nothing written, no ack', () async {
    await run(); // Kotlin holds nothing for this id
    expect(kotlin.doneArgs.single['outcome'], 'gone');
    expect(kotlin.calls, isNot(contains('ackHeld')));
    expect(await pendingKeys(), isEmpty);
  });

  test('a bad id never reaches Kotlin except as done(gone)', () async {
    await run('../../etc/passwd');
    expect(kotlin.calls, ['done']);
    expect(kotlin.doneArgs.single['outcome'], 'gone');
    await runBackgroundEntry(const [], channel: _channel);
    expect(kotlin.doneArgs.last['outcome'], 'gone');
  });

  test('Kotlin refuses the ack (Parse turned off): the item written is removed, done(stale), still held', () async {
    kotlin.held[_id] = kSampleSendMoney;
    kotlin.ackRefused = true;
    await run();
    expect(kotlin.doneArgs.single['outcome'], 'stale');
    expect(await pendingKeys(), isEmpty, reason: 'a refused ack must not leave a waiting item behind');
    expect(kotlin.held.containsKey(_id), isTrue);
  });

  test('the generation moves between the write and the ack (Delete data): stale, nothing left', () async {
    kotlin.held[_id] = kSampleSendMoney;
    kotlin.bumpGenerationOnAck = true;
    await run();
    expect(kotlin.doneArgs.single['outcome'], 'stale');
    expect(await pendingKeys(), isEmpty);
    expect(kotlin.held.containsKey(_id), isTrue);
  });

  test('a channel failure at peek: done(error), nothing written, no ack', () async {
    kotlin.held[_id] = kSampleSendMoney;
    kotlin.peekError = PlatformException(code: 'failed');
    await run();
    expect(kotlin.doneArgs.single['outcome'], 'error');
    expect(await pendingKeys(), isEmpty);
    expect(kotlin.calls, isNot(contains('ackHeld')));
  });

  test('done is sent once per run even when the reporter is asked twice', () async {
    final r = BackgroundReporter(_channel);
    await r.done('parsed', 1);
    await r.done('error', 0);
    expect(kotlin.doneArgs, hasLength(1));
    expect(kotlin.doneArgs.single['outcome'], 'parsed');
  });

  test('a second run for the same id after a successful one finds nothing (the ack deleted it)', () async {
    kotlin.held[_id] = kSampleSendMoney;
    await run();
    await run();
    expect(kotlin.doneArgs.map((d) => d['outcome']), ['parsed', 'gone']);
    expect(await pendingKeys(), hasLength(1));
  });

}
