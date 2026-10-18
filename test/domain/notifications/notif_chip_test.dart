import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';

void main() {
  test('without auto-read only News is available (no chip row)', () {
    expect(availableChips(autoReadCompiled: false), [NotifChip.news]);
  });

  test('with auto-read all four chips in order', () {
    expect(availableChips(autoReadCompiled: true),
        [NotifChip.all, NotifChip.parse, NotifChip.categorize, NotifChip.news]);
  });
}
