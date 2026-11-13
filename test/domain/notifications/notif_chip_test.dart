import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/notifications/notif_chip.dart';

void main() {
  test('without auto-read only News is available (no chip row)', () {
    expect(availableChips(autoReadCompiled: false), [NotifChip.news]);
  });

  test('with auto-read two chips in order: To do, News', () {
    expect(availableChips(autoReadCompiled: true), [NotifChip.todo, NotifChip.news]);
  });

  test('every chip but News opens To do', () {
    expect([for (final c in NotifChip.values) if (c.opensTodo) c.name],
        ['all', 'parse', 'categorize', 'todo']);
  });
}
