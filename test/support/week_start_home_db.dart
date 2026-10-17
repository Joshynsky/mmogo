// F5 (0.1.2 corrections): Home's SQL on top of the Analytics fake, so ONE fake
// database can serve a live Home and a live Analytics side by side (the
// week-start matrix tests). Sums rows by window and records every window
// Home asked for. Invented rows only.
import 'fake_analytics_db.dart';

/// Home's SQL on top of the Analytics fake: sums by window, records windows.
class WeekStartHomeDb extends FakeAnalyticsDb {
  WeekStartHomeDb(super.transactions);

  final sums = <(int, int)>[];

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  int _total(int s, int e) {
    var t = 0;
    for (final r in transactions) {
      final at = r['transaction_occurred_at'] as int;
      if (at >= s && at <= e) t += r['amount_cents'] as int;
    }
    return t;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('GROUP BY source_type')) {
      final s = arguments![0] as int;
      final e = arguments[1] as int;
      return [
        {'source_type': 'SEND_MONEY', 'total': _total(s, e), 'cost': 0, 'withdrawn': 0, 'n': 1},
      ];
    }
    if (sql.contains('COALESCE(SUM(')) {
      final s = arguments![0] as int;
      final e = arguments[1] as int;
      sums.add((s, e));
      return [
        {'total': _total(s, e)},
      ];
    }
    if (sql.contains('LIMIT ?')) {
      final newest = [...transactions]..sort((a, b) => (b['transaction_occurred_at'] as int).compareTo(a['transaction_occurred_at'] as int));
      return [
        for (final r in newest.take(arguments!.single as int))
          {
            'id': r['id'],
            'display_code': r['display_code'],
            'source_type': r['source_type'],
            'amount_cents': r['amount_cents'],
            'counterparty_label': r['counterparty_label'],
            'transaction_occurred_at': r['transaction_occurred_at'],
            'transaction_cost_cents': 0,
            'agent_number': null,
            'classification_name': 'Family/Friends',
          },
      ];
    }
    return super.rawQuery(sql, arguments);
  }
}
