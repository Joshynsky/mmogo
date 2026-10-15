// 0.1.2 S9a: the Look writers and the device-only appearance_mode.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_setting_keys.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/domain/analytics/chart_blocks.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<SharedPreferences> p() => SharedPreferences.getInstance();

  test('every Look writer stores its value EXPLICITLY, also at the default, and the reader returns it', () async {
    expect(await AppPrefs.writeFirstDayOfWeek(1), isTrue);
    expect(await AppPrefs.writeMonthChartStyle(MonthChartStyle.weeks), isTrue);
    expect(await AppPrefs.writeYearViewAmounts(YearViewAmounts.quarters), isTrue);
    expect(await AppPrefs.writeShowWithdrawalsInChart(false), isTrue);
    expect(await AppPrefs.writeWhereItWentStyle(WhereItWentStyle.button), isTrue);
    final prefs = await p();
    expect(prefs.get('first_day_of_week'), 1);
    expect(prefs.get('month_chart_style'), 'weeks');
    expect(prefs.get('year_view_amounts'), 'quarters');
    expect(prefs.get('show_withdrawals_in_chart'), false);
    expect(prefs.get('where_it_went_style'), 'button');

    await AppPrefs.writeFirstDayOfWeek(7);
    await AppPrefs.writeMonthChartStyle(MonthChartStyle.days);
    await AppPrefs.writeYearViewAmounts(YearViewAmounts.months);
    await AppPrefs.writeShowWithdrawalsInChart(true);
    await AppPrefs.writeWhereItWentStyle(WhereItWentStyle.strip);
    expect(await AppPrefs.readFirstDayOfWeek(), 7);
    expect(await AppPrefs.readMonthChartStyle(), MonthChartStyle.days);
    expect(await AppPrefs.readYearViewAmounts(), YearViewAmounts.months);
    expect(await AppPrefs.readShowWithdrawalsInChart(), isTrue);
    expect(await AppPrefs.readWhereItWentStyle(), WhereItWentStyle.strip);
  });

  test('a first day outside 1..7 is refused and nothing is written', () async {
    expect(await AppPrefs.writeFirstDayOfWeek(0), isFalse);
    expect(await AppPrefs.writeFirstDayOfWeek(8), isFalse);
    expect((await p()).containsKey('first_day_of_week'), isFalse);
  });

  test('appearance_mode: system by default, round trips, bad stored or written value is not kept', () async {
    expect(await AppPrefs.readAppearanceMode(), 'system');
    expect(await AppPrefs.writeAppearanceMode('dark'), isTrue);
    expect(await AppPrefs.readAppearanceMode(), 'dark');
    expect(await AppPrefs.writeAppearanceMode('purple'), isFalse);
    expect(await AppPrefs.readAppearanceMode(), 'dark');
    SharedPreferences.setMockInitialValues({'appearance_mode': 'neon'});
    expect(await AppPrefs.readAppearanceMode(), 'system');
    SharedPreferences.setMockInitialValues({'appearance_mode': 3});
    expect(await AppPrefs.readAppearanceMode(), 'system');
  });

  test('appearance_mode is device-only: not in the backup allowlist; the five Look keys are', () {
    final keys = kBackupSettingSpecs.map((s) => s.prefsKey).toSet();
    expect(keys.contains('appearance_mode'), isFalse);
    expect(
      keys,
      containsAll(['first_day_of_week', 'month_chart_style', 'year_view_amounts', 'show_withdrawals_in_chart', 'where_it_went_style']),
    );
  });
}
