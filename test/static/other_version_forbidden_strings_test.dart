// The standard APK must carry no auto-read words. The files that make up the
// "Other version of mmogo" pieces are scanned for them (the plain words "SMS
// permission" in user text are allowed). Two files that must name the build
// flag, updates_startup.dart and about_section.dart, are guarded elsewhere
// (layout_test); here only the files that never need the flag are scanned.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const files = [
    'lib/ui/copy/other_version_copy.dart',
    'lib/data/updates/other_version_notice.dart',
  ];
  final forbidden = [
    'autoread',
    'auto_read',
    'mmogo_mpesa_messages',
    'RECEIVE_SMS',
    'READ_SMS',
    'POST_NOTIFICATIONS',
    'SmsReceiver',
    'BROADCAST_SMS',
  ];

  test('the new other-version files contain no auto-read strings', () {
    for (final path in files) {
      final text = File(path).readAsStringSync().toLowerCase();
      for (final word in forbidden) {
        expect(text.contains(word.toLowerCase()), isFalse, reason: '$path contains $word');
      }
    }
  });

  test('the notice constants are named kOtherVersion...', () {
    final text = File('lib/ui/copy/other_version_copy.dart').readAsStringSync();
    final names = RegExp(r'const (k\w+)').allMatches(text).map((m) => m.group(1)!);
    expect(names, isNotEmpty);
    expect(names.every((n) => n.startsWith('kOtherVersion')), isTrue);
  });
}
