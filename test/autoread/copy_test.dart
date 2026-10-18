@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';

void main() {
  const banned = [
    '100% private',
    'never',
    'cannot read other messages',
    'no permissions',
    'within 24 hours',
    'compliant',
    'data protection act',
  ];

  test('no banned phrase in any auto-read string', () {
    for (final s in allAutoReadCopy()) {
      for (final b in banned) {
        expect(s.toLowerCase(), isNot(contains(b)), reason: '"$s" has "$b"');
      }
    }
  });

  test('the copy source types no 24, 48 or 36', () {
    final src = File('lib/autoread/ui/notifications_autoread_copy.dart').readAsStringSync();
    for (final n in ['24', '48', '36']) {
      expect(src, isNot(contains(n)));
    }
  });

  test('the held window line comes from the constant', () {
    expect(kHeldWindowLine, kHeldWindowCopy);
    expect(kHeldWindowLine, contains('${kHeldWindow.inHours} hours'));
  });

  test('signed strings are verbatim', () {
    expect(parseChipSpoken(3), 'To parse, 3');
    expect(categorizeChipSpoken(3), 'To categorize, 3');
    expect(categorizeChipSpoken(120), 'To categorize, 99 or more');
    expect(parseChipSpoken(0), 'To parse, none');
    expect(kWaitingNotCounted,
        'Waiting items are not counted in your totals until you categorize them.');
    expect(kCouldNotRead, 'Could not read this one. Paste it instead.');
    expect(kGoneLine, 'This message is no longer available. Paste it instead.');
    expect(kRemoveBody, contains('stays in your phone’s Messages. You can paste it again.'));
    expect(kPasteSheetHeading, 'Copy the M-Pesa message first, then continue to Add.');
    expect(kPasteContinue, 'Continue to Add');
    expect(kPasteGoStraight, 'Already copied it? Go straight to Add.');
    expect(kFromMessageTextOnly,
        'From the message text only. mmogo cannot check it with M-Pesa.');
    expect(expiresInLine(hours: 4, underOneHour: false), 'expires in 4 h');
    expect(expiresInLine(hours: 1, underOneHour: true), 'expires in under 1 h');
  });

  test('the gone recovery names finding the message and pasting it', () {
    final s = kGoneRecovery.toLowerCase();
    expect(s, contains('find'));
    expect(s, contains('paste'));
  });
}
