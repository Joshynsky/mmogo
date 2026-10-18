/// §AUTOREAD.PENDING — device-local store of PARSED waiting items.
///
/// One shared_preferences key per item (prefix [kPendingItemPrefix] plus the
/// 32-hex id), so there is no read-modify-write of a shared blob (SEC-R H1).
/// Only parsed fields are stored, never the message text. Lives under
/// `lib/autoread/` so the standard build drops it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/parsing/parsed_sms_fields.dart';
import '../model/waiting_item.dart';

/// Key prefix of one stored item: the prefix plus the 32-hex id.
const String kPendingItemPrefix = 'autoread_pending_v1.';

/// The generation counter. Off and Delete data bump it so an in-flight parse
/// that started before cannot write afterwards.
const String kPendingGenerationKey = 'autoread_generation_v1';

/// At most this many stored items; `put` returns [StoreResult.full] at the cap.
const int kPendingItemsCap = 200;

enum StoreResult { stored, storedFlagged, duplicate, full, staleGeneration }

abstract class PendingItemsStore {
  /// [item].kind must be [WaitingKind.waitingCategory].
  Future<StoreResult> put(WaitingItem item, {required int generation});

  /// Reloads prefs first; newest transaction first.
  Future<List<WaitingItem>> list();

  /// Removes ONLY that item's key.
  Future<void> remove(String id);

  Future<int> readGeneration();

  /// Off and Delete data call this. Returns the new value.
  Future<int> bumpGeneration();

  /// For dedupe against queued codes.
  Future<bool> containsCode(String displayCode);

  Future<int> count();
}

// ---------------------------------------------------------------- codec

/// JSON for one item: id, heldAt, parsed fields, flags. No message text.
String encodePendingItem(WaitingItem item) {
  final p = item.parsed;
  if (item.kind != WaitingKind.waitingCategory || p == null) {
    throw ArgumentError.value(item.kind, 'kind', 'only waiting-category items are stored');
  }
  return jsonEncode(<String, Object?>{
    'id': item.id,
    'heldAt': item.heldAt.millisecondsSinceEpoch,
    'flagged': item.sameCodeDifferentDetails,
    'code': p.code,
    'type': p.sourceType.name,
    'amountCents': p.amountCents,
    'costCents': p.transactionCostCents,
    'label': p.counterpartyLabel,
    'phone': p.counterpartyPhone,
    'account': p.paybillAccountNumber,
    'agent': p.agentNumber,
    'occurredAt': p.transactionOccurredAt,
  });
}

/// Null when the JSON is corrupt or incomplete (treated as absent).
WaitingItem? decodePendingItem(String json) {
  try {
    final m = jsonDecode(json);
    if (m is! Map<String, dynamic>) return null;
    final id = m['id'];
    if (id is! String || !isValidHeldId(id)) return null;
    final type = SmsSourceType.values.where((t) => t.name == m['type']).firstOrNull;
    final code = m['code'];
    final amount = m['amountCents'];
    final cost = m['costCents'];
    final occurred = m['occurredAt'];
    final heldAt = m['heldAt'];
    if (type == null || code is! String || amount is! int || cost is! int || occurred is! int || heldAt is! int) {
      return null;
    }
    String? optStr(String k) {
      final v = m[k];
      return v is String ? v : null;
    }

    return WaitingItem(
      id: id,
      kind: WaitingKind.waitingCategory,
      heldAt: DateTime.fromMillisecondsSinceEpoch(heldAt),
      sameCodeDifferentDetails: m['flagged'] == true,
      parsed: ParsedSmsFields(
        code: code,
        sourceType: type,
        amountCents: amount,
        transactionCostCents: cost,
        counterpartyLabel: optStr('label'),
        counterpartyPhone: optStr('phone'),
        paybillAccountNumber: optStr('account'),
        agentNumber: optStr('agent'),
        transactionOccurredAt: occurred,
      ),
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- store

class SharedPrefsPendingItemsStore implements PendingItemsStore {
  SharedPrefsPendingItemsStore();

  // Puts in this isolate run one after another so the cap and duplicate
  // checks see each other. Other isolates are covered by per-item keys and
  // the reload before every put.
  Future<void> _tail = Future<void>.value();

  Future<SharedPreferences> _fresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs;
  }

  List<WaitingItem> _readAll(SharedPreferences prefs) {
    final out = <WaitingItem>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(kPendingItemPrefix)) continue;
      final s = prefs.get(key);
      if (s is! String) continue;
      final item = decodePendingItem(s);
      // The key must match the id inside; anything else is treated as absent.
      if (item == null || '$kPendingItemPrefix${item.id}' != key) continue;
      out.add(item);
    }
    out.sort((a, b) {
      final c = b.parsed!.transactionOccurredAt.compareTo(a.parsed!.transactionOccurredAt);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
    return out;
  }

  @override
  Future<StoreResult> put(WaitingItem item, {required int generation}) {
    if (!isValidHeldId(item.id)) {
      throw ArgumentError.value(item.id, 'id', 'must be 32 lowercase hex characters');
    }
    if (item.kind != WaitingKind.waitingCategory || item.parsed == null) {
      throw ArgumentError.value(item.kind, 'kind', 'only waiting-category items are stored');
    }
    final run = _tail.then((_) => _putNow(item, generation));
    _tail = run.then<void>((_) {}, onError: (_) {});
    return run;
  }

  Future<StoreResult> _putNow(WaitingItem item, int generation) async {
    final prefs = await _fresh();
    final current = prefs.getInt(kPendingGenerationKey) ?? 0;
    if (generation != current) return StoreResult.staleGeneration;

    final key = '$kPendingItemPrefix${item.id}';
    if (prefs.containsKey(key)) return StoreResult.duplicate;

    final all = _readAll(prefs);
    final parsed = item.parsed!;
    var flagged = false;
    for (final other in all) {
      if (other.parsed!.code != parsed.code) continue;
      if (other.parsed == parsed) return StoreResult.duplicate;
      flagged = true;
    }
    final storedCount = prefs.getKeys().where((k) => k.startsWith(kPendingItemPrefix)).length;
    if (storedCount >= kPendingItemsCap) return StoreResult.full;

    final toStore = flagged
        ? WaitingItem(
            id: item.id,
            kind: item.kind,
            heldAt: item.heldAt,
            parsed: parsed,
            sameCodeDifferentDetails: true,
          )
        : item;
    final ok = await prefs.setString(key, encodePendingItem(toStore));
    if (!ok) throw StateError('could not write the item');
    return flagged ? StoreResult.storedFlagged : StoreResult.stored;
  }

  @override
  Future<List<WaitingItem>> list() async => _readAll(await _fresh());

  @override
  Future<void> remove(String id) async {
    if (!isValidHeldId(id)) {
      throw ArgumentError.value(id, 'id', 'must be 32 lowercase hex characters');
    }
    final prefs = await _fresh();
    await prefs.remove('$kPendingItemPrefix$id');
  }

  @override
  Future<int> readGeneration() async => (await _fresh()).getInt(kPendingGenerationKey) ?? 0;

  @override
  Future<int> bumpGeneration() async {
    final prefs = await _fresh();
    final next = (prefs.getInt(kPendingGenerationKey) ?? 0) + 1;
    await prefs.setInt(kPendingGenerationKey, next);
    return next;
  }

  @override
  Future<bool> containsCode(String displayCode) async =>
      _readAll(await _fresh()).any((i) => i.parsed!.code == displayCode);

  @override
  Future<int> count() async =>
      (await _fresh()).getKeys().where((k) => k.startsWith(kPendingItemPrefix)).length;
}
