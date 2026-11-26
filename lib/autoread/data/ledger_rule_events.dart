/// §AUTOREAD.LEDGER_RULE_EVENTS - keeps the rules and the history summary in step with the ledger.
///
/// The data layer tells `LedgerHooks` that a row was added, edited, deleted or restored (only its
/// number). This class reads that one row and then:
/// - added: tells the rule engine "recorded" for that person (Suggested counters; Ask first only
///   moves its last-recorded time), then rebuilds the summary;
/// - edited: when the category now differs from the one counted, tells the engine "category changed";
/// - deleted (an Undo or a delete): tells the engine "undone", remembers the M-Pesa code for 24 h so
///   the same message is not offered again, rebuilds the summary;
/// - restored, or a bulk change (a restore from a backup): rebuilds the summary.
///
/// Only the person's key, name and a category number are used. No message text exists here. Nothing
/// throws out of a method: a failure leaves the rules as they were. "Record receiver details" OFF:
/// no rule is touched and the summary is removed. Auto-read build only.
library;

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../history/history_summary_writer.dart';
import '../rules/receiver_key.dart';
import '../rules/rule_engine.dart';
import '../rules/rule_model.dart';
import '../rules/rule_store.dart';
import '../rules/undone_codes.dart';

/// The person a ledger row belongs to: the rule type, the rule key and the name to show.
class RowPerson {
  const RowPerson(this.type, this.key, this.name);
  final ReceiverType type;
  final String key;
  final String name;
}

class LedgerRuleEvents {
  LedgerRuleEvents({
    required this.engine,
    required this.store,
    required this.undone,
    required this.summary,
    required this.database,
    required this.detailsOn,
    Future<bool> Function(String name)? pochiRemembered,
    DateTime Function()? now,
  })  : _pochiRemembered = pochiRemembered ?? ((_) async => false),
        _now = now ?? DateTime.now;

  final RuleEngine engine;
  final RuleStore store;
  final UndoneCodes undone;
  final HistorySummaryWriter summary;
  final Future<Database> Function() database;

  /// The "Record receiver details" switch (default on).
  final Future<bool> Function() detailsOn;
  final Future<bool> Function(String name) _pochiRemembered;
  final DateTime Function() _now;

  static const _columns = 'display_code, source_type, counterparty_label, counterparty_phone, '
      'paybill_account_number, classification_id, raw_parse_source, recorded_automatically';

  Future<Map<String, Object?>?> _row(int id) async {
    final rows = await (await database()).rawQuery('SELECT $_columns FROM transactions WHERE id = ?', [id]);
    return rows.isEmpty ? null : rows.first;
  }

  /// The rule person of a row, or null (Cash, Withdrawal, Airtime, no usable key, or details off).
  Future<RowPerson?> personOf(Map<String, Object?> r, {required bool details}) async {
    final label = (r['counterparty_label'] as String?)?.trim();
    final phone = r['counterparty_phone'] as String?;
    final account = r['paybill_account_number'] as String?;
    final ReceiverType type;
    switch (r['source_type']) {
      case 'SEND_MONEY':
        type = ReceiverType.sendMoney;
      case 'PAYBILL':
        type = ReceiverType.payBill;
      case 'BUY_GOODS':
        type = ReceiverType.buyGoods;
      case 'POCHI_LA_BIASHARA':
        type = ReceiverType.pochi;
      default:
        return null;
    }
    final key = receiverKey(
      type,
      phone: phone,
      business: label,
      account: account,
      shopName: label,
      name: label,
      pochiRemembered: type == ReceiverType.pochi && label != null && label.isNotEmpty && await _pochiRemembered(label),
      recordReceiverDetails: details,
    );
    if (key == null) return null;
    return RowPerson(type, key, (label ?? '').isNotEmpty ? label! : key);
  }

  Future<void> inserted(int id) => _guard(() async {
        final details = await detailsOn();
        final r = await _row(id);
        final cat = r?['classification_id'];
        if (r != null && cat is int) {
          final p = await personOf(r, details: details);
          if (p != null) await engine.onRecorded(p.type, p.key, name: p.name, categoryId: cat, at: _now());
        }
        await _rebuild(details);
      });

  Future<void> edited(int id) => _guard(() async {
        final details = await detailsOn();
        final r = await _row(id);
        final cat = r?['classification_id'];
        if (r != null && cat is int) {
          final p = await personOf(r, details: details);
          if (p != null) {
            final rule = await store.get(p.type, p.key);
            // Only a real change of category matters; an edit of the amount or the date does not.
            if (rule != null && rule.runCategoryId != cat) {
              await engine.onCategoryChanged(p.type, p.key, categoryId: cat);
            }
          }
        }
        await _rebuild(details);
      });

  Future<void> removed(int id) => _guard(() async {
        final details = await detailsOn();
        final r = await _row(id);
        if (r != null) {
          final p = await personOf(r, details: details);
          // The no-tap marker is passed on, but the engine keeps the level (D-U): an Auto-record person
          // stays on Auto-record; the undone code below stops the same message being recorded again.
          if (p != null) await engine.onUndone(p.type, p.key, recordedAutomatically: r['recorded_automatically'] == 1);
          final code = r['display_code'];
          if (details && r['raw_parse_source'] == 'SMS_PARSE' && code is String && code.isNotEmpty && r['source_type'] != 'CASH') {
            await undone.add(code, now: _now());
          }
        }
        await _rebuild(details);
      });

  /// A restored row or a bulk change: only the summary needs to follow the ledger.
  Future<void> ledgerChanged([int? _]) => _guard(() async => _rebuild(await detailsOn()));

  Future<void> _rebuild(bool details) async {
    await summary.rebuild(recordReceiverDetails: details);
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }
}
