/// AUTOREAD HISTORY summary: the pure part (no I/O). The preferences summary `autoread_hist_v1` holds,
/// per person, the up-to-2 most used category ids of their last 5 records. Written only by the app.
/// Labels and numbers only, never message text.
library;

import 'dart:convert';

import '../../domain/counterparty/counterparty_key.dart';
import '../../domain/parsing/name_only_resolver.dart' show deriveRecipientNameKey;
import '../../domain/parsing/parsed_sms_fields.dart';
import '../rules/rule_model.dart';

/// The one preferences key of the summary. Pinned by the backup guard test (S2a).
const String kHistSummaryPrefKey = 'autoread_hist_v1';

/// At most this many people are kept (newest first when over).
const int kHistSummaryCap = 300;

/// A person's last N records are looked at.
const int kHistLastRecords = 5;

/// Keys longer than this are never stored or looked up (same limit as the rule keys).
const int kHistMaxKeyLength = 200;

/// The summary index of a person: `SM.0712345678`.
String historyPersonId(ReceiverType type, String key) => '${type.code}.$key';

/// The 2 most used ids among the first 5 of [newestFirst]; ties go to the one used most recently.
/// Empty input gives an empty list.
List<int> topTwoCategories(List<int> newestFirst) {
  final last = newestFirst.length > kHistLastRecords ? newestFirst.sublist(0, kHistLastRecords) : newestFirst;
  final count = <int, int>{};
  final firstSeen = <int, int>{};
  for (var i = 0; i < last.length; i++) {
    count[last[i]] = (count[last[i]] ?? 0) + 1;
    firstSeen.putIfAbsent(last[i], () => i);
  }
  final ids = count.keys.toList()
    ..sort((a, b) {
      final c = count[b]!.compareTo(count[a]!);
      return c != 0 ? c : firstSeen[a]!.compareTo(firstSeen[b]!);
    });
  return ids.length > 2 ? ids.sublist(0, 2) : ids;
}

/// The summary index (`TYPE.key`) of one ledger row, or null when the row has no person (empty key, over
/// 200 chars, or a type that never has a rule). [sourceType] is the stored `transactions.source_type`.
String? historyPersonIdOfRow({
  required String sourceType,
  String? label,
  String? phone,
  String? account,
}) {
  final ReceiverType type;
  final String key;
  switch (sourceType) {
    case 'SEND_MONEY':
      type = ReceiverType.sendMoney;
      key = deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);
    case 'PAYBILL':
      type = ReceiverType.payBill;
      key = deriveCounterpartyKey(
        sourceType: SmsSourceType.payBill,
        counterpartyLabel: label,
        paybillAccountNumber: account,
      );
      if (key.replaceAll('#', '').isEmpty) return null;
    case 'BUY_GOODS':
      type = ReceiverType.buyGoods;
      key = deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: label);
    case 'POCHI_LA_BIASHARA':
      type = ReceiverType.pochi;
      key = deriveRecipientNameKey(label ?? '');
    default:
      return null;
  }
  if (key.isEmpty || key.length > kHistMaxKeyLength) return null;
  return historyPersonId(type, key);
}

/// `{"v":1,"p":{"SM.0712345678":[3,4]}}`. [people] should be newest person first; only the first
/// [kHistSummaryCap] are written. Lists are cut to 2.
String encodeHistSummary(Map<String, List<int>> people) {
  final p = <String, List<int>>{};
  for (final e in people.entries) {
    if (p.length >= kHistSummaryCap) break;
    p[e.key] = e.value.length > 2 ? e.value.sublist(0, 2) : List.of(e.value);
  }
  return jsonEncode(<String, Object?>{'v': 1, 'p': p});
}

/// Null when [json] is missing or corrupt (the summary is then unavailable). Bad entries are skipped.
Map<String, List<int>>? decodeHistSummary(String? json) {
  if (json == null) return null;
  try {
    final m = jsonDecode(json);
    if (m is! Map || m['v'] != 1) return null;
    final p = m['p'];
    if (p is! Map) return null;
    final out = <String, List<int>>{};
    for (final e in p.entries) {
      if (out.length >= kHistSummaryCap) break;
      final k = e.key;
      final v = e.value;
      if (k is! String || v is! List) continue;
      final ids = <int>[];
      for (final x in v) {
        if (x is int) ids.add(x);
      }
      out[k] = ids.length > 2 ? ids.sublist(0, 2) : ids;
    }
    return out;
  } catch (_) {
    return null;
  }
}
