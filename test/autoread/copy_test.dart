@Tags(['autoread'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/held_window.dart';
import 'package:mmogo/autoread/ui/notifications_autoread_copy.dart';
import 'package:mmogo/autoread/ui/settings_autoread_copy.dart';

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
    // F3 added kAutoReadPageCopyAll and F6 allAutoReadActionsCopy: scan them too (19-10-2026).
    for (final s in [...allAutoReadCopy(), ...kAutoReadPageCopyAll, ...allAutoReadActionsCopy()]) {
      for (final b in banned) {
        expect(s.toLowerCase(), isNot(contains(b)), reason: '"$s" has "$b"');
      }
    }
  });

  test('no banned phrase in the Settings, consent and help strings (F10)', () {
    // The Judge allows exactly two "never" sentences (condition 10); only those
    // are removed before the scan, so any other "never" still fails.
    for (final s in allSettingsAutoReadCopy()) {
      final t = s
          .toLowerCase()
          .replaceAll(kOtherMessagesLine.toLowerCase(), '')
          .replaceAll(kDeveloperLine.toLowerCase(), '');
      for (final b in [...banned, 'private', 'compliance', 'complies', 'guarantee', 'always', 'no one', 'nobody']) {
        expect(t, isNot(contains(b)), reason: '"$s" has "$b"');
      }
      expect(t, isNot(contains('@')), reason: 'no email: "$s"');
    }
  });

  test('the Settings copy source types no hour count and names the person once', () {
    final src = File('lib/autoread/ui/settings_autoread_copy.dart').readAsStringSync();
    for (final n in ['24', '48', '36']) {
      expect(src, isNot(contains(n)));
    }
    expect('Joshua Waga'.allMatches(src).length, 1);
    expect(kResponsiblePerson, 'Joshua Waga');
    expect(src, contains('PM read pending'));
    expect(kConsentHeld, contains(kHeldWindowCopy));
    expect(kConsentHeld, contains('${kHeldWindow.inHours} hours'));
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
