import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/bell_copy.dart';

void main() {
  test('nothing present', () {
    expect(bellSpokenLabel(update: false, newNotice: false), 'Notifications');
  });
  test('update only', () {
    expect(bellSpokenLabel(update: true, newNotice: false), 'Notifications, 1 update available');
  });
  test('new notice only', () {
    expect(bellSpokenLabel(update: false, newNotice: true), 'Notifications, 1 new notice');
  });
  test('both', () {
    expect(bellSpokenLabel(update: true, newNotice: true), 'Notifications, 1 update available, 1 new notice');
  });
  test('every label starts with Notifications', () {
    for (final u in [true, false]) {
      for (final n in [true, false]) {
        expect(bellSpokenLabel(update: u, newNotice: n), startsWith('Notifications'));
      }
    }
  });
}
