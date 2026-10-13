// CA4 (S3b): the one phone-number key rule. The vector table V01-V41 and the
// assertions M1-M4 are the Database Engineer's hand-derived table (DBE 0.1.2c
// T3.2), run for real here. Expected values were NOT edited to fit the code.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/db/migration_v3_rekey.dart';
import 'package:mmogo/domain/counterparty/counterparty_key.dart';
import 'package:mmogo/domain/counterparty/phone_key.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';

/// (id, input, expected). Invented numbers only.
final List<(String, String?, String)> _vectors = [
  ('V01', '0712345678', '0712345678'),
  ('V02', '+254712345678', '0712345678'),
  ('V03', '254712345678', '0712345678'),
  ('V04', '00254712345678', '0712345678'),
  ('V05', '0112345678', '0112345678'),
  ('V06', '+254112345678', '0112345678'),
  ('V07', '254112345678', '0112345678'),
  ('V08', '00254112345678', '0112345678'),
  ('V09', '0712 345 678', '0712345678'),
  ('V10', '0712-345-678', '0712345678'),
  ('V11', '+254 712 345 678', '0712345678'),
  ('V12', '+254 7 12 345 678', '0712345678'),
  ('V13', '  0712345678  ', '0712345678'),
  ('V14', '+254-712-345-678', '0712345678'),
  ('V15', '00254 712 345 678', '0712345678'),
  ('V16', '0712345678\n', '0712345678'),
  ('V17', '+254712345678 ', '0712345678'),
  ('V18', '0112 345 678', '0112345678'),
  ('V19', '712345678', '712345678'),
  ('V20', '071234567', '071234567'),
  ('V21', '07123456789', '07123456789'),
  ('V22', '2547123456789', '2547123456789'),
  ('V23', '+25471234567', '+25471234567'),
  ('V24', '123456789012', '123456789012'),
  ('V25', '0212345678', '0212345678'),
  ('V26', '0312345678', '0312345678'),
  ('V27', '0512345678', '0512345678'),
  ('V28', '+254212345678', '+254212345678'),
  ('V29', '254512345678', '254512345678'),
  ('V30', '+254 800 123 456', '+254 800 123 456'),
  ('V31', '0712 abc 678', '0712 abc 678'),
  ('V32', '07123456a8', '07123456a8'),
  ('V33', '+254+712345678', '+254+712345678'),
  ('V34', '07+12345678', '07+12345678'),
  ('V35', '0254712345678', '0254712345678'),
  ('V36', '+2540712345678', '+2540712345678'),
  ('V37', '(0712) 345678', '(0712) 345678'),
  // Arabic-Indic digits spelling 0712345678: left verbatim.
  ('V38', '٠٧١٢٣٤٥٦٧٨',
      '٠٧١٢٣٤٥٦٧٨'),
  ('V39', '', ''),
  ('V40', '   ', ''),
  ('V41', null, ''),
];

/// Every vector whose output differs from [expected], as `id: got`.
List<String> _mismatches(String Function(String?) f) => [
      for (final v in _vectors)
        if (f(v.$2) != v.$3) '${v.$1}: ${f(v.$2)}'
    ];

/// True when [f] satisfies M1-M4 on the live vectors.
bool _crossAssertionsHold(String Function(String?) f) {
  String n(String id) => f(_vectors.firstWhere((v) => v.$1 == id).$2);
  final m1 = ['V01', 'V02', 'V03', 'V04', 'V09', 'V10', 'V11', 'V12', 'V15'].map(n).toSet();
  final m2 = ['V05', 'V06', 'V07', 'V08', 'V18'].map(n).toSet();
  final m3 = n('V01') != n('V05') && n('V02') != n('V06');
  final m4 = ['V19', 'V20', 'V25', 'V30'].every((id) => n(id) != n('V01'));
  return m1.length == 1 && m2.length == 1 && m3 && m4;
}

/// The 0.1.1 rule (trim only), as a control.
String _trimOnly(String? raw) => (raw ?? '').trim();

/// A deliberately wrong rule: folds 01 into 07 (breaks M3).
String _mergesZeroOne(String? raw) {
  final r = normalizePhoneKey(raw);
  return r.startsWith('01') && r.length == 10 ? '07${r.substring(2)}' : r;
}

/// A deliberately wrong frozen copy: no `00254` prefix.
String _noDoubleZero(String? raw) =>
    (raw ?? '').trim().startsWith('00254') ? (raw ?? '').trim() : normalizePhoneKeyV3(raw);

/// Files under lib/ that contain the call text, as `{path: count}`.
Map<String, int> _callSites(Map<String, String> sources) {
  final out = <String, int>{};
  sources.forEach((path, text) {
    final n = RegExp(r'normalizePhoneKey\(').allMatches(text).length;
    if (n > 0) out[path] = n;
  });
  return out;
}

const _allowedFiles = {
  'lib/domain/counterparty/phone_key.dart',
  'lib/domain/counterparty/counterparty_key.dart',
  'lib/data/backup/restore_plan.dart', // arrives with S3c (C-A5)
};

Map<String, String> _libSources() => {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart')) f.path.replaceAll(r'\', '/'): f.readAsStringSync()
    };

