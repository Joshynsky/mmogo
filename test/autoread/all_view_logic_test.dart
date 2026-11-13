@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/logic/all_view_logic.dart';
import 'package:mmogo/autoread/logic/waiting_logic.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';

import '../support/waiting_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 10, 18, 10, 0);

  test('the To do number is To parse + To categorize; unreadable and gone rows are not in it', () {
    final waiting = waitingSet(WaitingDataSet.typical, now).items;
    expect(todoCount(waiting, now), parseCount(waiting, now) + categorizeCount(waiting, now));
    expect(todoCount(waiting, now), 3 + 3);
  });

  test('empty in, zero out', () {
    expect(todoCount(const <WaitingItem>[], now), 0);
  });
}
