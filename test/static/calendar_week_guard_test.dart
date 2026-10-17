// CW1 guard: the calendar week is the only week model. FAILS if the old moving
// seven-day wording or API comes back anywhere under lib/.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = <String, RegExp>{
  'Last 7 days wording': RegExp(r'last 7 days', caseSensitive: false),
  'prior week caption': RegExp(r'prior week', caseSensitive: false),
  'lastSevenDays API': RegExp(r'lastSevenDays'),
  'rolling week': RegExp(r'rolling\s+(7|seven)', caseSensitive: false),
};

/// F4 (R4, PM-approved text): What's new card 2 NAMES the old model on purpose
/// ("Before, a week meant the last 7 days ...") to say it was corrected. Only this
/// exact phrase is allowed; any other use of the old wording is still caught.
const _history = 'Before, a week meant the last 7 days: today and the 6 days before it.';

List<String> scanOldWeek(String path, String text) {
  final out = <String>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(_history)) continue;
    for (final e in _banned.entries) {
      if (e.value.hasMatch(lines[i])) out.add('$path:${i + 1} ${e.key}');
    }
  }
  return out;
}

void main() {
  test('no rolling seven-day week wording or API is left in lib/', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      bad.addAll(scanOldWeek(f.path.replaceAll('\\', '/'), f.readAsStringSync()));
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('the scan can fail: each old form is caught (negative case)', () {
    expect(scanOldWeek('x', "vs: 'vs prior week',"), hasLength(1));
    expect(scanOldWeek('x', "spent: 'Spent in the last 7 days'"), hasLength(1));
    expect(scanOldWeek('x', 'AnalyticsPeriod.lastSevenDays(today)'), hasLength(1));
    expect(scanOldWeek('x', '/// a rolling 7 days ending on the anchor'), hasLength(1));
    expect(scanOldWeek('x', "'vs last week' and 'Spent this week'"), isEmpty);
    // F4: the one allowed phrase is narrow; the same words anywhere else are still caught.
    expect(scanOldWeek('x', "'$_history '"), isEmpty);
    expect(scanOldWeek('x', "'Home shows the last 7 days.'"), hasLength(1));
  });
}
