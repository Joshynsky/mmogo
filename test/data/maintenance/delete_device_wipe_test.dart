// I2 (19-10-2026): the device-wipe hook of Delete data (Judge condition 7: a
// superset of Off). A generic hook is used here (no auto-read import): it runs
// as part of the queue step of Level 1, before Level 2 clears the preferences
// (and so again in the start-up resume), a false or a throw is "did not finish"
// at the queue step, a retry completes, and with no hook everything is as before.
//
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/data/maintenance/device_keys.dart';
import 'package:mmogo/data/maintenance/reset_resume.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/data_op_env.dart';

void main() {
  late DataOpEnv env;
  late List<String> log;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
    log = [];
  });
  tearDown(() async {
    ResetEnv.defaultDeviceWipe = null;
    await env.dispose();
  });

  ResetEnv withHook(Future<bool> Function() hook) => ResetEnv(
        db: env.db,
        dbFactory: env.resetEnv().dbFactory,
        safety: env.safety,
        prefs: env.prefs,
        bridge: () => env.bridge,
        fs: env.fs,
        nowMs: () => env.clockMs,
        deviceWipe: hook,
        grantTimeout: const Duration(milliseconds: 300),
        flagReadTimeout: const Duration(milliseconds: 500),
      );

  DeleteDataServiceImpl serviceWith(ResetEnv e) => DeleteDataServiceImpl(
        env: e,
        memory: env.memory(),
        gate: env.gate,
        vacuumTimeout: const Duration(seconds: 5),
        quiesceBound: const Duration(milliseconds: 400),
      );

  group('Level 1', () {
    test('the hook runs once, after the queue keys are removed, and the result is done', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${kPendingItemKeyPrefix}aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '{}');
      final r = await serviceWith(withHook(() async {
        log.add('hook:keysLeft=${(await env.prefsMap()).keys.where((k) => k.startsWith(kPendingItemKeyPrefix)).length}');
        return true;
      })).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
      expect(log, ['hook:keysLeft=0']);
    });

    test('a hook that says false: "did not finish" at the queue step; a retry runs it again and completes', () async {
      var ok = false;
      final svc = serviceWith(withHook(() async {
        log.add('hook');
        return ok;
      }));
      final first = await svc.deleteMyTransactions();
      expect(first.outcome, DeleteDataOutcome.notFinished);
      expect(first.failedStep, DeleteDataStep.queue);
      ok = true;
      final again = await svc.deleteMyTransactions();
      expect(again.outcome, DeleteDataOutcome.done);
      expect(log, ['hook', 'hook']);
    });

    test('a hook that throws is the same: never a silent pass', () async {
      final r = await serviceWith(withHook(() async => throw StateError('platform'))).deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.queue);
    });

    test('no hook: unchanged (done, no hook anywhere)', () async {
      expect(ResetEnv.defaultDeviceWipe, isNull);
      final r = await env.service().deleteMyTransactions();
      expect(r.outcome, DeleteDataOutcome.done);
    });

    test('a default ResetEnv takes the process-wide hook; an explicit one wins', () async {
      ResetEnv.defaultDeviceWipe = () async {
        log.add('default');
        return true;
      };
      expect(await ResetEnv().runDeviceWipe(), isTrue);
      expect(log, ['default']);
      expect(await withHook(() async => false).runDeviceWipe(), isFalse);
    });
  });

  group('Level 2 and the start-up resume', () {
    test('Reset app runs the hook before the preferences are wiped; a failing hook leaves the flag', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('autoread_consent_version_v1', 1);
      final r = await serviceWith(withHook(() async {
        log.add('hook:consentStillThere=${(await env.prefsMap()).containsKey('autoread_consent_version_v1')}');
        return false;
      })).resetApp();
      expect(r.outcome, DeleteDataOutcome.notFinished);
      expect(r.failedStep, DeleteDataStep.queue);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue, reason: 'half-finished: the flag stays');
      expect(log, ['hook:consentStillThere=true']);

      // The next start-up resumes it and runs the hook again.
      expect(
          await ResetResume.runIfPending(
              env: withHook(() async {
            log.add('resume-hook');
            return true;
          })),
          isTrue);
      expect(log.last, 'resume-hook');
      expect(await env.prefsMap(), isEmpty);
    });

    test('a resume whose hook fails stays unfinished at the queue step and starts the app normally', () async {
      await (await SharedPreferences.getInstance()).setInt(kResetPendingKey, 123);
      final done = await ResetResume.runIfPending(env: withHook(() async => false));
      expect(done, isFalse);
      expect(ResetResume.lastOutcome, ResetResumeOutcome.notFinished);
      expect(ResetResume.lastFailedStep, DeleteDataStep.queue);
      expect((await env.prefsMap()).containsKey(kResetPendingKey), isTrue);
    });
  });
}
