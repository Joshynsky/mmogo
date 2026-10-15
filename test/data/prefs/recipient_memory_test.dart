// 0.1.2 S8b (NO2): recipient memory. Invented names only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/recipient_memory.dart';
import 'package:mmogo/domain/parsing/name_only_resolver.dart';
import 'package:mmogo/domain/parsing/parsed_sms_fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A prefs object whose writes always throw.
class _ThrowingPrefs implements SharedPreferences {
  @override
  String? getString(String key) => null;
  @override
  Future<bool> setString(String key, String value) => throw StateError('disk full');
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

final _logCall = RegExp(r'\b(print|debugPrint|log)\s*\(');
final _interpolatedThrow = RegExp(r'(throw|Exception|Error)\b[^;\n]*\$');

void main() {
  late int clock;
  late RecipientMemory mem;
  const k = 'ZED STORES';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    clock = 1000;
    mem = RecipientMemory(nowMs: () => clock++);
  });

  Future<String?> raw() async => (await SharedPreferences.getInstance()).getString('recipient_types_v1');

  test('the switch OFF writes nothing: raw string is null and the next lookup misses', () async {
    final r = await mem.remember(k, SmsSourceType.pochi, recordDetailsOn: false);
    expect(r, RememberResult.notRecorded);
    expect(await raw(), isNull);
    expect(await mem.lookup(k), isNull);
    // control: the same call with the switch on does write
    expect(await mem.remember(k, SmsSourceType.pochi, recordDetailsOn: true), RememberResult.saved);
    expect(await raw(), isNotNull);
  });

  test('round trip: remember, lookup, list newest first, override replaces type and bumps at, forget, forgetAll', () async {
    await mem.remember('A', SmsSourceType.pochi, recordDetailsOn: true);
    await mem.remember('B', SmsSourceType.sendMoney, recordDetailsOn: true);
    expect((await mem.lookup('A'))!.type, SmsSourceType.pochi);
    expect((await mem.lookup('B'))!.type, SmsSourceType.sendMoney);
    expect((await mem.list()).map((e) => e.key), ['B', 'A']);

    await mem.remember('A', SmsSourceType.sendMoney, recordDetailsOn: true); // override
    final a = (await mem.lookup('A'))!;
    expect(a.type, SmsSourceType.sendMoney);
    expect(a.at, 1002);
    expect((await mem.list()).map((e) => e.key), ['A', 'B']);

    expect(await mem.forget('A'), isTrue);
    expect(await mem.forget('A'), isFalse);
    expect(await mem.lookup('A'), isNull);
    expect(await mem.forgetAll(), isTrue);
    expect(await mem.list(), isEmpty);
    expect(await raw(), isNull);
  });

  test('same millisecond: the later write is listed first', () async {
    final m = RecipientMemory(nowMs: () => 5);
    await m.remember('X', SmsSourceType.pochi, recordDetailsOn: true);
    await m.remember('Y', SmsSourceType.pochi, recordDetailsOn: true);
    expect((await m.list()).map((e) => e.key), ['Y', 'X']);
  });

  test('non-rememberable types write nothing and say so', () async {
    for (final t in [SmsSourceType.buyGoods, SmsSourceType.payBill, SmsSourceType.agentWithdrawal, SmsSourceType.airtime]) {
      expect(await mem.remember(k, t, recordDetailsOn: true), RememberResult.notRememberable, reason: '$t');
    }
    expect(await raw(), isNull);
  });

  test('bad keys: empty, blank, over 200 chars are never written; 200 is fine', () async {
    expect(await mem.remember('', SmsSourceType.pochi, recordDetailsOn: true), RememberResult.badKey);
    expect(await mem.remember('   ', SmsSourceType.pochi, recordDetailsOn: true), RememberResult.badKey);
    expect(await mem.remember('A' * 201, SmsSourceType.pochi, recordDetailsOn: true), RememberResult.badKey);
    expect(await raw(), isNull);
    expect(await mem.lookup(''), isNull);
    expect(await mem.lookup('A' * 201), isNull);
    expect(await mem.remember('A' * 200, SmsSourceType.pochi, recordDetailsOn: true), RememberResult.saved);
  });

  test('cap: 300 entries, a 301st drops the oldest, says so, count stays 300', () async {
    for (var i = 0; i < 300; i++) {
      expect(await mem.remember('N$i', SmsSourceType.pochi, recordDetailsOn: true), RememberResult.saved);
    }
    expect(await mem.list(), hasLength(300));
    // an override at the cap drops nothing
    expect(await mem.remember('N5', SmsSourceType.sendMoney, recordDetailsOn: true), RememberResult.saved);
    expect(await mem.list(), hasLength(300));
    expect(await mem.remember('NEW', SmsSourceType.pochi, recordDetailsOn: true), RememberResult.savedDroppedOldest);
    final keys = (await mem.list()).map((e) => e.key).toSet();
    expect(keys, hasLength(300));
    expect(keys.contains('N0'), isFalse);
    expect(keys.contains('N1'), isTrue);
    expect(keys.contains('N5'), isTrue);
    expect(keys.contains('NEW'), isTrue);
  });

  group('corrupt storage reads empty or skips, never throws, the next remember recovers', () {
    void seed(String text) {
      SharedPreferences.setMockInitialValues({'recipient_types_v1': text});
      mem = RecipientMemory(nowMs: () => clock++);
    }

    test('non-JSON', () async {
      seed('{not json');
      expect(await mem.lookup(k), isNull);
      expect(await mem.list(), isEmpty);
      expect(await mem.remember(k, SmsSourceType.pochi, recordDetailsOn: true), RememberResult.saved);
      expect((await mem.lookup(k))!.type, SmsSourceType.pochi);
    });

    test('JSON array and scalar', () async {
      for (final t in ['[1,2]', '"x"', '7', 'null']) {
        seed(t);
        expect(await mem.list(), isEmpty, reason: t);
      }
      seed('[1]');
      expect(await mem.remember(k, SmsSourceType.sendMoney, recordDetailsOn: true), RememberResult.saved);
      expect(await mem.list(), hasLength(1));
    });

    test('bad entries are skipped, good ones kept', () async {
      seed(jsonEncode({
        'GOOD': {'t': 'POCHI_LA_BIASHARA', 'at': 5},
        'BADTYPE': {'t': 'BUY_GOODS', 'at': 6},
        'UNKNOWN': {'t': 'WHAT', 'at': 6},
        'BADAT': {'t': 'SEND_MONEY', 'at': '7'},
        'FLOATAT': {'t': 'SEND_MONEY', 'at': 7.5},
        'NOTMAP': 3,
        '': {'t': 'SEND_MONEY', 'at': 8},
      }));
      expect((await mem.list()).map((e) => e.key), ['GOOD']);
      expect(await mem.lookup('BADTYPE'), isNull);
    });
  });

  test('a failed write gives a code with no name in it, and does not throw', () async {
    const secret = 'MARY WANJIKU';
    final bad = RecipientMemory(prefs: () async => _ThrowingPrefs());
    final r = await bad.remember(secret, SmsSourceType.pochi, recordDetailsOn: true);
    expect(r, RememberResult.writeFailed);
    expect(r.toString().toUpperCase().contains('MARY'), isFalse);
    expect(r.toString().toUpperCase().contains('WANJIKU'), isFalse);
    // prefs that cannot even open
    final worse = RecipientMemory(prefs: () => throw StateError('no plugin'));
    expect(await worse.remember(secret, SmsSourceType.pochi, recordDetailsOn: true), RememberResult.writeFailed);
    expect(await worse.lookup(secret), isNull);
    expect(await worse.list(), isEmpty);
    expect(await worse.forgetAll(), isFalse);
  });

  test('two un-awaited remembers both land', () async {
    final f1 = mem.remember('ONE', SmsSourceType.pochi, recordDetailsOn: true);
    final f2 = mem.remember('TWO', SmsSourceType.sendMoney, recordDetailsOn: true);
    final f3 = mem.forget('NOPE');
    await Future.wait([f1, f2, f3]);
    expect((await mem.list()).map((e) => e.key).toSet(), {'ONE', 'TWO'});
  });

  test('raw stored text has only t and at (no classification id)', () async {
    await mem.remember('ONE', SmsSourceType.pochi, recordDetailsOn: true);
    await mem.remember('TWO', SmsSourceType.sendMoney, recordDetailsOn: true);
    final m = jsonDecode((await raw())!) as Map<String, dynamic>;
    expect(m.keys, unorderedEquals(['ONE', 'TWO']));
    for (final v in m.values) {
      expect((v as Map).keys, unorderedEquals(['t', 'at']));
    }
    expect(m['ONE']['t'], 'POCHI_LA_BIASHARA');
    expect(m['TWO']['t'], 'SEND_MONEY');
  });

  test('case and spacing variants of a name give one key and one entry', () async {
    final keys = {
      deriveRecipientNameKey('Mary  Wanjiku'),
      deriveRecipientNameKey(' mary wanjiku '),
      deriveRecipientNameKey('MARY\tWANJIKU'),
    };
    expect(keys, {'MARY WANJIKU'});
    await mem.remember(deriveRecipientNameKey('Mary  Wanjiku'), SmsSourceType.pochi, recordDetailsOn: true);
    await mem.remember(deriveRecipientNameKey(' mary wanjiku '), SmsSourceType.sendMoney, recordDetailsOn: true);
    expect(await mem.list(), hasLength(1));
    expect((await mem.lookup(deriveRecipientNameKey('MARY WANJIKU')))!.type, SmsSourceType.sendMoney);
  });

  group('retype (S9a)', () {
    test('changes the type, keeps at and the place in the list, never moves it to newest', () async {
      await mem.remember('A', SmsSourceType.pochi, recordDetailsOn: true); // at 1000
      await mem.remember('B', SmsSourceType.pochi, recordDetailsOn: true); // 1001
      await mem.remember('C', SmsSourceType.pochi, recordDetailsOn: true); // 1002
      expect(await mem.retype('B', SmsSourceType.sendMoney), isTrue);
      final b = (await mem.lookup('B'))!;
      expect(b.type, SmsSourceType.sendMoney);
      expect(b.at, 1001, reason: 'at is kept');
      expect((await mem.list()).map((e) => e.key), ['C', 'B', 'A'], reason: 'the middle row stays in the middle');
      expect(clock, 1003, reason: 'retype did not read the clock for a new at');
    });

    test('needs no receiver-details switch; refuses an unknown name and a non-rememberable type; writes nothing then', () async {
      await mem.remember('A', SmsSourceType.pochi, recordDetailsOn: true);
      final before = await raw();
      expect(await mem.retype('NOBODY', SmsSourceType.sendMoney), isFalse);
      expect(await mem.retype('A', SmsSourceType.payBill), isFalse);
      expect(await raw(), before);
      expect(await mem.retype('A', SmsSourceType.pochi), isTrue, reason: 'same type: nothing to do, no error');
      expect(await raw(), before);
    });

    test('a failed write gives false, no name anywhere', () async {
      final bad = RecipientMemory(prefs: () async => _ThrowingPrefs());
      expect(await bad.retype('MARY WANJIKU', SmsSourceType.pochi), isFalse);
    });
  });

  group('grep guards', () {
    String codeOf(String path) => File(path)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('no print, debugPrint or log call; no error built from a key or name', () {
      final code = codeOf('lib/data/prefs/recipient_memory.dart');
      expect(_logCall.hasMatch(code), isFalse);
      expect(code.contains('dart:developer'), isFalse);
      expect(_interpolatedThrow.hasMatch(code), isFalse);
      // NEGATIVE CONTROL: the guards can see a bad line
      expect(_logCall.hasMatch("print('x');"), isTrue);
      expect(_interpolatedThrow.hasMatch(r"throw StateError('bad $key');"), isTrue);
    });

    test('backup, restore and CSV code never touch it; backup_setting_keys.dart has no recipient key', () {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path.replaceAll(r'\', '/'))
          .where((p) => p.contains('/data/backup/') || p.toLowerCase().contains('csv') || p.contains('export_dao'))
          .toList();
      expect(files, isNotEmpty);
      for (final p in files) {
        final t = File(p).readAsStringSync();
        expect(t.contains('recipient_memory'), isFalse, reason: p);
        expect(t.contains('recipient_types_v1'), isFalse, reason: p);
      }
      expect(File('lib/data/backup/backup_setting_keys.dart').readAsStringSync().contains('recipient'), isFalse);
    });
  });
}
