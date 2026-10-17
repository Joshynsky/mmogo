// 0.1.2 S11a (A7): file scans over lib/ for the What's-new pager work.
//  - the D7 sentence is DEFINED once and written in no other lib literal;
//  - the stale constant `kCheckNowOff` is gone (a planted constant is caught);
//  - the new copy files have no banned phrase (W3 and the canonical line are
//    exempt) and never retype a fixed sentence;
//  - the retired 0.1.1 What's-new text is gone.
// No second shared banned list: the public-wording test (Q7, S11c) owns that.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';

String _norm(String p) => p.replaceAll('\\', '/');

Map<String, String> _lib() => {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart')) _norm(f.path): f.readAsStringSync(),
};

String _noLineComments(String src) => src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// Files that still mention the removed constant.
List<String> staleCheckNowOff(Map<String, String> files) => [
  for (final e in files.entries)
    if (RegExp(r'\bkCheckNowOff\b').hasMatch(e.value)) e.key,
];

const _newCopyFiles = [
  'lib/ui/copy/whats_new_pager_copy.dart',
  'lib/ui/copy/whats_new_copy.dart',
  'lib/ui/whats_new/whats_new_cards.dart',
  'lib/ui/whats_new/whats_new_pager.dart',
  'lib/ui/whats_new/whats_new_entry.dart',
  'lib/ui/whats_new/whats_new_hook.dart',
];

const _banned = <String>[
  'zero permissions',
  'not even internet',
  'erases',
  'authentication',
  'nothing is sent anywhere',
  'no permissions',
  'no internet',
];

List<String> bannedHits(String text) {
  final low = text.toLowerCase();
  return [for (final b in _banned) if (low.contains(b)) b];
}

void main() {
  test('D7: the sentence is DEFINED once, in data_copy.dart, and written in no other lib literal', () {
    const sentence = 'A backup made with 0.1.2 cannot be restored by 0.1.1 or older.';
    expect(kBackupNotRestorableByOlder, sentence);
    final files = _lib();
    final withSentence = [
      for (final e in files.entries)
        for (var i = 0; i < sentence.allMatches(_noLineComments(e.value)).length; i++) e.key,
    ];
    expect(withSentence, ['lib/ui/copy/data_copy.dart']);
    final defs = [
      for (final e in files.entries)
        for (var i = 0; i < RegExp(r'const\s+kBackupNotRestorableByOlder\s*=').allMatches(e.value).length; i++) e.key,
    ];
    expect(defs, ['lib/ui/copy/data_copy.dart']);
  });

  test('kCheckNowOff (the stale Check now caption constant) is gone from lib/', () {
    expect(staleCheckNowOff(_lib()), isEmpty);
  });

  test('the scan itself catches a planted kCheckNowOff', () {
    final planted = {..._lib(), 'lib/planted.dart': "const kCheckNowOff = 'x';"};
    expect(staleCheckNowOff(planted), ['lib/planted.dart']);
  });

  test('the new copy files have no banned phrase (W3 and the canonical line exempt)', () {
    final files = _lib();
    for (final path in _newCopyFiles) {
      expect(files.containsKey(path), isTrue, reason: path);
      var src = _noLineComments(files[path]!);
      // The constant's NAME holds the word "Erases"; it is the exempt W3 sentence by reference.
      src = src
          .replaceAll(kUninstallErasesNotice, '')
          .replaceAll(kPrivacySentenceStandard, '')
          .replaceAll('kUninstallErasesNotice', '');
      expect(bannedHits(src), isEmpty, reason: path);
    }
  });

  test('the words the pager really shows have no banned phrase either', () {
    final shown = [
      kWhatsNewPagerTitle,
      kWhatsNewEntryBody,
      kWhatsNewEntryButton,
      kWhatsNewCard1Title,
      kWhatsNewCard1Body,
      kWhatsNewCard2Title,
      kWhatsNewCard2Body,
      kWhatsNewCard3Title,
      kWhatsNewCard3Body,
      kWhatsNewCard3Extra,
      kWhatsNewCard4Title,
      kWhatsNewCard4Body,
      kWhatsNewCard5Title,
      kWhatsNewCard5Body,
    ].join('\n').replaceAll(kUninstallErasesNotice, '').replaceAll(kPrivacySentenceStandard, '');
    expect(bannedHits(shown), isEmpty);
    // "erases" appears only through W3 (uninstalling), on card 4.
    expect(kWhatsNewCard4Body, contains(kUninstallErasesNotice));
  });

  test('the banned-phrase check catches a planted phrase', () {
    expect(bannedHits('This app has zero permissions.'), ['zero permissions']);
    expect(bannedHits('Delete data erases your entries.'), ['erases']);
  });

  test('the pager copy never retypes a fixed sentence: it uses the named constants', () {
    final src = _noLineComments(_lib()['lib/ui/copy/whats_new_pager_copy.dart']!);
    expect(src, contains(r'$kBackupNotRestorableByOlder'));
    expect(src, contains(r'$kUninstallErasesNotice'));
    expect(src, contains(r'$kNetworkSeenSentence'), reason: 'card 5 (F4 R14): only the second half of W7');
    expect(src, isNot(contains(r'$kNetworkSentence')), reason: 'the full W7 would repeat the canonical sentence');
    expect(src, contains(r'$kPrivacySentenceStandard'));
    expect(src, isNot(contains(r'$kFirstDayRegrouped')), reason: 'F4 R4: card 2 has its own text; the line is for the First day dialog');
    expect(src, isNot(contains('GitHub sees your IP')));
    expect(src, isNot(contains('cannot be restored by')));
    expect(src, isNot(contains('Uninstalling mmogo')));
    expect(src, isNot(contains('No permissions except internet')));
    expect(src, isNot(contains('Past weeks are regrouped')));
    // The sign-off is written once.
    expect(src, isNot(contains('— Josh')));
  });

  test('the retired 0.1.1 What\'s-new text is gone from lib/', () {
    for (final e in _lib().entries) {
      expect(e.value, isNot(contains('still need to be added by hand')), reason: e.key);
      expect(e.value, isNot(contains('mmogo now uses the internet.')), reason: e.key);
      expect(e.value, isNot(contains('kWhatsNewInternetLead')), reason: e.key);
    }
    expect(File('lib/ui/whats_new/whats_new_dialog.dart').existsSync(), isFalse);
  });
}
