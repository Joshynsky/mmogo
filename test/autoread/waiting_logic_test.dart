@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';

import '../support/waiting_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 10, 0);
  var n = 1;
  WaitingItem ready(Duration age, {WaitingKind kind = WaitingKind.readyToParse}) =>
      WaitingItem(id: heldIdFor(n++), kind: kind, heldAt: now.subtract(age));
  WaitingItem cat(Duration age) {
    final at = now.subtract(age);
    return WaitingItem(
        id: heldIdFor(n++), kind: WaitingKind.waitingCategory, heldAt: at, parsed: sampleFields(0, at));
  }

  group('id validation', () {
    test('accepts 32 lowercase hex', () {
      expect(isValidHeldId('0123456789abcdef0123456789abcdef'), isTrue);
    });
    test('rejects wrong length, upper case and non-hex', () {
      expect(isValidHeldId('0123456789abcdef0123456789abcde'), isFalse);
      expect(isValidHeldId('0123456789abcdef0123456789abcdef0'), isFalse);
      expect(isValidHeldId('0123456789ABCDEF0123456789abcdef'), isFalse);
      expect(isValidHeldId('0123456789abcdef0123456789abcdeg'), isFalse);
      expect(isValidHeldId('../../0123456789abcdef01234567'), isFalse);
      expect(isValidHeldId(''), isFalse);
      expect(isValidHeldId('0123456789abcdef0123456789abcdef\n'), isFalse);
    });
    test('a WaitingItem with a bad id throws', () {
      expect(() => WaitingItem(id: 'X', kind: WaitingKind.gone, heldAt: now), throwsArgumentError);
    });
    test('a waiting-category item needs parsed fields', () {
      expect(() => WaitingItem(id: heldIdFor(1), kind: WaitingKind.waitingCategory, heldAt: now),
          throwsArgumentError);
    });
  });

  group('expiresAt and effectiveKind', () {
    test('expiresAt is heldAt plus kHeldWindow', () {
      final i = ready(const Duration(hours: 1));
      expect(i.expiresAt, i.heldAt.add(kHeldWindow));
    });
    test('inside the window stays ready', () {
      expect(effectiveKind(ready(kHeldWindow - const Duration(seconds: 1)), now), WaitingKind.readyToParse);
    });
    test('at the window it is gone, even though the stored kind is ready', () {
      expect(effectiveKind(ready(kHeldWindow), now), WaitingKind.gone);
    });
    test('an unreadable item past the window is gone; before it stays unreadable', () {
      expect(effectiveKind(ready(kHeldWindow, kind: WaitingKind.unreadable), now), WaitingKind.gone);
      expect(effectiveKind(ready(const Duration(hours: 1), kind: WaitingKind.unreadable), now),
          WaitingKind.unreadable);
    });
    test('a skewed-future heldAt counts as gone', () {
      final i = WaitingItem(
          id: heldIdFor(n++), kind: WaitingKind.readyToParse, heldAt: now.add(const Duration(days: 2)));
      expect(effectiveKind(i, now), WaitingKind.gone);
      expect(parseCount([i], now), 0);
    });
    test('a small future stamp inside the skew stays ready', () {
      final i = WaitingItem(
          id: heldIdFor(n++), kind: WaitingKind.readyToParse, heldAt: now.add(const Duration(minutes: 1)));
      expect(effectiveKind(i, now), WaitingKind.readyToParse);
    });
    test('a parsed waiting-category row is never turned into gone by age', () {
      expect(effectiveKind(cat(const Duration(days: 5)), now), WaitingKind.waitingCategory);
    });
  });

  group('counts', () {
    test('only readable ready items count for Parse; gone and unreadable do not', () {
      final items = [
        ready(const Duration(hours: 1)),
        ready(const Duration(hours: 2)),
        ready(const Duration(hours: 3), kind: WaitingKind.unreadable),
        ready(const Duration(hours: 3), kind: WaitingKind.gone),
        ready(kHeldWindow + const Duration(hours: 1)), // expired by age
        cat(const Duration(minutes: 5)),
      ];
      expect(parseCount(items, now), 2);
    });
    test('only waiting items count for Categorize', () {
      final items = [
        cat(const Duration(minutes: 5)),
        cat(const Duration(minutes: 9)),
        ready(const Duration(hours: 1)),
        ready(const Duration(hours: 3), kind: WaitingKind.gone),
      ];
      expect(categorizeCount(items, now), 2);
    });
    test('the Typical set gives Parse 3 and Categorize 3 as in the signed mock', () {
      final d = waitingSet(WaitingDataSet.typical, now).items;
      expect(parseCount(d, now), 3);
      expect(categorizeCount(d, now), 3);
    });
    test('the 99+ set has 12 ready and 120 waiting', () {
      final d = waitingSet(WaitingDataSet.many, now).items;
      expect(parseCount(d, now), 12);
      expect(categorizeCount(d, now), 120);
    });
    test('the Empty set counts zero', () {
      final d = waitingSet(WaitingDataSet.empty, now).items;
      expect(parseCount(d, now), 0);
      expect(categorizeCount(d, now), 0);
    });
  });

  group('sort', () {
    test('ready: soonest to expire first, unreadable and gone last', () {
      final a = ready(const Duration(hours: 2));
      final b = ready(const Duration(hours: 12));
      final u = ready(const Duration(hours: 22), kind: WaitingKind.unreadable);
      final g = ready(const Duration(hours: 40), kind: WaitingKind.gone);
      final e = ready(kHeldWindow + const Duration(hours: 1)); // expired, stored ready
      final out = sortReadyToParse([g, a, u, b, e], now);
      expect(out.take(2).toList(), [b, a]);
      expect(out.skip(2).toSet(), {u, g, e});
    });
    test('ready: waiting items are left out', () {
      final c = cat(const Duration(minutes: 5));
      expect(sortReadyToParse([c], now), isEmpty);
    });
    test('categorize: newest transaction first', () {
      final old = cat(const Duration(hours: 5));
      final mid = cat(const Duration(minutes: 90));
      final fresh = cat(const Duration(minutes: 25));
      expect(sortWaitingCategory([old, fresh, mid], now), [fresh, mid, old]);
    });
  });

  group('expiresInHours', () {
    test('rounds up to whole hours', () {
      final i = ready(kHeldWindow - const Duration(hours: 4));
      expect(expiresInHours(i, now), 4);
      final j = ready(kHeldWindow - const Duration(hours: 3, minutes: 30));
      expect(expiresInHours(j, now), 4);
      expect(expiresUnderOneHour(j, now), isFalse);
    });
    test('the last hour is "under one hour" and counts as 1', () {
      final i = ready(kHeldWindow - const Duration(minutes: 20));
      expect(expiresInHours(i, now), 1);
      expect(expiresUnderOneHour(i, now), isTrue);
    });
    test('0 when expired, gone, unreadable, waiting or skewed', () {
      expect(expiresInHours(ready(kHeldWindow), now), 0);
      expect(expiresInHours(ready(const Duration(hours: 1), kind: WaitingKind.gone), now), 0);
      expect(expiresInHours(ready(const Duration(hours: 1), kind: WaitingKind.unreadable), now), 0);
      expect(expiresInHours(cat(const Duration(hours: 1)), now), 0);
      final skew = WaitingItem(
          id: heldIdFor(n++), kind: WaitingKind.readyToParse, heldAt: now.add(const Duration(days: 2)));
      expect(expiresInHours(skew, now), 0);
    });
  });
}
