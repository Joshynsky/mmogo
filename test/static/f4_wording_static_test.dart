// 0.1.2 F4 wording scans: the card 3 sentence and the CHANGELOG say the same
// (and name the 01 numbers), the Welcome title has no version, the word
// "classification" is not on any visible string in lib/ui (identifiers, keys
// and the backup file's JSON keys are untouched), and the verb after a count
// agrees with it ("1 transaction uses", "3 transactions use").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/screens/manage_classifications_screen.dart';

String _norm(String p) => p.replaceAll('\\', '/');

Map<String, String> _ui() => {
  for (final f in Directory('lib/ui').listSync(recursive: true).whereType<File>())
    if (f.path.endsWith('.dart')) _norm(f.path): f.readAsStringSync(),
};

/// String literals (single or double quoted, one line) of [src] that read like
/// prose: they hold a space and the word "classification(s)" on a word boundary.
/// Comment lines are skipped. Identifiers, keys and routes have no space.
List<String> classificationProse(String src) {
  final out = <String>[];
  final lit = RegExp(r"'((?:[^'\\\n]|\\.)*)'|" r'"((?:[^"\\\n]|\\.)*)"');
  for (final line in src.split('\n')) {
    if (line.trimLeft().startsWith('//')) continue;
    for (final m in lit.allMatches(line)) {
      final s = m.group(1) ?? m.group(2) ?? '';
      if (s.contains(' ') && RegExp(r'\bclassifications?\b', caseSensitive: false).hasMatch(s)) out.add(s);
    }
  }
  return out;
}

void main() {
  group('R10: card 3 and the CHANGELOG say the same thing, 01 numbers included', () {
    const sentence =
        'Earlier versions counted one number as two people when it was written two ways, for example '
        '0712 345 678 and +254 712 345 678 (07 and 01 numbers alike). '
        'We have corrected that: they now count as one person on Paid to, '
        'and their totals are added together. The numbers saved on your entries do not change.';

    test('card 3 body is the approved sentence', () {
      expect(kWhatsNewCard3Body, sentence);
    });

    test('the CHANGELOG 0.1.2 bullet holds the same sentence and the title', () {
      final log = File('CHANGELOG.md').readAsStringSync().replaceAll('\r\n', '\n');
      final section = log.substring(0, log.indexOf('## 0.1.1'));
      expect(section, contains('- **Same phone number, one person.** $sentence\n'));
      expect(section, contains('(07 and 01 numbers alike)'));
      expect(section, isNot(contains('That was a mistake')));
    });

    test('no public file keeps "That was a mistake" for the 0.1.2 correction', () {
      expect(kWhatsNewCard3Body, isNot(contains('mistake')));
    });
  });

  test('R6: the Welcome title carries no version number', () {
    expect(kWelcomeNoticeTitle, 'Hello, and welcome to mmogo');
  });

  test('R14: card 5 does not say "used only to check for updates" twice, and the Privacy page keeps both sentences', () {
    expect('used only to check for updates'.allMatches(kWhatsNewCard5Body), hasLength(1));
    expect(kWhatsNewCard5Body, startsWith(kPrivacySentenceStandard));
    expect(kWhatsNewCard5Body, endsWith(kNetworkSeenSentence));
    // The full W7 is unchanged (value), so the Privacy page and the Updates page keep both sentences.
    expect(
      kNetworkSentence,
      'The internet is used only to check for updates. GitHub sees your IP address and that the request comes '
      'from the mmogo app. No entries, names or messages are sent.',
    );
  });

  group('C2: no visible "classification" wording in lib/ui', () {
    test('no string literal in lib/ui reads "classification(s)"', () {
      final hits = <String>[];
      for (final e in _ui().entries) {
        for (final s in classificationProse(e.value)) {
          hits.add('${e.key}: $s');
        }
      }
      expect(hits, isEmpty);
    });

    test('the scan itself catches a planted visible string and ignores keys and routes', () {
      expect(classificationProse("Text('No classifications yet')"), ['No classifications yet']);
      expect(classificationProse("hintText: 'New classification name'"), ['New classification name']);
      expect(classificationProse('"A classification named"'), ['A classification named']);
      expect(classificationProse("const manage = '/manage-classifications';"), isEmpty);
      expect(classificationProse("Key('mpesaClassificationRow_1')"), isEmpty);
      expect(classificationProse("// 'a classification here'"), isEmpty);
    });
  });

  group('A10: the verb after a count agrees with it', () {
    test('the Delete category message: 1 uses, 3 use, 0 use', () {
      expect(
        deleteCategoryMessage(1, 'Rent'),
        '1 transaction uses "Rent". It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.',
      );
      expect(
        deleteCategoryMessage(3, 'Rent'),
        '3 transactions use "Rent". It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.',
      );
      expect(
        deleteCategoryMessage(0, 'Rent'),
        'No transactions currently use "Rent". It moves to Inactive (deleted) and you can restore it any time. Past entries keep it.',
      );
      expect(deleteCategoryMessage(1, 'Rent'), isNot(startsWith('1 transaction use "')));
    });

    test('the screen uses that function; no count + "use" literal is left in lib/', () {
      final all = _ui();
      expect(all['lib/ui/screens/manage_classifications_screen.dart'], contains('deleteCategoryMessage(count, item.name)'));
      final bad = RegExp(r"transaction\$\{[^}]*\? '' : 's'\} use\b");
      for (final e in all.entries) {
        expect(bad.hasMatch(e.value), isFalse, reason: e.key);
      }
    });
  });
}