void main() {
  group('vector table V01-V41 (run for real)', () {
    test('there are 41 vectors, V01..V41 in order', () {
      expect(_vectors, hasLength(41));
      for (var i = 0; i < 41; i++) {
        expect(_vectors[i].$1, 'V${(i + 1).toString().padLeft(2, '0')}');
      }
    });

    test('every vector gives the DBE hand-derived output (mismatches are listed, never edited)', () {
      expect(_mismatches(normalizePhoneKey), isEmpty);
    });

    test('M1-M4 cross assertions hold', () {
      expect(_crossAssertionsHold(normalizePhoneKey), isTrue);
    });

    test('NEGATIVE CONTROL: the 0.1.1 trim-only rule fails the table', () {
      final bad = _mismatches(_trimOnly);
      expect(bad, isNotEmpty);
      expect(bad.map((m) => m.split(':').first), containsAll(['V02', 'V03', 'V04', 'V09']));
      expect(_crossAssertionsHold(_trimOnly), isFalse);
    });

    test('NEGATIVE CONTROL: a rule that folds 01 into 07 breaks M3', () {
      expect(_crossAssertionsHold(_mergesZeroOne), isFalse);
      expect(_mismatches(_mergesZeroOne), isNotEmpty);
    });

    test('idempotent over the whole table', () {
      for (final v in _vectors) {
        final once = normalizePhoneKey(v.$2);
        expect(normalizePhoneKey(once), once, reason: v.$1);
      }
    });

    test('stored values are not touched by the rule: the output is only a key', () {
      const stored = '+254 712 345 678';
      final key = normalizePhoneKey(stored);
      expect(key, '0712345678');
      expect(stored, '+254 712 345 678');
    });
  });

  group('deriveCounterpartyKey stays the single entry', () {
    String send(String? phone) =>
        deriveCounterpartyKey(sourceType: SmsSourceType.sendMoney, counterpartyPhone: phone);

    test('Send Money uses the phone rule', () {
      expect(send('+254712345678'), send('0712345678'));
      expect(send('0112345678'), isNot(send('0712345678')));
      expect(send(null), '');
      expect(send('  not a phone  '), 'not a phone');
    });

    test('Paybill and Buy Goods keys are NOT phone-normalised', () {
      expect(
          deriveCounterpartyKey(
              sourceType: SmsSourceType.payBill,
              counterpartyLabel: 'acme  ltd',
              paybillAccountNumber: '+254712345678'),
          'ACME LTD#+254712345678');
      expect(
          deriveCounterpartyKey(sourceType: SmsSourceType.buyGoods, counterpartyLabel: ' shop '),
          'SHOP');
    });
  });

  group('differential corpus: frozen migration copy == live rule', () {
    List<String> corpus() {
      final r = Random(20261009); // fixed seed
      const alphabet = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', ' ', '\t', '-', 'a'];
      const prefixes = ['', '0', '+254', '254', '00254', '+2540', '0254', ' ', '+'];
      const firsts = ['1', '7', '1', '7', '2', '0', '8', '9'];
      final out = <String>[];
      for (var i = 0; i < 2500; i++) {
        out.add(List.generate(r.nextInt(17), (_) => alphabet[r.nextInt(alphabet.length)]).join());
      }
      for (var i = 0; i < 2500; i++) {
        final digits = StringBuffer(firsts[r.nextInt(firsts.length)]);
        final extra = r.nextInt(10) < 6 ? 8 : 6 + r.nextInt(5); // mostly the legal 9 digits, else 7..11
        for (var k = 0; k < extra; k++) {
          digits.write(r.nextInt(10));
        }
        var s = prefixes[r.nextInt(prefixes.length)] + digits.toString();
        if (r.nextInt(3) == 0) s = s.replaceFirst(RegExp(r'(?<=\d)(?=\d{3}$)'), ' ');
        if (r.nextInt(4) == 0) s = '  $s\n';
        out.add(s);
      }
      return out;
    }

    test('5,000 strings (fixed seed): frozen == live, and the corpus really exercises the rule', () {
      final c = corpus();
      expect(c, hasLength(5000));
      var rewritten = 0;
      for (final s in c) {
        final live = normalizePhoneKey(s);
        expect(normalizePhoneKeyV3(s), live, reason: 'input ${s.codeUnits}');
        if (live != s.trim()) rewritten++;
      }
      expect(rewritten, greaterThan(300), reason: 'many inputs hit a real rewrite branch');
    });

    test('NEGATIVE CONTROL: a frozen copy that differs on one prefix is caught by the corpus', () {
      final diffs = corpus().where((s) => _noDoubleZero(s) != normalizePhoneKey(s));
      expect(diffs, isNotEmpty);
    });

    test('idempotent over the corpus (live rule)', () {
      for (final s in corpus()) {
        final once = normalizePhoneKey(s);
        expect(normalizePhoneKey(once), once);
      }
    });
  });

  group('static guard: normalizePhoneKey( appears only in its allowed files', () {
    test('live lib/ call sites are inside the three allowed files', () {
      final sites = _callSites(_libSources());
      expect(sites.keys.toSet().difference(_allowedFiles), isEmpty,
          reason: 'only the allowed files may call the rule: $sites');
      expect(sites.keys, containsAll([
        'lib/domain/counterparty/phone_key.dart',
        'lib/domain/counterparty/counterparty_key.dart',
      ]));
    });

    test('NEGATIVE CONTROL: a doctored extra call site is flagged', () {
      final src = _libSources()
        ..['lib/data/db/analytics_dao.dart'] = 'final k = normalizePhoneKey(x);';
      expect(_callSites(src).keys.toSet().difference(_allowedFiles), {'lib/data/db/analytics_dao.dart'});
    });
  });
}
