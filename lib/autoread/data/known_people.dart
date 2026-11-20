/// §AUTOREAD.KNOWN_PEOPLE - who the Remembered page's second tab lists even before a rule exists:
/// people who already have history in the ledger (Send Money, Paybill, Buy Goods), plus the names
/// remembered as Pochi (a Pochi person is listed only when remembered as one).
///
/// Read only. Newest person first, at most 300. Nothing is listed while "Record receiver details" is
/// off. A failure gives an empty list (the tab then shows the people who have a rule). Auto-read
/// build only.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/prefs/recipient_memory.dart' show RecipientMemory;
import '../../domain/parsing/parsed_sms_fields.dart' show SmsSourceType;
import '../history/history_summary_codec.dart' show historyPersonIdOfRow, kHistSummaryCap;
import '../rules/rule_model.dart';
import '../ui/levels/levels_deps.dart' show KnownPerson;

/// Newest ledger rows looked at (the same bound the history summary uses).
const int kKnownScanLimit = 5000;

const String _knownSql = 'SELECT source_type, counterparty_label, counterparty_phone, paybill_account_number '
    'FROM transactions WHERE deleted_at IS NULL AND source_type IN (\'SEND_MONEY\',\'PAYBILL\',\'BUY_GOODS\') '
    'ORDER BY transaction_occurred_at DESC, id DESC LIMIT ?';

const Map<String, ReceiverType> _typeOfSource = {
  'SEND_MONEY': ReceiverType.sendMoney,
  'PAYBILL': ReceiverType.payBill,
  'BUY_GOODS': ReceiverType.buyGoods,
};

class KnownPeopleSource {
  KnownPeopleSource({
    required this.database,
    required this.detailsOn,
    RecipientMemory? memory,
    this.scanLimit = kKnownScanLimit,
  }) : _memory = memory ?? RecipientMemory();

  final Future<Database> Function() database;
  final Future<bool> Function() detailsOn;
  final RecipientMemory _memory;
  final int scanLimit;

  Future<List<KnownPerson>> call() async {
    try {
      if (!await detailsOn()) return const [];
      final out = <KnownPerson>[];
      final seen = <String>{};
      final rows = await (await database()).rawQuery(_knownSql, [scanLimit]);
      for (final r in rows) {
        if (out.length >= kHistSummaryCap) break;
        final source = r['source_type'] as String;
        final id = historyPersonIdOfRow(
          sourceType: source,
          label: r['counterparty_label'] as String?,
          phone: r['counterparty_phone'] as String?,
          account: r['paybill_account_number'] as String?,
        );
        final type = _typeOfSource[source];
        if (id == null || type == null || !seen.add(id)) continue;
        final key = id.substring(type.code.length + 1);
        final label = (r['counterparty_label'] as String?)?.trim() ?? '';
        out.add(KnownPerson(type: type, key: key, name: label.isEmpty ? key : label));
      }
      try {
        for (final e in await _memory.list()) {
          if (e.rule.type != SmsSourceType.pochi) continue; // a remembered Send Money name has no phone key
          if (seen.add('${ReceiverType.pochi.code}.${e.key}')) out.add(KnownPerson(type: ReceiverType.pochi, key: e.key, name: e.key));
        }
      } catch (_) {}
      return out;
    } catch (_) {
      return const [];
    }
  }
}
