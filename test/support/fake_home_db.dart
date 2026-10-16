// A small stand-in Database for Home (HomeDashboardDao's four queries), shared
// by the S11b text-size matrix. Same idea as the private fake in
// test/ui/screens/home_screen_test.dart: a real sqflite database hangs inside
// testWidgets here. Invented rows only.
import 'package:mmogo/domain/home/home_period.dart';
import 'package:mmogo/domain/money/spent_amount.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeHomeDb implements Database {
  FakeHomeDb({required this.now, this.thisTotal = 0, this.priorTotal = 0, this.types = const {}, this.recentCount = 0});

  final DateTime now;
  final int thisTotal;
  final int priorTotal;

  /// source_type -> (total cents, cost cents)
  final Map<String, (int, int)> types;
  final int recentCount;

  static const _codes = ['BUY_GOODS', 'SEND_MONEY', 'CASH', 'PAYBILL'];

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async => 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    if (sql.contains('GROUP BY source_type')) {
      return [
        for (final e in types.entries) {'source_type': e.key, 'total': e.value.$1, 'cost': e.value.$2},
      ];
    }
    if (sql.contains('JOIN classifications')) {
      final limit = arguments!.single as int;
      return [
        for (var i = 0; i < recentCount && i < limit; i++)
          {
            'id': i + 1,
            'display_code': 'CODE$i',
            'source_type': _codes[i % 4],
            'amount_cents': 1000 * (i + 1),
            'counterparty_label': 'PARTY NUMBER ${i + 1} WITH A VERY LONG NAME THAT MUST ELLIPSISE',
            'transaction_occurred_at': now.subtract(Duration(hours: i)).millisecondsSinceEpoch,
            'classification_name': 'Lunch',
          },
      ];
    }
    if (sql.contains(kSpentCentsSql)) {
      final start = arguments!.first as int;
      final currentStarts = {for (final p in HomePeriod.values) p.bounds(now).$1};
      return [
        {'total': currentStarts.contains(start) ? thisTotal : priorTotal},
      ];
    }
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
