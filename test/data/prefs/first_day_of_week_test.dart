// CW1: the typed first-day-of-week reader. 1 = Monday ... 7 = Sunday; anything
// else gives Monday.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the key is the one the backup allowlist names, the default is Monday', () {
    expect(AppPrefs.keyFirstDayOfWeek, 'first_day_of_week');
    expect(AppPrefs.defaultFirstDayOfWeek, 1);
  });

  test('unset gives Monday', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AppPrefs.readFirstDayOfWeek(), 1);
  });

  test('1 through 7 are read as stored', () async {
    for (var v = 1; v <= 7; v++) {
      SharedPreferences.setMockInitialValues({'first_day_of_week': v});
      expect(await AppPrefs.readFirstDayOfWeek(), v);
    }
  });

  test('out of range, a string or a bool give Monday', () async {
    for (final bad in <Object>[0, 8, -3, 100, 'sunday', '7', true]) {
      SharedPreferences.setMockInitialValues({'first_day_of_week': bad});
      expect(await AppPrefs.readFirstDayOfWeek(), 1, reason: '$bad');
    }
  });
}
