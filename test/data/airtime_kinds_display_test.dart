// WBS row 17: display, CSV, totals and privacy for the two Airtime categories
// (data layer only). Real in-memory database; invented data only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/model/waiting_item.dart';
import 'package:mmogo/data/db/analytics_dao.dart';
import 'package:mmogo/data/db/classification_dao.dart';
import 'package:mmogo/data/db/export_dao.dart';
import 'package:mmogo/data/db/home_dashboard_dao.dart';
import 'package:mmogo/domain/airtime/airtime_kind.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';
import 'package:mmogo/ui/screens/analytics/analytics_filters.dart';
import 'package:mmogo/ui/screens/analytics/where_breakdown.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../domain/parsing/sample_messages.dart';
import '../support/restore_test_db.dart';

void main() {
  late Database db;

  Future<int> idOf(String key) async =>
      (await db.rawQuery('SELECT id FROM classifications WHERE seed_key = ?', [key])).first['id']! as int;

  Future<void> addAirtime(String code, String key, int cents, {int at = 0}) async => db.insert('transactions', {
        'display_code': code,
        'source_type': 'AIRTIME',
        'amount_cents': cents,
        'transaction_cost_cents': 0,
        'classification_id': await idOf(key),
        'raw_parse_source': 'SMS_PARSE',
        'transaction_occurred_at': t0 + at,
        'created_at': t0,
      });

  setUp(() async {
    db = await openTestDb();
    await addAirtime('AIR0000001', kAirtimeSeedMyself, 1000, at: 1);
    await addAirtime('AIR0000002', kAirtimeSeedMyself, 2000, at: 2);
    await addAirtime('AIR0000003', kAirtimeSeedOther, 500, at: 3);
  });
  tearDown(() => db.close());

  test('csv_header_unchanged_11_names', () {
    expect(ExportDao.csvHeader, [
      'Date',
      'Type',
      'Classification Group',
      'Classification',
      'Counterparty Label',
      'Counterparty Phone',
      'Paybill Account Number',
      'Amount (KES)',
      'Transaction Cost (KES)',
      'M-Pesa/Cash Code',
      'Agent Number',
    ]);
  });

  test('csv_classification_values_for_myself_and_for_another_number', () async {
    final csv = ExportDao.toCsv(await ExportDao.activeTransactions(db));
    final lines = const LineSplitter().convert(csv);
    final own = lines.firstWhere((l) => l.contains('AIR0000001'));
    final oth = lines.firstWhere((l) => l.contains('AIR0000003'));
    expect(own, contains(',Airtime,For myself,'));
    expect(oth, contains(',Airtime,For another number,'));
    expect(csv, isNot(contains('0712345678')));
  });

  test('analytics_airtime_two_lines_sum_equals_group_total', () async {
    final rows = await AnalyticsDao.itemizedTransactions(db, types: {'AIRTIME'});
    final ranking = analyticsWhereRanking(rows, AnalyticsFilters.none);
    expect(ranking.map((n) => (n.name, n.cents, n.count)),
        [(kAirtimeNameMyself, 3000, 2), (kAirtimeNameOther, 500, 1)]);
    expect(ranking.fold<int>(0, (a, n) => a + n.cents), rows.fold<int>(0, (a, r) => a + r.spent));
  });

  test('analytics_zero_row_kind_hidden', () async {
    await db.delete('transactions', where: 'display_code = ?', whereArgs: ['AIR0000003']);
    final rows = await AnalyticsDao.itemizedTransactions(db, types: {'AIRTIME'});
    final ranking = analyticsWhereRanking(rows, AnalyticsFilters.none);
    expect(ranking.map((n) => n.name), [kAirtimeNameMyself]);
  });

  test('home_airtime_month_total_unchanged_by_split', () async {
    final totals = await HomeDashboardDao.sourceTypeTotals(db, startMs: t0, endMs: t0 + 100);
    expect(totals['AIRTIME']!.totalCents, 3500);
    expect(totals['AIRTIME']!.count, 3);
    // The month total is by source_type: the sum of both kinds.
    expect(totals['AIRTIME']!.totalCents, 1000 + 2000 + 500);
  });

  test('row_title_stays_airtime_type_name', () async {
    final recent = await HomeDashboardDao.recentTransactions(db, limit: 10);
    expect(recent.map((r) => r.displayName).toSet(), {'Airtime'});
    expect(recent.map((r) => r.classificationName).toSet(), {kAirtimeNameMyself, kAirtimeNameOther});
    final rows = await AnalyticsDao.itemizedTransactions(db, types: {'AIRTIME'});
    expect(rows.map((r) => r.classificationName).toSet(), {kAirtimeNameMyself, kAirtimeNameOther});
  });

  test('cash_picker_excludes_airtime_categories', () async {
    final names = (await ClassificationDao.fetchFlatActiveClassifications(db)).map((i) => i.name).toSet();
    expect(names, isNot(contains(kAirtimeNameMyself)));
    expect(names, isNot(contains(kAirtimeNameOther)));
    expect(names, isNot(contains('Airtime')));
  });

  test('no_screen_types_the_category_name_airtime', () {
    // Every literal 'Airtime' in lib/ is the TYPE name (or the frozen v3 seed).
    // A new file naming the category this way must be reviewed and added here.
    const typeNameFiles = {
      'lib/autoread/logic/message_details.dart',
      'lib/autoread/ui/categorize_details.dart',
      'lib/data/db/analytics_dao.dart',
      'lib/data/db/migration_v3_ddl.dart',
      'lib/domain/format/source_types.dart',
      'lib/domain/home/recent_transaction.dart',
      'lib/ui/screens/add/add_draft.dart',
      'lib/ui/screens/add/type_pills.dart',
    };
    final hits = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final text = f.readAsStringSync();
      if (text.contains("'Airtime'")) hits.add(f.path.replaceAll('\\', '/'));
    }
    expect(hits.difference(typeNameFiles), isEmpty, reason: 'new use of the literal Airtime: type name or category?');
    // And the live seed list does not name the category Airtime.
    expect(File('lib/data/db/schema.dart').readAsStringSync(), isNot(contains("name: 'Airtime'")));
  });

  test('privacy_scan_no_number_in_any_text_surface', () async {
    const digits = ['0712345678', '712345678'];
    final parsed = (SmsParser.parse(kSampleAirtimeOtherReal) as ParseSuccess).fields;
    expect(parsed.airtimeOther, isTrue);
    final surfaces = <String>[
      parsed.toString(),
      encodePendingItem(WaitingItem(
        id: '0' * 32,
        kind: WaitingKind.waitingCategory,
        heldAt: DateTime.fromMillisecondsSinceEpoch(1),
        parsed: parsed,
      )),
    ];
    // Saved as the parser sees it: the row goes into the other category.
    await db.insert('transactions', {
      'display_code': parsed.code,
      'source_type': 'AIRTIME',
      'amount_cents': parsed.amountCents,
      'transaction_cost_cents': parsed.transactionCostCents,
      'classification_id': await idOf(airtimeSeedKey(parsed.airtimeOther)),
      'raw_parse_source': 'SMS_PARSE',
      'transaction_occurred_at': parsed.transactionOccurredAt,
      'created_at': t0,
    });
    surfaces.add(utf8.decode(await backupOf(db).exportToBytes()));
    surfaces.add(ExportDao.toCsv(await ExportDao.activeTransactions(db)));
    for (final table in ['transactions', 'classifications', 'classification_groups', 'counterparty_classification_map']) {
      surfaces.add(jsonEncode(await db.rawQuery('SELECT * FROM $table')));
    }
    for (final s in surfaces) {
      for (final d in digits) {
        expect(s, isNot(contains(d)));
      }
    }
  });
}
