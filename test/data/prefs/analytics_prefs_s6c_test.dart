// 0.1.2 S6c: the two typed Analytics preference readers (Show withdrawals in
// the chart, Where it went style). Reader only, no Settings control until S9.
// Same keys the backup allowlist names; anything outside the set gives the default.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the keys are the ones the backup allowlist already names', () {
    expect(AppPrefs.keyShowWithdrawalsInChart, 'show_withdrawals_in_chart');
    expect(AppPrefs.keyWhereItWentStyle, 'where_it_went_style');
    expect(backupSettingSpecFor(AppPrefs.keyShowWithdrawalsInChart)?.kind, BackupSettingKind.boolean);
    expect(backupSettingSpecFor(AppPrefs.keyWhereItWentStyle)?.choices, ['button', 'strip']);
  });

  group('Show withdrawals in the chart', () {
    test('unset gives false', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPrefs.readShowWithdrawalsInChart(), isFalse);
    });

    test('true and false are read as stored', () async {
      SharedPreferences.setMockInitialValues({'show_withdrawals_in_chart': true});
      expect(await AppPrefs.readShowWithdrawalsInChart(), isTrue);
      SharedPreferences.setMockInitialValues({'show_withdrawals_in_chart': false});
      expect(await AppPrefs.readShowWithdrawalsInChart(), isFalse);
    });

    test('a junk value or another type gives false', () async {
      for (final bad in <Object>['true', 'yes', 1, 'on', '']) {
        SharedPreferences.setMockInitialValues({'show_withdrawals_in_chart': bad});
        expect(await AppPrefs.readShowWithdrawalsInChart(), isFalse, reason: '$bad');
      }
    });
  });

  group('Where it went style', () {
    test('unset gives button', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.button);
    });

    test('button and strip are read as stored', () async {
      SharedPreferences.setMockInitialValues({'where_it_went_style': 'strip'});
      expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.strip);
      SharedPreferences.setMockInitialValues({'where_it_went_style': 'button'});
      expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.button);
    });

    test('a junk value, another type or another case gives button', () async {
      for (final bad in <Object>['grid', 'Strip', '', 2, true]) {
        SharedPreferences.setMockInitialValues({'where_it_went_style': bad});
        expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.button, reason: '$bad');
      }
    });
  });

  test('a reader does not read another key', () async {
    SharedPreferences.setMockInitialValues({'where_it_went_style': 'strip'});
    expect(await AppPrefs.readShowWithdrawalsInChart(), isFalse);
    SharedPreferences.setMockInitialValues({'show_withdrawals_in_chart': true, 'month_chart_style': 'days'});
    expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.button);
  });
}
