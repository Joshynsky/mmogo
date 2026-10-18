import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/notifications_copy.dart';

void main() {
  const banned = [
    '100% private',
    'never',
    'cannot read other messages',
    'no permissions',
    'within 24 hours',
    'gdpr',
    'data protection',
  ];
  const autoReadWords = ['parse', 'categor', 'held', 'waiting', 'm-pesa', 'reading'];

  final file = File('lib/ui/copy/notifications_copy.dart').readAsStringSync().toLowerCase();

  test('no banned phrase in any string or in the file', () {
    for (final b in banned) {
      for (final s in kNotificationsCopyAll) {
        expect(s.toLowerCase().contains(b), isFalse, reason: '"$b" in "$s"');
      }
      expect(file.contains(b), isFalse, reason: '"$b" in the file');
    }
  });

  test('no auto-read wording in this file', () {
    for (final w in autoReadWords) {
      for (final s in kNotificationsCopyAll) {
        expect(s.toLowerCase().contains(w), isFalse, reason: '"$w" in "$s"');
      }
      expect(file.contains(w), isFalse, reason: '"$w" in the file');
    }
  });

  test('file does not import the auto-read folder', () {
    expect(file.contains('autoread'), isFalse);
  });

  test('heading and key strings', () {
    expect(newsHeadingWithCount('99+'), 'News (99+)');
    expect(kNotificationsTitle, 'Notifications');
    expect(kUpdateRowTitle, 'An update is available');
  });
}
