// 0.1.2 A3c: Delete data (Level 1) and the auto-read waiting items. The service
// removes every `autoread_pending_v1.` key by that one prefix, bumps the
// generation counter FIRST, never removes the counter, and says "not finished"
// when a key will not go. Same real-SQLite temp env as delete_level1_test.dart.
//
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/data/pending_items_store.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/data_op_env.dart';

const _idA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _idB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  late DataOpEnv env;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$kPendingItemKeyPrefix$_idA', '{"id":"$_idA"}');
    await prefs.setString('$kPendingItemKeyPrefix$_idB', '{"id":"$_idB"}');
    await prefs.setInt(kPendingGenerationPrefsKey, 4);
  });

  tearDown(() => env.dispose());

  test('the device-keys strings equal the store strings (the standard build cannot import the store)', () {
    expect(kPendingItemKeyPrefix, kPendingItemPrefix);
    expect(kPendingGenerationPrefsKey, kPendingGenerationKey);
    expect(queueKeyPrefixes, [kPendingItemKeyPrefix]);
  });

  test('peek sees waiting items as a queue', () async {
    expect((await env.service().peek()).queuePresent, isTrue);
  });

  test('delete removes every waiting item key, bumps the generation, keeps the counter', () async {
    final r = await env.service().deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.done);
    final m = await env.prefsMap();
    expect(m.keys.where((k) => k.startsWith(kPendingItemKeyPrefix)), isEmpty);
    expect(m[kPendingGenerationPrefsKey], 5);
  });

  test('the generation is bumped before any item key is removed', () async {
    await env.service().deleteMyTransactions();
    final log = env.prefs.log;
    final bump = log.indexOf('setInt:$kPendingGenerationPrefsKey');
    final firstRemove = log.indexWhere((e) => e.startsWith('remove:$kPendingItemKeyPrefix'));
    expect(bump, isNonNegative);
    expect(firstRemove, greaterThan(bump));
  });

  test('a missing counter starts from 0 and ends at 1', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPendingGenerationPrefsKey);
    await env.service().deleteMyTransactions();
    expect((await env.prefsMap())[kPendingGenerationPrefsKey], 1);
  });

  test('an item key that will not go: notFinished at queue; retry clean', () async {
    env.prefs.removeFails.add('$kPendingItemKeyPrefix$_idA');
    final r = await env.service().deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.notFinished);
    expect(r.failedStep, DeleteDataStep.queue);
    env.prefs.removeFails.clear();
    expect((await env.service().deleteMyTransactions()).outcome, DeleteDataOutcome.done);
    expect((await env.prefsMap()).keys.where((k) => k.startsWith(kPendingItemKeyPrefix)), isEmpty);
  });

  test('a remove that lies is caught by the read-back', () async {
    env.prefs.removeLies.add('$kPendingItemKeyPrefix$_idB');
    final r = await env.service().deleteMyTransactions();
    expect(r.failedStep, DeleteDataStep.queue);
  });

  test('a counter write that fails: notFinished at queue and no item key was touched', () async {
    env.prefs.failSetInt = true;
    final r = await env.service().deleteMyTransactions();
    expect(r.failedStep, DeleteDataStep.queue);
    final m = await env.prefsMap();
    expect(m.containsKey('$kPendingItemKeyPrefix$_idA'), isTrue);
    expect(m.containsKey('$kPendingItemKeyPrefix$_idB'), isTrue);
  });

  test('only the one prefix is removed: a look-alike key stays', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('autoread_pending_v2.$_idA', 'x');
    await env.service().deleteMyTransactions();
    expect((await env.prefsMap()).containsKey('autoread_pending_v2.$_idA'), isTrue);
  });
}
