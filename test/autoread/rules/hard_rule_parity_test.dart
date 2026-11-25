// 0.2.2 item 2 slice B2b: Dart and Kotlin decide the same. ONE case table (test/autoread/hard_rule_parity_cases.json)
// is run here against decideHardRule / arrivalMayRecord and by tool/kotlin_selfcheck (HardRuleSelfCheck) against
// HardRuleLogic.kt. This file also pins the constants the two sides share (like ask_first_kotlin_pin_test).
@Tags(['autoread'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/hard_rule_arrival.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/autoread/data/queued_yes.dart';
import 'package:mmogo/autoread/rules/hard_rule_decision.dart';
import 'package:mmogo/autoread/rules/prefs_hard_rule_pause.dart';
import 'package:mmogo/autoread/rules/rule_codec.dart';
import 'package:mmogo/autoread/rules/rule_model.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _k = 'android/app/src/autoread/kotlin/app/mmogo/autoread';
String _kt(String n) => File('$_k/$n').readAsStringSync().replaceAll('\r\n', '\n');
String _const(String src, String name) {
  final m = RegExp('const val $name(?:: [A-Za-z]+)? = ("?)([^"\\n]*)\\1\\n').firstMatch(src);
  expect(m, isNotNull, reason: '$name not found');
  return m!.group(2)!;
}

final Map<String, dynamic> _table =
    jsonDecode(File('test/autoread/hard_rule_parity_cases.json').readAsStringSync()) as Map<String, dynamic>;

ReceiverType? _kind(Object? code) => code == null ? null : ReceiverType.values.firstWhere((t) => t.code == code);

void main() {
  group('the shared case table against decideHardRule', () {
    final cases = (_table['decide'] as List).cast<Map<String, dynamic>>();

    test('the table is not empty and every case has a name and an expected answer', () {
      expect(cases.length, greaterThanOrEqualTo(40));
      for (final c in cases) {
        expect(c['name'], isA<String>());
        expect(HardRuleDecision.values.map((d) => d.name), contains(c['expect']), reason: '${c['name']}');
      }
    });

    for (final c in cases) {
      test(c['name'] as String, () {
        final paused = c['pausedUnreadable'] == true ? true : hardPausedFromRaw(c['paused']);
        final details = c['detailsUnreadable'] == true ? false : hardDetailsOnFromRaw(c['details']);
        final d = decideHardRule(
          rule: decodeRule(c['rule']),
          kind: _kind(c['kind']),
          amountCents: c['amountCents'] as int,
          paused: paused,
          detailsOn: details,
        );
        expect(d.name, c['expect']);
      });
    }
  });

  group('the shared case table against arrivalMayRecord (the import re-check)', () {
    for (final c in (_table['mayRecord'] as List).cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final prefs = (c['prefs'] as Map).cast<String, Object?>();
        final item = decodePendingItem(c['item'] as String);
        expect(arrivalMayRecord(item, (k) => prefs[k]), c['expect'], reason: c['name'] as String);
      });
    }

    test('the same answers through fresh preferences (HardRuleRecheck)', () async {
      for (final c in (_table['mayRecord'] as List).cast<Map<String, dynamic>>()) {
        final prefs = (c['prefs'] as Map).cast<String, Object>();
        SharedPreferences.setMockInitialValues(prefs);
        final item = decodePendingItem(c['item'] as String);
        if (item == null) continue;
        expect(await HardRuleRecheck().passes(item), c['expect'], reason: c['name'] as String);
      }
    });
  });

  group('the shared case table: keys and kinds', () {
    test('rule storage keys', () {
      for (final c in (_table['ruleKey'] as List).cast<Map<String, dynamic>>()) {
        expect(ruleStorageKey(_kind(c['type'])!, c['key'] as String), c['storageKey']);
      }
    });

    test('kind of a source type', () {
      for (final c in (_table['kindOfSource'] as List).cast<Map<String, dynamic>>()) {
        expect(ruleKindOfSource(SmsSourceType.values.byName(c['source'] as String))?.code, c['kind']);
      }
    });
  });

  group('the raw readers match the app readers', () {
    test('hardPausedFromRaw answers as PrefsHardRulePause.isPaused for the same stored value', () async {
      for (final v in <Object?>[null, true, false, 'yes', 1]) {
        SharedPreferences.setMockInitialValues({kHardPausedPrefsKey: ?v});
        expect(await PrefsHardRulePause().isPaused(), hardPausedFromRaw(v), reason: '$v');
      }
    });
  });

  group('constants pinned on both sides', () {
    final logic = _kt('HardRuleLogic.kt');

    test('the dormancy flag is false in Dart AND in Kotlin (flipping is step G2: edit both and this test)', () {
      expect(autoRecordLive, isFalse);
      expect(_const(logic, 'AUTO_RECORD_LIVE'), 'false');
    });

    test('the keys and limits Kotlin reads are the ones Dart writes', () {
      expect(_const(logic, 'PAUSED_KEY'), 'flutter.$kHardPausedPrefsKey');
      expect(_const(logic, 'CEILING_MAX_CENTS'), '${kCeilingMaxCents}L');
      expect(_const(logic, 'AUTO_MARK_TAG'), kAutoMarkTag);
      expect(logic, contains('AskStore.DETAILS_KEY'));
      expect(_const(_kt('AskFirstLogic.kt'), 'DETAILS_KEY'), 'flutter.${AppPrefs.keyCaptureIdentityPreference}');
      expect(logic, contains('ArrivalParse.RULE_KEY_PREFIX'));
    });

    test('Kotlin acts on a decision only behind the flag; the importer drops automatic marks while it is false', () {
      final prefs = _kt('HardRuleArrival.kt');
      expect(prefs, contains('if (!HardRuleLogic.AUTO_RECORD_LIVE) return false'));
      expect(File('lib/autoread/data/queued_yes.dart').readAsStringSync(), contains('_live = live ?? autoRecordLive'));
    });

    test('AskFirstLogic still treats a stored level 2 as Ask first for the arrival Parse (isAskFirstRule)', () {
      expect(_kt('AskFirstLogic.kt'), contains('return level == 1 || level == 2'));
    });

    test('nothing in the new Kotlin logs', () {
      for (final f in ['HardRuleLogic.kt', 'HardRuleArrival.kt']) {
        expect(_kt(f), isNot(matches(RegExp(r'\bLog\.|println\(|printStackTrace'))), reason: f);
      }
    });
  });
}
