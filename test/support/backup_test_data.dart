// Hand-built backup-file fixtures shared by the codec, service and validator
// tests. Built WITHOUT BackupCodec so the validator tests do not depend on the
// code that writes files.
import 'dart:convert';
import 'dart:typed_data';

const int tBase = 1790000000000; // 2026-09-21, inside the valid epoch range.

/// A small, realistic, valid backup as a decoded JSON object.
Map<String, Object?> validBackupJson() => jsonDecode(jsonEncode(<String, Object?>{
      'app': 'mmogo',
      'format_version': 1,
      'schema_version': 2,
      'created_at': tBase,
      'counts': {'classifications': 5, 'transactions': 5, 'counterparty_map': 2},
      'classifications': [
        {'id': 1, 'group': 'SEND_MONEY', 'name': 'Family/Friends', 'active': 1, 'seed_key': 'SEND_MONEY:family_friends', 'created_at': tBase},
        {'id': 2, 'group': 'PAYBILL', 'name': 'Landlord', 'active': 1, 'seed_key': 'PAYBILL:rent_payment', 'created_at': tBase},
        {'id': 3, 'group': 'BUY_GOODS', 'name': 'Shopping', 'active': 1, 'seed_key': 'BUY_GOODS:shopping', 'created_at': tBase},
        {'id': 4, 'group': 'SEND_MONEY', 'name': 'School fees', 'active': 1, 'seed_key': null, 'created_at': tBase + 1000},
        {'id': 5, 'group': 'SEND_MONEY', 'name': 'Old one', 'active': 0, 'seed_key': null, 'created_at': tBase + 2000},
      ],
      'transactions': [
        {'id': 1, 'display_code': 'AB12CD34EF', 'source_type': 'SEND_MONEY', 'amount_cents': 150000, 'transaction_cost_cents': 2300, 'counterparty_label': 'JOHN DOE', 'counterparty_phone': '0712345678', 'paybill_account_number': null, 'classification': 1, 'raw_parse_source': 'SMS_PARSE', 'transaction_occurred_at': tBase, 'created_at': tBase},
        {'id': 2, 'display_code': 'QWE123RTY4', 'source_type': 'PAYBILL', 'amount_cents': 500000, 'transaction_cost_cents': 0, 'counterparty_label': 'KPLC', 'counterparty_phone': null, 'paybill_account_number': '12345', 'classification': 2, 'raw_parse_source': 'MANUAL', 'transaction_occurred_at': tBase + 5000, 'created_at': tBase + 5000},
        {'id': 3, 'display_code': 'ZXC123VBN5', 'source_type': 'BUY_GOODS', 'amount_cents': 9900, 'transaction_cost_cents': 0, 'counterparty_label': null, 'counterparty_phone': null, 'paybill_account_number': null, 'classification': 3, 'raw_parse_source': 'SMS_PARSE', 'transaction_occurred_at': tBase + 6000, 'created_at': tBase + 6000},
        {'id': 4, 'display_code': 'CASH-20260921-1030', 'source_type': 'CASH', 'amount_cents': 20000, 'transaction_cost_cents': null, 'counterparty_label': null, 'counterparty_phone': null, 'paybill_account_number': null, 'classification': 1, 'raw_parse_source': 'MANUAL', 'transaction_occurred_at': tBase + 7000, 'created_at': tBase + 7000},
        {'id': 5, 'display_code': 'CASH-20260921-1030', 'source_type': 'CASH', 'amount_cents': 30000, 'transaction_cost_cents': null, 'counterparty_label': null, 'counterparty_phone': null, 'paybill_account_number': null, 'classification': 4, 'raw_parse_source': 'MANUAL', 'transaction_occurred_at': tBase + 7000, 'created_at': tBase + 7500},
      ],
      'counterparty_map': [
        {'source_type': 'SEND_MONEY', 'counterparty_key': '0712345678', 'classification': 1, 'auto_apply': 1, 'updated_at': tBase},
        {'source_type': 'PAYBILL', 'counterparty_key': 'KPLC#12345', 'classification': 2, 'auto_apply': 0, 'updated_at': tBase},
      ],
      'prefs': {'palette_id': 'leaf', 'user_display_name': 'Amina'},
      'end': 'mmogo-v1',
    })) as Map<String, Object?>;

Uint8List bytesOf(Object? json) =>
    Uint8List.fromList(utf8.encode(jsonEncode(json)));

/// Shorthands for editing the fixture in place.
List<Map<String, Object?>> rowsOf(Map<String, Object?> m, String table) =>
    (m[table]! as List).cast<Map<String, Object?>>();

/// Keeps `counts` equal to the array lengths after an edit.
void fixCounts(Map<String, Object?> m) {
  m['counts'] = {
    'classifications': (m['classifications']! as List).length,
    'transactions': (m['transactions']! as List).length,
    'counterparty_map': (m['counterparty_map']! as List).length,
  };
}
