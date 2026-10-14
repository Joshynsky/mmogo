// 0.1.2 S6b: the two typed chart preference readers (Month chart style, Year
// view amounts). Reader only, no Settings control until S9. Same keys the
// backup allowlist names; any value outside the set gives the default.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the keys are the ones the backup allowlist already names, with the same choices', () {
    expect(AppPrefs.keyMonthChartStyle, 'month_chart_style');
    expect(AppPrefs.keyYearViewAmounts, 'year_view_amounts');
    final month = backupSettingSpecFor(AppPrefs.keyMonthChartStyle);
    final year = backupSettingSpecFor(AppPrefs.keyYearViewAmounts);
    expect(month?.choices, ['days', 'weeks']);
    expect(year?.choices, ['quarters', 'months']);
  });

  group('Month chart style', () {
    test('unset gives weeks', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.weeks);
    });

    test('weeks and days are read as stored', () async {
      SharedPreferences.setMockInitialValues({'month_chart_style': 'days'});
      expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.days);
      SharedPreferences.setMockInitialValues({'month_chart_style': 'weeks'});
      expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.weeks);
    });

    test('a junk value, another type or another case gives weeks', () async {
      for (final bad in <Object>['fortnights', 'Days', '', 7, true, 'quarters']) {
        SharedPreferences.setMockInitialValues({'month_chart_style': bad});
        expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.weeks, reason: '$bad');
      }
    });
  });

  group('Year view amounts', () {
    test('unset gives quarters', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.quarters);
    });

    test('quarters and months are read as stored', () async {
      SharedPreferences.setMockInitialValues({'year_view_amounts': 'months'});
      expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.months);
      SharedPreferences.setMockInitialValues({'year_view_amounts': 'quarters'});
      expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.quarters);
    });

    test('a junk value, another type or another case gives quarters', () async {
      for (final bad in <Object>['weekly', 'Months', '', 3, false, 'days']) {
        SharedPreferences.setMockInitialValues({'year_view_amounts': bad});
        expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.quarters, reason: '$bad');
      }
    });
  });

  test('the two readers do not read each other\'s key', () async {
    SharedPreferences.setMockInitialValues({'month_chart_style': 'days'});
    expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.quarters);
    SharedPreferences.setMockInitialValues({'year_view_amounts': 'months'});
    expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.weeks);
  });
}
