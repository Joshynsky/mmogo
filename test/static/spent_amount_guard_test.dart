// SP1 guard: spending is computed in ONE place (domain/money/spent_amount.dart).
// This scan FAILS if a raw SUM(amount_cents) appears in a query under lib/, or
// if an Analytics or Home Dart total adds a row's raw amountCents. The allowed
// sites are listed here, each with its reason.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SQL sites where a raw SUM over the amount column is NOT a spending total.
const _allowedRawSumFiles = <String, String>{
  // The migration's before/after integrity digest compares stored values, it
  // does not report spending.
  'lib/data/db/migration_v3.dart': 'integrity digest, not spending',
};

/// Dart folders whose totals are spending totals (Analytics and Home).
const _spendingDartDirs = ['lib/ui/screens/analytics', 'lib/ui/screens/home'];

final _rawSum = RegExp(r'SUM\s*\(\s*(?:\w+\.)?amount_cents\s*\)', caseSensitive: false);
final _rawDartAdd = RegExp(r'\+\s*\w+\.amountCents\b');

/// Returns the offending "file:line" strings for [text] under [path].
List<String> scanRawSpending(String path, String text) {
  final out = <String>[];
  final lines = text.split('\n');
  final sqlAllowed = _allowedRawSumFiles.containsKey(path);
  final dartScanned = _spendingDartDirs.any(path.startsWith);
  for (var i = 0; i < lines.length; i++) {
    if (!sqlAllowed && _rawSum.hasMatch(lines[i])) out.add('$path:${i + 1} raw SUM(amount_cents)');
    if (dartScanned && _rawDartAdd.hasMatch(lines[i])) out.add('$path:${i + 1} raw amountCents added');
  }
  return out;
}

List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

String _norm(String p) => p.replaceAll('\\', '/');

void main() {
  test('no spending query or total under lib/ sums the raw amount', () {
    final bad = <String>[];
    for (final f in _libFiles()) {
      final path = _norm(f.path);
      bad.addAll(scanRawSpending(path, f.readAsStringSync()));
    }
    expect(bad, isEmpty, reason: 'Use spentCents / kSpentCentsSql / row.spent:\n${bad.join('\n')}');
  });

  test('the allowed raw-SUM sites still exist (a stale allowlist fails)', () {
    for (final path in _allowedRawSumFiles.keys) {
      expect(File(path).existsSync(), isTrue, reason: path);
      expect(_rawSum.hasMatch(File(path).readAsStringSync()), isTrue, reason: '$path no longer needs its allowance');
    }
  });

  test('the scan can fail: injected raw sums are caught (negative case)', () {
    expect(scanRawSpending('lib/data/db/home_dashboard_dao.dart', 'SELECT COALESCE(SUM(amount_cents), 0) FROM t'),
        hasLength(1));
    expect(scanRawSpending('lib/data/db/analytics_dao.dart', 'SELECT sum( t.amount_cents ) FROM transactions t'),
        hasLength(1));
    expect(scanRawSpending('lib/ui/screens/analytics/x.dart', '.fold<int>(0, (s, r) => s + r.amountCents)'),
        hasLength(1));
    expect(scanRawSpending('lib/ui/screens/home/x.dart', 'total += 1; x = a + p.amountCents;'), hasLength(1));
    // The sanctioned forms pass.
    expect(scanRawSpending('lib/data/db/home_dashboard_dao.dart', r'SUM($kSpentCentsSql)'), isEmpty);
    expect(scanRawSpending('lib/ui/screens/analytics/x.dart', '.fold<int>(0, (s, r) => s + r.spent)'), isEmpty);
  });

  test('the two Home queries and the Analytics view use the rule', () {
    final home = File('lib/data/db/home_dashboard_dao.dart').readAsStringSync();
    expect(RegExp(r'SUM\(\$kSpentCentsSql\)').allMatches(home).length, 2);
    final view = File('lib/ui/screens/analytics/analytics_view.dart').readAsStringSync();
    expect(view, contains('s + r.spent'));
  });
}
