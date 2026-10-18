// §AUTOREAD.HELD: the one held-window constant, the expiry rule and the copy.
// Tagged autoread so the tagged run covers it; it needs no define, so it also
// runs in the default run (never skipped).
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';

void main() {
  final heldAt = DateTime.utc(2026, 10, 18, 8, 0);

  group('heldExpired', () {
    test('the window is 24 hours', () => expect(kHeldWindow, const Duration(hours: 24)));

    test('just inside the window is kept', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow - const Duration(seconds: 1))), isFalse);
    });

    test('exactly the window is gone', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow)), isTrue);
    });

    test('past the window is gone', () {
      expect(heldExpired(heldAt, heldAt.add(kHeldWindow + const Duration(days: 3))), isTrue);
    });

    test('just received is kept', () => expect(heldExpired(heldAt, heldAt), isFalse));

    test('a small future stamp (within skew) is kept', () {
      expect(heldExpired(heldAt, heldAt.subtract(kHeldClockSkew)), isFalse);
      expect(heldExpired(heldAt, heldAt.subtract(const Duration(minutes: 1))), isFalse);
    });

    test('a stamp in the future by more than the skew is gone', () {
      expect(heldExpired(heldAt, heldAt.subtract(kHeldClockSkew + const Duration(seconds: 1))), isTrue);
      expect(heldExpired(heldAt, heldAt.subtract(const Duration(days: 2))), isTrue);
    });

    test('the window parameter is honoured', () {
      const w = Duration(hours: 2);
      expect(heldExpired(heldAt, heldAt.add(const Duration(hours: 1)), window: w), isFalse);
      expect(heldExpired(heldAt, heldAt.add(w), window: w), isTrue);
    });
  });

  group('copy follows the constant', () {
    test('default copy', () {
      expect(kHeldWindowCopy, 'Kept up to 24 hours, removed the next time mmogo runs after that.');
      expect(kHeldWindowCopy, heldWindowCopy(kHeldWindow));
    });

    test('the hour count in the copy equals kHeldWindow.inHours', () {
      expect(kHeldWindowCopy, contains('${kHeldWindow.inHours} hours'));
    });

    test('changing the window through the parameter changes the copy', () {
      expect(heldWindowCopy(const Duration(hours: 12)), contains('Kept up to 12 hours,'));
      expect(heldWindowCopy(const Duration(hours: 12)), isNot(contains('24')));
      expect(heldWindowCopy(const Duration(hours: 1)), contains('Kept up to 1 hour,'));
    });

    test('the copy never says "within"', () {
      expect(kHeldWindowCopy.toLowerCase(), isNot(contains('within')));
    });
  });
}
