// PR1 / CA6 / CB13 (mmogo 0.1.2, S3c): the preferences allowlist is ELEVEN keys.
// Denied keys are never read (A4); Merge applies only what is unset and Replace
// overwrites (A5); hostile values refuse the whole file; the snapshot never
// emits a device-only key; and a round trip keeps the five new choices.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/backup_settings.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/restore_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/backup_test_data.dart';
import '../../support/fake_safety_copy_store.dart';
import '../../support/restore_test_db.dart';

const _five = <String, Object?>{
  'first_day_of_week': 7,
  'month_chart_style': 'weeks',
  'year_view_amounts': 'months',
  'show_withdrawals_in_chart': true,
  'where_it_went_style': 'strip',
};

/// Keys that must stay on the phone whatever a file says.
const _deviceOnly = <String, Object?>{
  'appearance_mode': 'dark',
  'recipient_types_v1': '{"x":"y"}',
  'pending_entries_v1': '[1]',
  'autoread_consent_version_v1': 1, // AR9 (I2): the consent answer never travels
  'reset_pending_v1': true,
  'phone_merge_report_v1': '3',
  'auto_backup_folder_uri': 'content://evil',
  'auto_backup_enabled': true,
  'update_check_enabled': false,
};

RestoreService svc(Database db) => RestoreService(
      db: () async => db,
      backup: backupOf(db),
      safety: FakeSafetyCopyStore([]),
      settings: BackupSettings(prefs: SharedPreferences.getInstance),
      validateInIsolate: false,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('hostile values for the five new keys refuse the whole file (H2)', () {
    void refuses(Map<String, Object?> prefs, String key) {
      expect(
        () => BackupValidator.validate(bytesOf(validBackupJson()..['prefs'] = prefs)),
        throwsA(isA<RestoreRejected>()
            .having((e) => e.reason, 'reason', RestoreRejectReason.invalidRow)
            .having((e) => e.table, 'table', 'prefs')
            .having((e) => e.field, 'field', key)),
        reason: '$prefs',
      );
    }

    test('first_day_of_week: 0, 8, 7.0, "1", true, null, -1 are refused; 1 and 7 are accepted', () {
      for (final bad in <Object?>[0, 8, 7.0, '1', true, null, -1, 1.5]) {
        refuses({'first_day_of_week': bad}, 'first_day_of_week');
      }
      for (final good in [1, 2, 7]) {
        expect(BackupValidator.validate(bytesOf(validBackupJson()..['prefs'] = {'first_day_of_week': good})).prefs,
            {'first_day_of_week': good});
      }
    });

    test('a bad choice string or type on each choice key is refused; the listed choices are accepted', () {
      refuses({'month_chart_style': 'weekly'}, 'month_chart_style');
      refuses({'month_chart_style': 1}, 'month_chart_style');
      refuses({'year_view_amounts': 'Quarters'}, 'year_view_amounts');
      refuses({'year_view_amounts': true}, 'year_view_amounts');
      refuses({'where_it_went_style': 'tabs'}, 'where_it_went_style');
      refuses({'where_it_went_style': ''}, 'where_it_went_style');
      refuses({'show_withdrawals_in_chart': 'yes'}, 'show_withdrawals_in_chart');
      refuses({'show_withdrawals_in_chart': 1}, 'show_withdrawals_in_chart');
      for (final entry in [
        {'month_chart_style': 'days'}, {'month_chart_style': 'weeks'},
        {'year_view_amounts': 'quarters'}, {'year_view_amounts': 'months'},
        {'where_it_went_style': 'button'}, {'where_it_went_style': 'strip'},
        {'show_withdrawals_in_chart': false}, {'show_withdrawals_in_chart': true},
      ]) {
        expect(BackupValidator.validate(bytesOf(validBackupJson()..['prefs'] = entry)).prefs, entry);
      }
    });

    test('a bad value refuses the file even when every other key is fine (nothing is half-applied)', () async {
      final db = await openTestDb();
      final json = validBackupJson()..['prefs'] = {..._five, 'first_day_of_week': 9};
      await expectLater(svc(db).restore(bytesOf(json), RestoreMode.merge), throwsA(isA<RestoreRejected>()));
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
      await db.close();
    });
  });

  group('H1 denied keys are dropped, nothing is written', () {
    test('the validator drops every device-only key and keeps the five new ones', () {
      final v = BackupValidator.validate(bytesOf(validBackupJson()..['prefs'] = {..._five, ..._deviceOnly}));
      expect(v.prefs, _five);
      for (final k in _deviceOnly.keys) {
        expect(v.prefs.containsKey(k), isFalse, reason: k);
      }
    });

    test('a restore leaves device-only prefs as they were, and an existing recipient_types_v1 survives Replace', () async {
      SharedPreferences.setMockInitialValues({
        'appearance_mode': 'light',
        'recipient_types_v1': '{"mine":"1"}',
        'pending_entries_v1': '[7]',
        'autoread_consent_version_v1': 1,
        'reset_pending_v1': false,
        'auto_backup_folder_uri': 'content://mine',
      });
      final db = await openTestDb();
      final json = validBackupJson()..['prefs'] = {..._five, ..._deviceOnly};
      for (final mode in RestoreMode.values) {
        final r = await svc(db).restore(bytesOf(json), mode);
        expect(r.settingsApplied, isTrue);
        final p = await SharedPreferences.getInstance();
        expect(p.getString('appearance_mode'), 'light', reason: mode.name);
        expect(p.getString('recipient_types_v1'), '{"mine":"1"}', reason: mode.name);
        expect(p.getString('pending_entries_v1'), '[7]', reason: mode.name);
        expect(p.getInt('autoread_consent_version_v1'), 1, reason: 'a restore leaves the consent answer as it was (${mode.name})');
        expect(p.getBool('reset_pending_v1'), false, reason: mode.name);
        expect(p.getString('auto_backup_folder_uri'), 'content://mine', reason: mode.name);
        for (final k in const ['phone_merge_report_v1', 'auto_backup_enabled', 'update_check_enabled']) {
          expect(p.containsKey(k), isFalse, reason: '$k is never written (${mode.name})');
        }
      }
      await db.close();
    });

    test('P6-13T: a restore file (Merge and Replace) carrying recipient_types_v1 leaves prefs unchanged', () async {
      const planted = '{"PLANTED NAME":{"t":"POCHI_LA_BIASHARA","at":1}}';
      for (final mine in <String?>[null, '{"MINE":{"t":"SEND_MONEY","at":2}}']) {
        for (final mode in RestoreMode.values) {
          SharedPreferences.setMockInitialValues({'recipient_types_v1': ?mine});
          final db = await openTestDb();
          final json = validBackupJson()..['prefs'] = {'recipient_types_v1': planted};
          await svc(db).restore(bytesOf(json), mode);
          final p = await SharedPreferences.getInstance();
          expect(p.getString('recipient_types_v1'), mine, reason: '${mode.name} mine=$mine');
          expect(p.getKeys(), mine == null ? isEmpty : {'recipient_types_v1'}, reason: mode.name);
          await db.close();
        }
      }
    });

    test('NEGATIVE CONTROL: the same restore DOES write an allowlisted key (the test can see a write)', () async {
      final db = await openTestDb();
      await svc(db).restore(bytesOf(validBackupJson()..['prefs'] = {'first_day_of_week': 3}), RestoreMode.merge);
      expect((await SharedPreferences.getInstance()).getInt('first_day_of_week'), 3);
      await db.close();
    });
  });

  group('H4 the snapshot', () {
    test('emits the five when set and never a device-only key, even when it is set on the phone', () async {
      SharedPreferences.setMockInitialValues({..._five, ..._deviceOnly}.map((k, v) => MapEntry(k, v as Object)));
      final snap = await BackupSettings().snapshot();
      expect(snap, _five);
      for (final k in _deviceOnly.keys) {
        expect(snap.containsKey(k), isFalse, reason: k);
      }
      expect(BackupSettings.firstProblem(snap), isNull);
    });

    test('a stored junk value of a new key is left out (the exporter never writes a refusable block)', () async {
      SharedPreferences.setMockInitialValues({
        'first_day_of_week': 0,
        'month_chart_style': 'bogus',
        'year_view_amounts': 'months',
      });
      expect(await BackupSettings().snapshot(), {'year_view_amounts': 'months'});
    });
  });

  group('round trip and A5', () {
    test('export on phone A, restore Replace on phone B: the five choices arrive equal', () async {
      SharedPreferences.setMockInitialValues({..._five}.map((k, v) => MapEntry(k, v as Object)));
      final a = await openTestDb();
      final BackupExport export = await backupOf(a).export();
      final file = BackupValidator.validate(export.bytes);
      expect(file.prefs, _five);

      SharedPreferences.setMockInitialValues({
        'first_day_of_week': 2,
        'month_chart_style': 'days',
        'where_it_went_style': 'button',
      });
      final b = await openTestDb();
      final r = await svc(b).restore(export.bytes, RestoreMode.replace);
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('first_day_of_week'), 7);
      expect(p.getString('month_chart_style'), 'weeks');
      expect(p.getString('year_view_amounts'), 'months');
      expect(p.getBool('show_withdrawals_in_chart'), true);
      expect(p.getString('where_it_went_style'), 'strip');
      // The result lists what was restored.
      expect(r.settings.applied.toSet(), _five.keys.toSet());
      expect(r.settings.skipped, isEmpty);
      await a.close();
      await b.close();
    });

    test('Merge applies only what is unset (and lists the rest as skipped); Replace overwrites', () async {
      SharedPreferences.setMockInitialValues({
        'first_day_of_week': 1, // the DEFAULT, written explicitly: it counts as SET
        'month_chart_style': 'days',
      });
      final db = await openTestDb();
      final bytes = bytesOf(validBackupJson()..['prefs'] = {..._five});
      final merged = await svc(db).restore(bytes, RestoreMode.merge);
      var p = await SharedPreferences.getInstance();
      expect(p.getInt('first_day_of_week'), 1, reason: 'a set key (even at its default) is kept');
      expect(p.getString('month_chart_style'), 'days');
      expect(p.getString('year_view_amounts'), 'months', reason: 'unset keys are filled');
      expect(p.getBool('show_withdrawals_in_chart'), true);
      expect(p.getString('where_it_went_style'), 'strip');
      expect(merged.settings.skipped.toSet(), {'first_day_of_week', 'month_chart_style'});
      expect(merged.settings.applied.toSet(), {'year_view_amounts', 'show_withdrawals_in_chart', 'where_it_went_style'});

      await svc(db).restore(bytes, RestoreMode.replace);
      p = await SharedPreferences.getInstance();
      expect(p.getInt('first_day_of_week'), 7, reason: 'Replace overwrites');
      expect(p.getString('month_chart_style'), 'weeks');
      await db.close();
    });

    test('a file with none of the five leaves them alone (no version gating, no defaults written)', () async {
      SharedPreferences.setMockInitialValues({'first_day_of_week': 3});
      final db = await openTestDb();
      await svc(db).restore(bytesOf(validBackupJson()..['prefs'] = {'palette_id': 'leaf'}), RestoreMode.replace);
      final p = await SharedPreferences.getInstance();
      expect(p.getInt('first_day_of_week'), 3);
      expect(p.containsKey('month_chart_style'), isFalse);
      await db.close();
    });
  });
}
