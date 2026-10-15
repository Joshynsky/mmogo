// SMS scenario runner (0.1.2 S8a follow-up). Reads blocks from
// test/fixtures/sms_scenarios.txt (committed, invented) and, when
// MMOGO_SMS_SCENARIOS (env var or --dart-define) names another file in the
// same format, from that file too. Format and how-to: header of the .txt file.
//
// Privacy: for the OPT-IN file nothing prints or fails with message text,
// names, phones, amounts or expected values; only index, domain, note and the
// verdict type / key names.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/domain/parsing/parse_result.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:mmogo/domain/parsing/sms_parser.dart';

const String _envName = 'MMOGO_SMS_SCENARIOS';
const String _committedPath = 'test/fixtures/sms_scenarios.txt';

class Scenario {
  Scenario(this.index, this.domain, this.note, this.expect, this.message);
  final int index;
  final String domain;
  final String note;

  /// Null = report mode.
  final Map<String, String>? expect;
  final String message;
  String get header => '#$index $domain | $note';
}

final RegExp _pair = RegExp(r'(\w+)=("[^"]*"|\S+)');

String _expand(String raw) {
  var s = raw.replaceAllMapped(RegExp(r'<<REPEAT:(.*?):(\d+)>>'),
      (m) => m.group(1)! * int.parse(m.group(2)!));
  final pad = RegExp(r'<<PAD:(\d+)>>').firstMatch(s);
  if (pad != null) {
    final without = s.replaceFirst(pad.group(0)!, '');
    final n = int.parse(pad.group(1)!) - without.length;
    s = s.replaceFirst(pad.group(0)!, 'x' * (n < 0 ? 0 : n));
  }
  return s;
}

List<Scenario> parseScenarioFile(String content) {
  final out = <Scenario>[];
  String? header;
  final body = <String>[];
  void flush() {
    final h = header;
    if (h == null) return;
    final parts = h.substring(2).split(' | ');
    final domain = parts[0].trim();
    String note = '';
    String? expectPart;
    for (var i = 1; i < parts.length; i++) {
      final p = parts[i].trim();
      if (p.startsWith('expect:')) {
        expectPart = p.substring(7).trim();
      } else {
        note = note.isEmpty ? p : '$note | $p';
      }
    }
    Map<String, String>? expect;
    if (expectPart != null) {
      final tokens = expectPart.split(RegExp(r'\s+'));
      expect = {'result': tokens.isEmpty ? '' : tokens.first};
      for (final m in _pair.allMatches(expectPart)) {
        var v = m.group(2)!;
        if (v.startsWith('"')) v = v.substring(1, v.length - 1);
        expect[m.group(1)!] = v;
      }
    }
    out.add(Scenario(out.length + 1, domain, note, expect, _expand(body.join('\n'))));
    header = null;
    body.clear();
  }

  for (final line in content.split('\n').map((l) => l.endsWith('\r') ? l.substring(0, l.length - 1) : l)) {
    if (line.startsWith('# NOTE')) continue;
    if (line.isEmpty) {
      flush();
    } else if (header == null) {
      if (line.startsWith('# ')) header = line;
    } else {
      body.add(line);
    }
  }
  flush();
  return out;
}

/// The verdict type name used by the expect line.
String verdictOf(ParseResult r) => switch (r) {
      ParseSuccess(:final fields) => switch (fields.sourceType) {
          SmsSourceType.sendMoney => 'sendMoney',
          SmsSourceType.payBill => 'payBill',
          SmsSourceType.buyGoods => 'buyGoods',
          SmsSourceType.pochi => 'pochi',
          SmsSourceType.agentWithdrawal => 'agentWithdrawal',
          SmsSourceType.airtime => 'airtime',
        },
      ParseNeedsType() => 'needsType',
      ParseTooLong() => 'tooLong',
      ParseError() => 'notParsed',
    };

String _cents(int c) => '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';

/// Returns a list of problems (empty = pass). [showValues] false hides every
/// value (opt-in files): only the key names are reported.
List<String> check(Scenario s, {required bool showValues}) {
  final expect = s.expect!;
  final r = SmsParser.parse(s.message);
  final problems = <String>[];
  final got = verdictOf(r);
  final want = expect['result']!;
  if (got.toLowerCase() != want.toLowerCase()) {
    problems.add(showValues ? 'result: expected $want, got $got' : 'result differs');
    return problems;
  }
  final actual = <String, String?>{};
  if (r is ParseSuccess) {
    final f = r.fields;
    actual['amount'] = _cents(f.amountCents);
    actual['fee'] = _cents(f.transactionCostCents);
    actual['label'] = f.counterpartyLabel;
    actual['labellen'] = f.counterpartyLabel?.length.toString();
    actual['phone'] = f.counterpartyPhone;
    actual['account'] = f.paybillAccountNumber;
    actual['agent'] = f.agentNumber;
  } else if (r is ParseNeedsType) {
    final f = r.fields;
    actual['amount'] = _cents(f.amountCents);
    actual['fee'] = _cents(f.transactionCostCents);
    actual['label'] = f.name;
    actual['labellen'] = f.name.length.toString();
  }
  for (final e in expect.entries) {
    if (e.key == 'result') continue;
    final a = actual[e.key];
    final w = e.value == 'none' ? null : e.value;
    if (a != w) {
      problems.add(showValues ? '${e.key}: expected ${e.value}, got ${a ?? 'none'}' : '${e.key} differs');
    }
  }
  return problems;
}

void main() {
  final committed = parseScenarioFile(File(_committedPath).readAsStringSync());

  group('committed scenarios ($_committedPath)', () {
    test('file has scenarios and every one has an expect line', () {
      expect(committed.length, greaterThanOrEqualTo(40));
      for (final s in committed) {
        expect(s.expect, isNotNull, reason: 'no expect line: ${s.header}');
      }
    });
    for (final s in committed) {
      test(s.header, () {
        final problems = check(s, showValues: true);
        expect(problems, isEmpty, reason: 'scenario ${s.header}: ${problems.join('; ')}');
      });
    }
  });

  final envPath = Platform.environment[_envName] ?? const String.fromEnvironment(_envName);
  group('opt-in scenario file ($_envName)', () {
    if (envPath.isEmpty) {
      test('opt-in file', skip: 'SKIPPED: $_envName is not set. Set it to a scenario file to run your own.', () {});
      return;
    }
    final file = File(envPath);
    if (!file.existsSync()) {
      test('opt-in file exists', () {
        fail('$_envName points to a file that does not exist');
      });
      return;
    }
    final scenarios = parseScenarioFile(file.readAsStringSync());
    final report = scenarios.where((s) => s.expect == null).toList();
    for (final s in scenarios.where((s) => s.expect != null)) {
      test('opt-in #${s.index} ${s.domain}', () {
        final problems = check(s, showValues: false);
        expect(problems, isEmpty, reason: 'opt-in scenario #${s.index} (${s.domain}): ${problems.join('; ')}');
      });
    }
    test('report mode (${report.length} blocks, nothing asserted)', () {
      final counts = <String, int>{};
      for (final s in report) {
        final v = verdictOf(SmsParser.parse(s.message));
        counts[v] = (counts[v] ?? 0) + 1;
        // ignore: avoid_print
        print('REPORT #${s.index} | ${s.domain}${s.note.isEmpty ? '' : ' | ${s.note}'} | $v');
      }
      // ignore: avoid_print
      print('REPORT SUMMARY: ${report.length} blocks, '
          '${scenarios.length - report.length} asserted elsewhere; '
          '${counts.entries.map((e) => '${e.key}=${e.value}').join(' ')}');
    });
  });
}
