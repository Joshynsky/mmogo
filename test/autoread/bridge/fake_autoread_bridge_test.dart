// §AUTOREAD.BRIDGE: the in-memory fake follows the bridge rules.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/bridge/fake_autoread_bridge.dart';

const _id = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';
final _t0 = DateTime.utc(2026, 10, 18, 8, 0);

void main() {
  var now = _t0;
  late FakeAutoReadBridge b;
  setUp(() {
    now = _t0;
    b = FakeAutoReadBridge(now: () => now);
  });

  test('peek returns a held message; toString leaves the body out', () async {
    b.hold(_id, 'SECRET BODY', _t0);
    final m = await b.peekHeld(_id);
    expect(m!.body, 'SECRET BODY');
    expect(m.toString(), isNot(contains('SECRET')));
  });

  test('peek is null for invalid, missing and expired ids', () async {
    b.hold(_id, 'x', _t0);
    expect(await b.peekHeld('nope'), isNull);
    expect(await b.peekHeld('f' * 32), isNull);
    now = _t0.add(const Duration(hours: 24));
    expect(await b.peekHeld(_id), isNull);
    expect(await b.listHeldIds(), isEmpty);
  });

  test('claim is exclusive until ack or release', () async {
    b.hold(_id, 'x', _t0);
    expect(await b.claim(_id), isTrue);
    expect(await b.claim(_id), isFalse);
    await b.release(_id);
    expect(await b.claim(_id), isTrue);
    await b.ackHeld(_id, generation: await b.readGeneration());
    expect(b.isHeld(_id), isFalse);
    expect(await b.claim(_id), isTrue);
  });

  test('ack with a wrong generation keeps the message', () async {
    b.hold(_id, 'x', _t0);
    await b.ackHeld(_id, generation: 99);
    expect(b.isHeld(_id), isTrue);
  });

  test('listHeldIds lists unexpired ids; readGeneration answers', () async {
    b.hold(_id, 'x', _t0);
    expect(await b.listHeldIds(), [_id]);
    expect(await b.readGeneration(), 1);
  });
}
