// Hand-built backup files for the restore tests (built WITHOUT BackupCodec,
// so a bug in the writer of files cannot hide a bug in the reader).
import 'dart:convert';
import 'dart:typed_data';

import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_validator.dart';

const int f0 = 1790000000000;

Map<String, Object?> cls(int id, String group, String name,
        {int active = 1, String? seedKey, int createdAt = f0}) =>
    {
      'id': id,
      'group': group,
      'name': name,
      'active': active,
      'seed_key': seedKey,
      'created_at': createdAt,
    };

/// The 12 built-ins as a file carries them (file ids 1..12, default names).
List<Map<String, Object?>> seedRows({Map<String, String> renamed = const {}}) {
  const names = {
    'SEND_MONEY:family_friends': 'Family/Friends',
    'SEND_MONEY:rent': 'Rent',
    'SEND_MONEY:transport': 'Transport',
    'SEND_MONEY:groceries': 'Groceries',
    'PAYBILL:rent_payment': 'Rent Payment',
    'PAYBILL:shopping': 'Shopping',
    'PAYBILL:transport': 'Transport',
    'PAYBILL:groceries': 'Groceries',
    'BUY_GOODS:rent_payment': 'Rent Payment',
    'BUY_GOODS:shopping': 'Shopping',
    'BUY_GOODS:transport': 'Transport',
    'BUY_GOODS:groceries': 'Groceries',
  };
  var id = 0;
  return [
    for (final k in kBackupSeedKeys)
      cls(++id, k.split(':').first, renamed[k] ?? names[k]!, seedKey: k),
  ];
}

Map<String, Object?> tx(
  int id,
  String code,
  String source,
  int classification, {
  int amount = 10000,
  String? label,
  String? phone,
  String? account,
  int createdAt = f0,
}) =>
    {
      'id': id,
      'display_code': code,
      'source_type': source,
      'amount_cents': amount,
      'transaction_cost_cents': source == 'CASH' ? null : 500,
      'counterparty_label': label,
      'counterparty_phone': phone,
      'paybill_account_number': account,
      'classification': classification,
      'raw_parse_source': source == 'CASH' ? 'MANUAL' : 'SMS_PARSE',
      'transaction_occurred_at': createdAt,
      'created_at': createdAt,
    };

Map<String, Object?> mapRow(String source, String key, int classification,
        {int autoApply = 1}) =>
    {
      'source_type': source,
      'counterparty_key': key,
      'classification': classification,
      'auto_apply': autoApply,
      'updated_at': f0,
    };

Map<String, Object?> fileJson({
  required List<Map<String, Object?>> classes,
  List<Map<String, Object?>> txs = const [],
  List<Map<String, Object?>> map = const [],
  Map<String, Object?> prefs = const {},
}) =>
    {
      'app': 'mmogo',
      'format_version': 1,
      'schema_version': 2,
      'created_at': f0,
      'counts': {
        'classifications': classes.length,
        'transactions': txs.length,
        'counterparty_map': map.length,
      },
      'classifications': classes,
      'transactions': txs,
      'counterparty_map': map,
      'prefs': prefs,
      'end': 'mmogo-v1',
    };

Uint8List fileBytes(Map<String, Object?> json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// A valid file with all 12 built-ins and [n] SEND_MONEY transactions on the
/// first built-in, codes `X000000000`, `X000000001`, ...
Map<String, Object?> bigFileJson(int n, {String prefix = 'X'}) => fileJson(
      classes: seedRows(),
      txs: [
        for (var i = 0; i < n; i++)
          tx(i + 1, '$prefix${i.toString().padLeft(9, '0')}', 'SEND_MONEY', 1,
              amount: 100 + i, createdAt: f0 + i),
      ],
    );

/// A [ValidatedBackup] built by hand, bypassing the validator (for the
/// trigger and index backstop tests only).
ValidatedBackup unvalidated(Map<String, Object?> json) => ValidatedBackup(
      formatVersion: 1,
      schemaVersion: 2,
      createdAt: f0,
      classifications: (json['classifications']! as List).cast<Map<String, Object?>>(),
      transactions: (json['transactions']! as List).cast<Map<String, Object?>>(),
      counterpartyMap: (json['counterparty_map']! as List).cast<Map<String, Object?>>(),
      prefs: const {},
    );
