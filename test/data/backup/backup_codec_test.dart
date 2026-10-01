// B9: BackupCodec (the file writer). Pure; no database.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_codec.dart';
import 'package:mmogo/data/backup/backup_limits.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/db/migrations.dart';
import 'package:mmogo/data/db/schema.dart';

import '../../support/backup_test_data.dart';

Uint8List _encodeFixture({Map<String, Object?> prefs = const {}}) {
  final j = validBackupJson();
  return BackupCodec.encode(
    createdAtMs: j['created_at']! as int,
    classifications: rowsOf(j, 'classifications'),
    transactions: rowsOf(j, 'transactions'),
    counterpartyMap: rowsOf(j, 'counterparty_map'),
    prefs: prefs,
  );
}

void main() {
  test('envelope has exactly the documented keys, in order', () {
    final obj = jsonDecode(utf8.decode(_encodeFixture())) as Map<String, Object?>;
    expect(obj.keys.toList(), kBackupTopLevelKeys);
    expect(obj['app'], 'mmogo');
    expect(obj['format_version'], 1);
    expect(obj['schema_version'], 2);
    expect(obj['created_at'], tBase);
    expect(obj['end'], 'mmogo-v1');
    expect(obj['counts'], {
      'classifications': 5,
      'transactions': 5,
      'counterparty_map': 2,
    });
  });

  test('constants agree with the app: schema version and seed keys', () {
    expect(kBackupSchemaVersion, kDbVersion);
    expect(
      kBackupSeedKeys,
      AppSchema.seedClassifications.map((s) => s.seedKey).toList(),
    );
    expect(kBackupGroupCodes.toSet(), {
      'SEND_MONEY', 'PAYBILL', 'BUY_GOODS', 'POCHI_LA_BIASHARA',
    });
  });

  test('output is compact: app marker in the first 256 bytes, tail marker last', () {
    final bytes = _encodeFixture();
    final head = utf8.decode(bytes.sublist(0, 256), allowMalformed: true);
    expect(head.contains('"app":"mmogo"'), isTrue);
    expect(utf8.decode(bytes).endsWith('"end":"mmogo-v1"}'), isTrue);
    expect(utf8.decode(bytes).contains('\n'), isFalse);
  });

  test('every row carries exactly its key set, in the documented order', () {
    final obj = jsonDecode(utf8.decode(_encodeFixture())) as Map<String, Object?>;
    for (final r in (obj['classifications']! as List).cast<Map>()) {
      expect(r.keys.toList(), kBackupClassificationKeys);
    }
    for (final r in (obj['transactions']! as List).cast<Map>()) {
      expect(r.keys.toList(), kBackupTransactionKeys);
    }
    for (final r in (obj['counterparty_map']! as List).cast<Map>()) {
      expect(r.keys.toList(), kBackupMapKeys);
    }
  });

  test('extra columns in a source row never reach the file', () {
    final j = validBackupJson();
    final tx = rowsOf(j, 'transactions');
    tx.first['deleted_at'] = 123;
    tx.first['secret'] = 'x';
    final bytes = BackupCodec.encode(
      createdAtMs: tBase,
      classifications: rowsOf(j, 'classifications'),
      transactions: tx,
      counterpartyMap: rowsOf(j, 'counterparty_map'),
    );
    final text = utf8.decode(bytes);
    expect(text.contains('deleted_at'), isFalse);
    expect(text.contains('secret'), isFalse);
  });

  test('the output validates and decodes back to the same rows', () {
    final j = validBackupJson();
    final v = BackupValidator.validate(_encodeFixture(prefs: {'palette_id': 'leaf'}));
    expect(v.classifications, rowsOf(j, 'classifications'));
    expect(v.transactions, rowsOf(j, 'transactions'));
    expect(v.counterpartyMap, rowsOf(j, 'counterparty_map'));
    expect(v.prefs, {'palette_id': 'leaf'});
    expect(v.createdAt, tBase);
  });

  test('hostile text is JSON-escaped, stays text, and survives a round trip', () {
    const hostile = <String>[
      "'); DROP TABLE transactions;--",
      '" OR 1=1',
      'file:///etc/passwd',
      'https://evil.example/x?a=b&c=d',
      r'C:\Windows\System32',
      'quote " backslash \\ slash / emoji \u{1F600}',
      '{"app":"mmogo","end":"mmogo-v1"}',
    ];
    for (final h in hostile) {
      final j = validBackupJson();
      rowsOf(j, 'classifications')[3]['name'] = h;
      final bytes = BackupCodec.encode(
        createdAtMs: tBase,
        classifications: rowsOf(j, 'classifications'),
        transactions: rowsOf(j, 'transactions'),
        counterpartyMap: rowsOf(j, 'counterparty_map'),
      );
      // Still one well-formed JSON object ending in the tail marker.
      expect(utf8.decode(bytes).endsWith('"end":"mmogo-v1"}'), isTrue);
      final v = BackupValidator.validate(bytes);
      expect(v.classifications[3]['name'], h);
    }
  });

  test('empty database shape encodes and validates', () {
    final bytes = BackupCodec.encode(
      createdAtMs: tBase,
      classifications: const [],
      transactions: const [],
      counterpartyMap: const [],
    );
    final v = BackupValidator.validate(bytes);
    expect(v.transactions, isEmpty);
    expect(v.prefs, isEmpty);
  });
}
