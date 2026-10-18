// §AUTOREAD.SERVICE: the held-message to waiting-item service.
@Tags(['autoread'])
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';
import 'package:mmogo/autoread/service/autoread_service.dart';

import '../../domain/parsing/sample_messages.dart';
import '../../support/pending_store_stand_in.dart';

class _Saved implements CodeLookup {
  final Set<String> codes;
  _Saved([this.codes = const {}]);
  @override
  Future<bool> contains(String displayCode) async => codes.contains(displayCode);
}

const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
final _t0 = DateTime.utc(2026, 10, 18, 8, 0);

void main() {
  late FakeAutoReadBridge bridge;
  late InMemoryPendingStore store;
  late AutoReadService service;
  var now = _t0;

  AutoReadService build({Set<String> saved = const {}, int capacity = 200}) {
    store = InMemoryPendingStore(capacity: capacity);
    return AutoReadService(
      bridge: bridge,
      store: store,
      savedCodes: _Saved(saved),
      now: () => now,
    );
  }

  setUp(() {
    now = _t0.add(const Duration(minutes: 1));
    bridge = FakeAutoReadBridge(now: () => now);
    service = build();
  });

  test('happy path: parsed, stored as waitingCategory, then acked', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    expect(await service.parse(_id), ParseOutcome.parsed);
    final items = await store.list();
    expect(items, hasLength(1));
    expect(items.single.id, _id);
    expect(items.single.parsed!.code, 'QWE1R2T3Y4');
    expect(items.single.parsed!.amountCents, 50000);
    expect(bridge.isHeld(_id), isFalse);
    expect(bridge.isClaimed(_id), isFalse);
    expect(service.lastFailure, isNull);
  });

  test('non-M-Pesa text: couldNotRead and the message stays held', () async {
    bridge.hold(_id, 'Hello, lunch at one?', _t0);
    expect(await service.parse(_id), ParseOutcome.couldNotRead);
    expect(service.lastFailure, ParseFailure.notRecognised);
    expect(bridge.isHeld(_id), isTrue);
    expect(await store.count(), 0);
    expect(bridge.isClaimed(_id), isFalse);
  });

  test('over 2,000 characters: couldNotRead, nothing stored, stays held', () async {
    bridge.hold(_id, '$kSampleSendMoney${' ' * 2000}', _t0);
    expect(await service.parse(_id), ParseOutcome.couldNotRead);
    expect(service.lastFailure, ParseFailure.tooLong);
    expect(await store.count(), 0);
    expect(bridge.isHeld(_id), isTrue);
  });

  test('exactly 2,000 characters is still read', () async {
    final body = kSampleSendMoney.padRight(2000);
    expect(body.length, 2000);
    bridge.hold(_id, body, _t0);
    expect(await service.parse(_id), ParseOutcome.parsed);
  });

  test('expired id: gone', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    now = _t0.add(const Duration(hours: 25));
    expect(await service.parse(_id), ParseOutcome.gone);
    expect(await store.count(), 0);
    expect(bridge.isClaimed(_id), isFalse);
  });

  test('missing id: gone', () async {
    expect(await service.parse(_id), ParseOutcome.gone);
  });

  test('invalid id: gone and no bridge call', () async {
    for (final bad in ['', 'short', '../etc/passwd', 'A1B2C3D4E5F60718293A4B5C6D7E8F90', '${_id}0']) {
      expect(await service.parse(bad), ParseOutcome.gone);
    }
    expect(bridge.calls, isEmpty);
  });

  test('duplicate: same code and identical fields is a silent duplicate, acked', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    expect(await service.parse(_id), ParseOutcome.parsed);
    const id2 = 'ffffffffffffffffffffffffffffffff';
    bridge.hold(id2, kSampleSendMoney, _t0);
    expect(await service.parse(id2), ParseOutcome.duplicate);
    expect(await store.count(), 1);
    expect(bridge.isHeld(id2), isFalse);
  });

  test('same code, different fields: parsed and flagged', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    await service.parse(_id);
    const id2 = 'ffffffffffffffffffffffffffffffff';
    bridge.hold(id2, kSampleSendMoney.replaceFirst('Ksh500.00', 'Ksh900.00'), _t0);
    expect(await service.parse(id2), ParseOutcome.parsed);
    final items = await store.list();
    expect(items, hasLength(2));
    expect(items.last.sameCodeDifferentDetails, isTrue);
    expect(bridge.isHeld(id2), isFalse);
  });

  test('saved code: duplicate, acked, nothing stored', () async {
    service = build(saved: {'QWE1R2T3Y4'});
    bridge.hold(_id, kSampleSendMoney, _t0);
    expect(await service.parse(_id), ParseOutcome.duplicate);
    expect(await store.count(), 0);
    expect(bridge.isHeld(_id), isFalse);
  });

  test('queue full: couldNotRead, stays held, lastFailure queueFull', () async {
    service = build(capacity: 0);
    bridge.hold(_id, kSampleSendMoney, _t0);
    expect(await service.parse(_id), ParseOutcome.couldNotRead);
    expect(service.lastFailure, ParseFailure.queueFull);
    expect(bridge.isHeld(_id), isTrue);
    expect(bridge.isClaimed(_id), isFalse);
  });

  test('stale generation: not acked, treated as gone', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    bridge.generation = 7; // the store is still on 1
    expect(await service.parse(_id), ParseOutcome.gone);
    expect(bridge.isHeld(_id), isTrue);
    expect(bridge.calls.where((c) => c.startsWith('ackHeld')), isEmpty);
    expect(await store.count(), 0);
  });

  test('a second concurrent parse of the same id writes once', () async {
    final gate = Completer<void>();
    bridge.peekGate = gate.future;
    bridge.hold(_id, kSampleSendMoney, _t0);
    final first = service.parse(_id);
    await Future<void>.delayed(Duration.zero);
    final second = await service.parse(_id);
    expect(second, anyOf(ParseOutcome.gone, ParseOutcome.duplicate));
    gate.complete();
    expect(await first, ParseOutcome.parsed);
    expect(store.writes, 1);
    expect(bridge.isClaimed(_id), isFalse);
  });

  test('crash after the write (ack throws), then retry: duplicate', () async {
    bridge.hold(_id, kSampleSendMoney, _t0);
    bridge.ackError = StateError('simulated crash');
    await expectLater(service.parse(_id), throwsStateError);
    expect(await store.count(), 1);
    expect(bridge.isHeld(_id), isTrue);
    expect(bridge.isClaimed(_id), isFalse);
    bridge.ackError = null;
    expect(await service.parse(_id), ParseOutcome.duplicate);
    expect(await store.count(), 1);
    expect(store.writes, 1);
    expect(bridge.isHeld(_id), isFalse);
  });

  test('the claim is released after every outcome', () async {
    bridge.hold(_id, 'not a message', _t0);
    await service.parse(_id);
    expect(bridge.isClaimed(_id), isFalse);
    bridge.hold(_id, kSampleSendMoney, _t0);
    await service.parse(_id);
    expect(bridge.isClaimed(_id), isFalse);
  });

  test('the body never appears in anything printed', () async {
    final printed = <String>[];
    final oldDebugPrint = debugPrint;
    debugPrint = (String? m, {int? wrapWidth}) => printed.add(m ?? '');
    try {
      await runZoned(() async {
        bridge.hold(_id, kSampleSendMoney, _t0);
        await service.parse(_id); // parsed
        const id2 = 'ffffffffffffffffffffffffffffffff';
        bridge.hold(id2, kSampleSendMoney, _t0);
        await service.parse(id2); // duplicate
        const id3 = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
        bridge.hold(id3, 'JANE DOE secret words 0712345678', _t0);
        await service.parse(id3); // couldNotRead
      }, zoneSpecification: ZoneSpecification(print: (s, p, z, line) => printed.add(line)));
    } finally {
      debugPrint = oldDebugPrint;
    }
    final all = printed.join('\n');
    expect(all, isNot(contains('JANE')));
    expect(all, isNot(contains('0712345678')));
    expect(all, isNot(contains('Confirmed')));
    expect(all, isNot(contains('secret words')));
    // And the held message's own text form leaves the body out.
    expect(bridge.toString(), isNot(contains('Confirmed')));
  });
}
