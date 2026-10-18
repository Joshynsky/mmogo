@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/ui/bell_spoken.dart';

void main() {
  String l({bool u = false, bool n = false, int r = 0, int w = 0}) =>
      bellSpokenLabelAutoRead(update: u, newNotice: n, readyToParse: r, waiting: w);

  test('nothing present', () => expect(l(), 'Notifications'));

  test('full example from the mock', () {
    expect(
      l(u: true, n: true, r: 2, w: 3),
      'Notifications, 1 update available, 3 messages waiting for a category, 2 messages ready to parse, 1 new notice',
    );
  });

  test('singular', () {
    expect(l(w: 1), 'Notifications, 1 message waiting for a category');
    expect(l(r: 1), 'Notifications, 1 message ready to parse');
  });

  test('counts above 99 say 99 or more', () {
    expect(l(w: 100, r: 250), 'Notifications, 99 or more messages waiting for a category, 99 or more messages ready to parse');
    expect(l(w: 99), 'Notifications, 99 messages waiting for a category');
  });

  test('always starts with Notifications', () {
    for (final u in [true, false]) {
      for (final r in [0, 1, 120]) {
        expect(l(u: u, r: r, w: r), startsWith('Notifications'));
      }
    }
  });
}
