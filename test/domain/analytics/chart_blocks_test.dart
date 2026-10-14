// 0.1.2 S6b (PH1 / M10 / H3): the pure maths behind Month by weeks, All time
// five-year blocks, Custom calendar-week blocks, the Year amount form and the
// bar tooltips (lib/domain/analytics/chart_blocks.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';

String r(MonthWeekSegment s) => '${s.rangeLabel}:${s.days}';

void main() {
  group('Month by weeks (Monday first)', () {
    test('31-day month starting on Saturday (Aug 2026): a 2-day first and a 1-day last segment', () {
      final s = monthWeekSegments(DateTime(2026, 8, 17));
      expect(s.map(r), ['1-2:2', '3-9:7', '10-16:7', '17-23:7', '24-30:7', '31:1']);
      expect(s.map((x) => x.part), [true, false, false, false, false, true]);
      expect(s.first.crossLine, 'Week crosses into July');
      expect(s.last.crossLine, 'Week crosses into September');
      expect(s[2].crossLine, isNull);
      expect(s.last.rangeLabel, '31', reason: 'a one-day segment shows one number');
      expect(s.last.daysLabel, '1 day');
      expect(s.first.daysLabel, '2 days');
    });

    test('30-day month (Sep 2026): a 6-day first and a 3-day last segment', () {
      final s = monthWeekSegments(DateTime(2026, 9, 1));
      expect(s.map(r), ['1-6:6', '7-13:7', '14-20:7', '21-27:7', '28-30:3']);
      expect(s.first.crossLine, 'Week crosses into August');
      expect(s.last.crossLine, 'Week crosses into October');
    });

    test('February: 28 days (2026), a month that is exactly four weeks (2027), and a leap day (2028)', () {
      expect(monthWeekSegments(DateTime(2026, 2, 10)).map(r), ['1:1', '2-8:7', '9-15:7', '16-22:7', '23-28:6']);
      final exact = monthWeekSegments(DateTime(2027, 2, 10));
      expect(exact.map(r), ['1-7:7', '8-14:7', '15-21:7', '22-28:7']);
      expect(exact.any((x) => x.part), isFalse);
      expect(exact.every((x) => x.crossLine == null), isTrue);
      final leap = monthWeekSegments(DateTime(2028, 2, 10));
      expect(leap.map(r), ['1-6:6', '7-13:7', '14-20:7', '21-27:7', '28-29:2']);
      expect(leap.fold<int>(0, (a, x) => a + x.days), 29);
    });

    test('segments hold only the month: the days add up and never leave it', () {
      for (final m in [DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 2), DateTime(2028, 2), DateTime(2026, 12)]) {
        final s = monthWeekSegments(m);
        final len = DateTime(m.year, m.month + 1, 0).day;
        expect(s.fold<int>(0, (a, x) => a + x.days), len);
        expect(s.first.start, DateTime(m.year, m.month, 1));
        expect(s.last.end, DateTime(m.year, m.month, len));
        expect(s.every((x) => x.start.month == m.month && x.end.month == m.month), isTrue);
      }
    });

    test('a Sunday-first week changes the cut', () {
      // Sep 2026 starts on a Tuesday; Sunday weeks: 1-5, 6-12, 13-19, 20-26, 27-30.
      final s = monthWeekSegments(DateTime(2026, 9, 1), firstDay: 7);
      expect(s.map(r), ['1-5:5', '6-12:7', '13-19:7', '20-26:7', '27-30:4']);
    });

    test('elapsed days count only the days up to today', () {
      final s = monthWeekSegments(DateTime(2026, 9, 1));
      final today = DateTime(2026, 9, 24); // Thursday of the 21-27 segment
      expect(s[3].elapsed(today), 4);
      expect(s[2].elapsed(today), 7);
      expect(s[4].elapsed(today), 0, reason: 'not started');
    });
  });

  group('Month by days labels', () {
    test('the 1st, every 5th and the last; a 5th-day label is dropped next to the last', () {
      List<String> shown(int n) => [for (var d = 1; d <= n; d++) monthDayLabel(d, n)].where((x) => x.isNotEmpty).toList();
      expect(shown(31), ['1', '5', '10', '15', '20', '25', '31'], reason: '30 is dropped: it would touch 31');
      expect(shown(30), ['1', '5', '10', '15', '20', '25', '30']);
      expect(shown(28), ['1', '5', '10', '15', '20', '25', '28']);
      expect(shown(29), ['1', '5', '10', '15', '20', '25', '29']);
    });
  });

  group('All time five-year blocks', () {
    test('blocks follow the digits: a block starts in a year ending in 1 or 6', () {
      expect(allTimeBlockStart(2021), 2021);
      expect(allTimeBlockStart(2025), 2021);
      expect(allTimeBlockStart(2026), 2026);
      expect(allTimeBlockStart(2030), 2026);
      expect(allTimeBlockStart(2031), 2031);
      expect(allTimeBlockStart(2035), 2031);
    });

    test('steps back by whole blocks from the one holding today, never forward', () {
      final today = DateTime(2026, 10, 14);
      expect(allTimeBlockStartAt(today, 0), 2026);
      expect(allTimeBlockStartAt(today, -1), 2021);
      expect(allTimeBlockStartAt(today, 1), 2026, reason: 'never into the future');
    });
  });

  group('Custom blocks over 31 days', () {
    test('Monday weeks, clipped at both ends', () {
      // Thu 20 Aug to Thu 24 Sep 2026 = 36 days.
      final b = customWeekBlocks(DateTime(2026, 8, 20), DateTime(2026, 9, 24));
      expect(b.map((x) => '${x.start.month}/${x.start.day}-${x.end.month}/${x.end.day}'), [
        '8/20-8/23',
        '8/24-8/30',
        '8/31-9/6',
        '9/7-9/13',
        '9/14-9/20',
        '9/21-9/24',
      ]);
      expect(b.map((x) => x.part), [true, false, false, false, false, true]);
      expect(b.fold<int>(0, (a, x) => a + x.days), 36);
    });

    test('32 days that start on a week start are clipped only at the end', () {
      final b = customWeekBlocks(DateTime(2026, 8, 24), DateTime(2026, 9, 24));
      expect(b, hasLength(5));
      expect(b.first.part, isFalse);
      expect(b.last.days, 4);
    });

    test('first day Sunday cuts the same dates differently', () {
      final b = customWeekBlocks(DateTime(2026, 8, 20), DateTime(2026, 9, 24), firstDay: 7);
      expect(b.map((x) => x.days), [3, 7, 7, 7, 7, 5]);
      expect(b.first.start, DateTime(2026, 8, 20));
      expect(b.first.end, DateTime(2026, 8, 22));
      expect(b[1].start, DateTime(2026, 8, 23), reason: 'a Sunday');
    });
  });

  group('Year amounts, compact form', () {
    test('the whole number when it fits the slot (4 characters at 24 wide), else 48k', () {
      expect(fitAmount(950, 24), '950');
      expect(fitAmount(4800, 24), '4800');
      expect(fitAmount(48000, 24), '48k');
      expect(fitAmount(12000, 24), '12k');
      expect(fitAmount(4812, 40), '4812', reason: 'a wider slot keeps the full number');
    });

    test('thousands keep one decimal below 10k, millions use M', () {
      expect(fitAmount(4800.4, 12), '4.8k');
      expect(fitAmount(2000, 12), '2k');
      expect(fitAmount(1234567, 24), '1.2M');
      expect(fitAmount(12000000, 24), '12M');
    });
  });

  group('tooltips', () {
    test('a day: weekday and date, the amount, the open line', () {
      expect(dayTipLines(DateTime(2026, 9, 2), 125000), ['Wed 2 Sep', 'Ksh 1,250', 'Tap again to open the day']);
    });

    test('a week segment: days in the month, total with the average, "so far" while it runs', () {
      final seg = monthWeekSegments(DateTime(2026, 9, 1))[3]; // 21-27 Sep
      final lines = weekTipLines(seg, 140000, DateTime(2026, 9, 24));
      expect(lines[0], '21-27 Sep · 7 days');
      expect(lines[1], 'Ksh 1,400 · avg Ksh 350/day so far');
      expect(lines[2], 'Tap again to open the week');
      final done = weekTipLines(monthWeekSegments(DateTime(2026, 9, 1))[1], 70000, DateTime(2026, 9, 24));
      expect(done[1], 'Ksh 700 · avg Ksh 100/day');
      expect(weekSegmentName(monthWeekSegments(DateTime(2026, 8, 1)).last), '31 Aug, 1 day');
    });
  });
}
