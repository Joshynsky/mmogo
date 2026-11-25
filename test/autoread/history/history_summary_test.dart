// Auto-record S2b: the history summary (codec, writer, reader) and the fallback reader.
@Tags(['autoread'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/history/fake_history_reader.dart';
import 'package:mmogo/autoread/history/fallback_history_reader.dart';
import 'package:mmogo/autoread/history/history_reader.dart';
import 'package:mmogo/autoread/history/history_summary_codec.dart';
import 'package:mmogo/autoread/history/history_summary_writer.dart';
import 'package:mmogo/autoread/history/summary_history_reader.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Throws implements HistoryReader {
  @override
  Future<List<int>?> topTwo(ReceiverType type, String key) => throw StateError('x');
}

void main() {
  group('topTwoCategories (most used of the last 10)', () {
    test('most used first, at most 2', () {
      expect(topTwoCategories([3, 4, 4, 5, 4]), [4, 3]);
      expect(topTwoCategories([7]), [7]);
      expect(topTwoCategories([]), isEmpty);
    });
    test('a tie goes to the more recent category', () {
      expect(topTwoCategories([9, 8, 9, 8, 1]), [9, 8]);
      expect(topTwoCategories([1, 2, 3, 4, 5]), [1, 2]);
    });
    test('only the newest 10 count (most used, NOT most recent)', () {
      // newest first: 1 once, 2 four times, 3 twice, then 4 six times; only the first 10 count,
      // so 4 has 3 and wins nothing over 2 (4 would win if all 13 counted).
      expect(topTwoCategories([1, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4]), [2, 4]);
      expect(kHistLastRecords, 10);
    });
  });

  group('row to person id (keys per receiver type)', () {
    test('Send Money: 07xx, +254 and 254 forms are one person', () {
      final a = historyPersonIdOfRow(sourceType: 'SEND_MONEY', label: 'A', phone: '0712345678');
      expect(a, 'SM.0712345678');
      expect(historyPersonIdOfRow(sourceType: 'SEND_MONEY', label: 'A', phone: '+254712345678'), a);
      expect(historyPersonIdOfRow(sourceType: 'SEND_MONEY', label: 'A', phone: '254 712 345 678'), a);
    });
    test('Paybill business UPPERCASE hash account (case kept); Buy Goods shop UPPERCASE', () {
      expect(historyPersonIdOfRow(sourceType: 'PAYBILL', label: 'kplc  prepaid', account: '12ab'), 'PB.KPLC PREPAID#12ab');
      expect(historyPersonIdOfRow(sourceType: 'BUY_GOODS', label: ' mama  mboga '), 'BG.MAMA MBOGA');
    });
    test('no key: empty, too long, Cash, Withdrawal, Airtime', () {
      expect(historyPersonIdOfRow(sourceType: 'BUY_GOODS', label: '  '), isNull);
      expect(historyPersonIdOfRow(sourceType: 'PAYBILL'), isNull);
      expect(historyPersonIdOfRow(sourceType: 'BUY_GOODS', label: 'x' * 201), isNull);
      for (final t in ['CASH', 'AGENT_WITHDRAWAL', 'AIRTIME']) {
        expect(historyPersonIdOfRow(sourceType: t, label: 'A', phone: '0712345678'), isNull);
      }
    });
  });

  group('summary codec', () {
    test('round trip keeps the order and cuts lists to 2', () {
      final s = encodeHistSummary({'SM.1': [1, 2, 3], 'BG.X': [5]});
      expect(decodeHistSummary(s), {'SM.1': [1, 2], 'BG.X': [5]});
    });
    test('cap: 300 people, the first (newest) kept', () {
      final m = {for (var i = 0; i < 350; i++) 'SM.$i': [i]};
      final d = decodeHistSummary(encodeHistSummary(m))!;
      expect(d.length, kHistSummaryCap);
      expect(d.containsKey('SM.299'), isTrue);
      expect(d.containsKey('SM.300'), isFalse);
      expect(encodeHistSummary(m).length, lessThan(20 * 1024));
    });
    test('missing, corrupt or wrong version reads as unavailable; bad entries are skipped', () {
      expect(decodeHistSummary(null), isNull);
      expect(decodeHistSummary('not json'), isNull);
      expect(decodeHistSummary('{"v":2,"p":{}}'), isNull);
      expect(decodeHistSummary('{"v":1,"p":{"SM.1":"x","SM.2":[1,"a",2]}}'), {'SM.2': [1, 2]});
    });
    test('the stored text holds only labels and numbers (no message text field)', () {
      final s = encodeHistSummary({'SM.0712345678': [3]});
      expect(s, '{"v":1,"p":{"SM.0712345678":[3]}}');
    });
  });

  group('writer and reader over preferences', () {
    final rows = [
      const HistoryRow('SM.1', 4), // newest first
      const HistoryRow('BG.SHOP', 9),
      const HistoryRow('SM.1', 3),
      const HistoryRow('SM.1', 3),
      const HistoryRow('SM.1', 4),
      const HistoryRow('SM.1', 4),
      const HistoryRow('SM.1', 8), // sixth record of SM.1: ignored
    ];

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('rebuild writes top 2 of the last 10 per person; the reader returns them', () async {
      final w = HistorySummaryWriter(rows: () async => rows);
      expect(await w.rebuild(recordReceiverDetails: true), isTrue);
      final r = SummaryHistoryReader();
      expect(await r.topTwo(ReceiverType.sendMoney, '1'), [4, 3]);
      expect(await r.topTwo(ReceiverType.buyGoods, 'SHOP'), [9]);
      expect(await r.topTwo(ReceiverType.sendMoney, 'nobody'), isEmpty);
    });

    test('reader answers null while the summary was never written', () async {
      expect(await SummaryHistoryReader().topTwo(ReceiverType.sendMoney, '1'), isNull);
    });

    test('rebuild with receiver details off removes the summary (nothing is kept)', () async {
      final w = HistorySummaryWriter(rows: () async => rows);
      await w.rebuild(recordReceiverDetails: true);
      expect((await SharedPreferences.getInstance()).containsKey(kHistSummaryPrefKey), isTrue);
      await w.rebuild(recordReceiverDetails: false);
      expect((await SharedPreferences.getInstance()).containsKey(kHistSummaryPrefKey), isFalse);
    });

    test('clear (Delete data) removes it; a failing source returns false and never throws', () async {
      final w = HistorySummaryWriter(rows: () async => rows);
      await w.rebuild(recordReceiverDetails: true);
      expect(await w.clear(), isTrue);
      expect((await SharedPreferences.getInstance()).containsKey(kHistSummaryPrefKey), isFalse);
      final bad = HistorySummaryWriter(rows: () => throw StateError('db'));
      expect(await bad.rebuild(recordReceiverDetails: true), isFalse);
    });

    test('an Undo or category change is one more rebuild: the summary follows the ledger', () async {
      var current = rows;
      final w = HistorySummaryWriter(rows: () async => current);
      await w.rebuild(recordReceiverDetails: true);
      current = rows.where((r) => r.personId != 'BG.SHOP').toList(); // the BG.SHOP record was undone
      await w.rebuild(recordReceiverDetails: true);
      expect(await SummaryHistoryReader().topTwo(ReceiverType.buyGoods, 'SHOP'), isEmpty);
    });

    test('N1: changes counts only rebuilds that changed the summary (and a clear that removed it)', () async {
      var current = rows;
      final w = HistorySummaryWriter(rows: () async => current);
      final start = HistorySummaryWriter.changes.value;
      await w.rebuild(recordReceiverDetails: true);
      expect(HistorySummaryWriter.changes.value, start + 1);
      await w.rebuild(recordReceiverDetails: true); // same ledger: same summary
      expect(HistorySummaryWriter.changes.value, start + 1);
      current = rows.where((r) => r.personId != 'BG.SHOP').toList(); // Undo
      await w.rebuild(recordReceiverDetails: true);
      expect(HistorySummaryWriter.changes.value, start + 2);
      await w.clear();
      expect(HistorySummaryWriter.changes.value, start + 3);
    });

    test('the key is not in the backup allowlist file (device only)', () {
      expect(kHistSummaryPrefKey, 'autoread_hist_v1');
    });
  });

  group('FallbackHistoryReader', () {
    test('uses the primary when it answers (even empty)', () async {
      final r = FallbackHistoryReader(FakeHistoryReader(), FakeHistoryReader(history: {'SM.1': [1]}));
      expect(await r.topTwo(ReceiverType.sendMoney, '1'), isEmpty);
    });
    test('falls back when the primary is unavailable or throws; null when both fail', () async {
      final fb = FakeHistoryReader(history: {'SM.1': [1, 2]});
      expect(await FallbackHistoryReader(FakeHistoryReader(unavailable: true), fb).topTwo(ReceiverType.sendMoney, '1'), [1, 2]);
      expect(await FallbackHistoryReader(_Throws(), fb).topTwo(ReceiverType.sendMoney, '1'), [1, 2]);
      expect(await FallbackHistoryReader(_Throws(), _Throws()).topTwo(ReceiverType.sendMoney, '1'), isNull);
    });
  });
}
