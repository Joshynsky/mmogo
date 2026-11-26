/// §AUTOREAD.SETUP_RECIPIENTS_SOURCE (0.2.2 item 2 redesign, slice B-SRC): the real [SetupRecipientsSource].
/// The Set up sheet's list, read from the ledger: every Send Money, Pochi, Buy Goods and Paybill recipient,
/// one row per rule key, with the payment count and the stored level. Reads only; never writes.
///
/// Decisions in code (Judge notes):
/// - One row per RULE key (`receiverKey`, the same call and arguments as `LedgerRuleEvents.personOf`), not
///   per Paid to row, so the level lookup and a level set from the sheet hit the rule the ledger events
///   keep. Rows with no rule key are not listed (they could never hold a rule): no phone (Send Money), no
///   business (Paybill), no shop name (Buy Goods), and a Pochi name not remembered as Pochi. A Paybill with
///   a business but no account IS listed (key `BUSINESS#`, as the ledger events key it), although Paid to
///   counts it as "Not recorded".
/// - Airtime and withdrawals are never listed (PM Q3, 25-11): they are not read at all. Cash neither.
/// - Payment count = every non-deleted payment under that key, all time (`AnalyticsDao.itemizedTransactions`
///   with no period, which already drops soft-deleted rows).
/// - Numbers: only masked (`maskPhone`, 0722***555, F2). Send Money shows its masked phone key. Pochi,
///   Paybill and Buy Goods show none (null): the ledger keeps a phone on Send Money rows only (schema CHECK),
///   and a Paybill account is not a phone number. A name that is only a number is masked too (`nameOrMask`).
///   The full number never leaves this class.
/// - Name: the newest non-empty name in the ledger for that key.
/// - Level: from the rule store (`all()`), null = no rule (a new person, or one removed by Forget all).
/// - "Record receiver details" OFF, or the switch cannot be read: an empty list (fails closed).
/// - Order: most payments first, then name (case-insensitive), then type, then key.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../data/db/analytics_dao.dart';
import '../../data/prefs/app_prefs.dart';
import '../../domain/paid_to/paid_to.dart' show paidToPochi;
import '../logic/phone_mask.dart';
import '../rules/receiver_key.dart';
import '../rules/rule_model.dart';
import '../rules/rule_store.dart';
import '../ui/levels/setup_ports.dart';

/// The ledger source types the Set up list reads, by rule type. Airtime and withdrawals are not here.
const Map<String, ReceiverType> kSetupSourceTypes = {
  'SEND_MONEY': ReceiverType.sendMoney,
  'PAYBILL': ReceiverType.payBill,
  'BUY_GOODS': ReceiverType.buyGoods,
  paidToPochi: ReceiverType.pochi,
};

class LedgerSetupRecipientsSource implements SetupRecipientsSource {
  LedgerSetupRecipientsSource({
    required Future<Database> Function() database,
    required RuleStore store,
    Future<bool> Function()? detailsOn,
    Future<bool> Function(String name)? pochiRemembered,
  })  : _database = database,
        _store = store,
        _detailsOn = detailsOn ?? AppPrefs.readCaptureIdentityPreference,
        _pochiRemembered = pochiRemembered ?? ((n) => isRememberedPochi(n));

  final Future<Database> Function() _database;
  final RuleStore _store;
  final Future<bool> Function() _detailsOn;
  final Future<bool> Function(String name) _pochiRemembered;

  Future<bool> _details() async {
    try {
      return await _detailsOn();
    } catch (_) {
      return false; // privacy: an unreadable switch lists nobody
    }
  }

  @override
  Future<List<SetupRecipient>> list({ReceiverType? type}) async {
    if (!await _details()) return const [];
    final sourceTypes = {
      for (final e in kSetupSourceTypes.entries)
        if (type == null || e.value == type) e.key,
    };
    final rows = await AnalyticsDao.itemizedTransactions(await _database(), types: sourceTypes);

    final groups = <String, _Group>{};
    final pochiCache = <String, bool>{};
    for (final r in rows) {
      final t = kSetupSourceTypes[r.sourceType];
      if (t == null) continue;
      final label = r.counterpartyLabel?.trim();
      final phone = r.counterpartyPhone;
      final account = r.paybillAccountNumber;
      var remembered = false;
      if (t == ReceiverType.pochi && label != null && label.isNotEmpty) {
        remembered = pochiCache[label] ??= await _safePochi(label);
      }
      // The same call and arguments as LedgerRuleEvents.personOf, so the key is the rule store's key.
      final key = receiverKey(
        t,
        phone: phone,
        business: label,
        account: account,
        shopName: label,
        name: label,
        pochiRemembered: remembered,
      );
      if (key == null) continue;
      // Rows come newest first: the first row seen with a name gives the name.
      final g = groups.putIfAbsent('${t.code}.$key', () => _Group(t, key));
      g.count += 1;
      if (g.name == null && label != null && label.isNotEmpty) g.name = label;
    }
    if (groups.isEmpty) return const [];

    final levels = <String, RuleLevel>{
      for (final rule in await _store.all()) '${rule.type.code}.${rule.key}': rule.level,
    };
    final out = [
      for (final e in groups.entries)
        SetupRecipient(
          type: e.value.type,
          key: e.value.key,
          displayName: e.value.displayName,
          maskedNumber: e.value.maskedNumber,
          paymentCount: e.value.count,
          level: levels[e.key],
        ),
    ];
    out.sort((a, b) {
      final byCount = b.paymentCount.compareTo(a.paymentCount);
      if (byCount != 0) return byCount;
      final byName = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
      if (byName != 0) return byName;
      final byType = a.type.index.compareTo(b.type.index);
      return byType != 0 ? byType : a.key.compareTo(b.key);
    });
    return List.unmodifiable(out);
  }

  Future<bool> _safePochi(String name) async {
    try {
      return await _pochiRemembered(name);
    } catch (_) {
      return false;
    }
  }
}

class _Group {
  _Group(this.type, this.key);
  final ReceiverType type;
  final String key;
  int count = 0;
  String? name;

  String? get maskedNumber {
    if (type != ReceiverType.sendMoney) return null;
    final m = maskPhone(key);
    return m.isEmpty ? null : m;
  }

  /// Never a raw number: a number-only name is masked; no name shows the masked Send Money key. A key with
  /// no digits at all (text, never a number) is the last fallback.
  String get displayName {
    final n = nameOrMask(name, type == ReceiverType.sendMoney ? key : null);
    return n.isNotEmpty ? n : key;
  }
}
