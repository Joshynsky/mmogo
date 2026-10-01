// B13: the shared data-safety copy holds the required phrases and none of the
// banned ones.
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';

void main() {
  const all = {
    'kBackupFileWarning': kBackupFileWarning,
    'kCloudSyncNotice': kCloudSyncNotice,
    'kNetworkDisclosure': kNetworkDisclosure,
    'kUpdateCheckCadence': kUpdateCheckCadence,
    'kFeedbackHint': kFeedbackHint,
    'kWhyRestoreAsks': kWhyRestoreAsks,
    'kPhoneTransferNotice': kPhoneTransferNotice,
  };

  test('copy_contains_required_phrases_and_none_of_the_banned', () {
    // W1 says "not encrypted" (the approved wording), the same claim the
    // B13 row calls "unencrypted".
    expect(kBackupFileWarning, contains('not encrypted'));
    expect(kBackupFileWarning, contains('names and phone numbers'));
    expect(kCloudSyncNotice, contains('names and phone numbers'));
    expect(kNetworkDisclosure, contains('GitHub sees your IP address'));
    expect(kNetworkDisclosure, contains('at most once a week after a successful check'));
    expect(kNetworkDisclosure, contains('when you open the app'));
    expect(kNetworkDisclosure, contains('No entries, names or messages are sent'));
    expect(kFeedbackHint, contains('M-Pesa messages'));
    expect(kFeedbackHint, contains('public issue'));
    expect(kWhyRestoreAsks, contains('Merge'));
    expect(kWhyRestoreAsks, contains('Replace'));
    expect(kPhoneTransferNotice, contains('phone-to-phone'));
    expect(kPhoneTransferNotice, contains('backup file is the only way'));

    const banned = ['nothing is sent anywhere', 'no permissions', 'no internet', 'never connects'];
    for (final e in all.entries) {
      for (final b in banned) {
        expect(e.value.toLowerCase(), isNot(contains(b)), reason: '${e.key} must not say "$b"');
      }
    }
  });

  test('every constant is non-empty, single-spaced and has no stray whitespace', () {
    for (final e in all.entries) {
      expect(e.value.trim(), e.value, reason: e.key);
      expect(e.value, isNotEmpty, reason: e.key);
      expect(e.value, isNot(contains('  ')), reason: e.key);
    }
  });
}
