// T20 — Home's time-of-day greeting (PM direct decision, 2026-09-24):
// before 12:00 morning, before 17:00 afternoon, otherwise evening; the name
// follows with a comma, and no name gives just the time of day.
import 'package:flutter_test/flutter_test.dart';
import 'package:mpesa_tracker/domain/home/home_greeting.dart';

DateTime _at(int h, [int m = 0, int s = 0]) => DateTime(2026, 9, 24, h, m, s);

void main() {
  group('time boundaries (with a name)', () {
    for (final (time, expected) in [
      (_at(0), 'Good morning Shyn,'),
      (_at(11, 59, 59), 'Good morning Shyn,'),
      (_at(12), 'Good afternoon Shyn,'),
      (_at(16, 59, 59), 'Good afternoon Shyn,'),
      (_at(17), 'Good evening Shyn,'),
      (_at(23, 59, 59), 'Good evening Shyn,'),
    ]) {
      test('${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:'
          '${time.second.toString().padLeft(2, '0')} -> "$expected"', () {
        expect(homeGreeting(time, 'Shyn'), expected);
      });
    }
  });

  group('no name: just the time of day (no "Welcome back")', () {
    test('null', () {
      expect(homeGreeting(_at(9), null), 'Good morning');
      expect(homeGreeting(_at(13), null), 'Good afternoon');
      expect(homeGreeting(_at(20), null), 'Good evening');
    });

    test('empty or whitespace-only counts as no name', () {
      expect(homeGreeting(_at(9), ''), 'Good morning');
      expect(homeGreeting(_at(9), '   '), 'Good morning');
    });
  });

  test('the name is trimmed', () {
    expect(homeGreeting(_at(18), '  Amina '), 'Good evening Amina,');
  });
}
