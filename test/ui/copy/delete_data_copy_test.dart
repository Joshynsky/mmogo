// 0.1.2 S9b-2: CB6 wording (pattern search over ONLY the delete strings, A10)
// and the A1 source guard (no real DeleteDataServiceImpl from the UI or from a
// test without an explicit env). Reads source files; touches nothing else.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';

/// The words CB6 and A10 ban in the delete strings, lower case.
const _banned = ['erase', 'left on this phone', 'authenticat', 'hi,', 'secure', 'wipe'];

String _code(String path) => File(path).readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

Iterable<File> _dart(String dir) =>
    Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  group('CB6: pattern search over the delete strings', () {
    test('no banned word in any delete string (case-insensitive)', () {
      for (final s in kDeleteDataAllStrings) {
        for (final w in _banned) {
          expect(s.toLowerCase().contains(w), isFalse, reason: '"$s" contains "$w"');
        }
      }
    });

    test('"deleted from this phone" is said', () {
      final all = kDeleteDataAllStrings.join('\n').toLowerCase();
      expect(all, contains('deleted from this phone'));
      expect(kDeleteDoneTitle.toLowerCase(), contains('deleted from this phone'));
      // F3: the option sentences are short ("Deletes ..."); the plain list of what each really clears is
      // pinned in test/data/maintenance/delete_sentences_f3_test.dart.
      expect(kDeleteLevel1Short, startsWith('Deletes your transactions'));
      expect(kDeleteLevel2Short, startsWith('Deletes everything mmogo keeps on this phone'));
    });

    test('the sheets and results state what stays (backups, auto list, SMS, safety copy, categories)', () {
      expect(kDeleteIntro, 'This cannot be undone.');
      expect(kDeleteExtraBackups, 'Backup files you saved earlier are not touched.');
      expect(kDeleteStayBackups, contains('Backup files you saved earlier'));
      expect(kDeleteStayAutoList, contains('automatic backup'));
      expect(kDeleteStaySms, contains('original SMS'));
      expect(kDeleteLevel1SafetyGone, contains('Undo of your last Replace is gone'));
      expect(kDeleteLevel1CategoriesStay, contains('renamed or hid'));
      expect(kDeleteExtraLevel2, allOf(contains('preferences'), contains('own categories'), contains('display name')));
      expect(kDeleteLevel1Short, allOf(contains('names it remembers'), contains('Keeps your settings and categories')));
      expect(kDeleteLevel2Short, allOf(contains('first launch'), contains('Backup files you saved earlier stay')));
    });

    test('nothing promises anything about future automatic backup files', () {
      for (final s in kDeleteDataAllStrings) {
        expect(s.toLowerCase(), isNot(contains('future')), reason: s);
        expect(s.toLowerCase(), isNot(contains('will be backed up')), reason: s);
      }
    });

    test('the typed word is a confirmation: it is never called authentication', () {
      expect(kDeleteWordLabel, 'Type DELETE to confirm');
    });

    test('every Delete data string constant is in the scanned list (a new constant must be added)', () {
      final names = RegExp(r'^const (k\w+) =', multiLine: true)
          .allMatches(File('lib/ui/copy/delete_data_copy.dart').readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();
      // Not strings of a Delete data screen: the word itself and the stale-Undo text.
      names.removeAll(['kDeleteWordWord', 'kEntryNoLongerThere', 'kDeleteDataAllStrings', 'kDeleteExtras']);
      expect(kDeleteDataAllStrings.length, names.length, reason: 'add the new constant to kDeleteDataAllStrings');
    });

    test('the new UI files (code only, comments skipped) hold no banned word either', () {
      for (final f in [
        'lib/ui/screens/settings/delete_data_row.dart',
        'lib/ui/screens/settings/delete_data_sheet.dart',
        'lib/ui/screens/settings/delete_data_run_sheet.dart',
        'lib/ui/screens/settings/delete_data_factory.dart',
        'lib/ui/copy/delete_data_copy.dart',
      ]) {
        final code = _code(f).toLowerCase();
        for (final w in _banned) {
          expect(code.contains(w), isFalse, reason: '$f contains "$w"');
        }
      }
    });
  });

  group('A1: nothing real can be reached', () {
    // Spelled in two parts so this file does not match itself.
    const needle = 'DeleteDataServiceImpl' '(';

    test('lib constructs the real service in ONE place only (the factory)', () {
      final hits = <String>[];
      for (final f in _dart('lib')) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.endsWith('lib/ui/screens/settings/delete_data_factory.dart')) continue;
        if (p.endsWith('lib/data/maintenance/delete_data_service.dart')) continue; // the class itself
        if (f.readAsStringSync().contains(needle)) hits.add(p);
      }
      expect(hits, isEmpty, reason: 'only delete_data_factory.dart may construct the real service');
      expect(File('lib/ui/screens/settings/delete_data_factory.dart').readAsStringSync().contains(needle), isTrue);
    });

    test('no widget under lib/ui builds it', () {
      for (final f in _dart('lib/ui')) {
        final p = f.path.replaceAll(r'\', '/');
        if (p.endsWith('delete_data_factory.dart')) continue;
        expect(f.readAsStringSync().contains(needle), isFalse, reason: p);
      }
    });

    test('every construction under test/ passes env: (never the default collaborators)', () {
      for (final f in _dart('test')) {
        final text = f.readAsStringSync();
        var from = 0;
        while (true) {
          final i = text.indexOf(needle, from);
          if (i < 0) break;
          final window = text.substring(i, (i + 500).clamp(0, text.length));
          expect(window.contains('env:'), isTrue, reason: '${f.path} constructs the real service without env:');
          from = i + needle.length;
        }
      }
    });

    test('the fake factory hook is the only way a test reaches Settings\' default', () {
      final text = File('lib/ui/screens/settings/delete_data_factory.dart').readAsStringSync();
      expect(text, contains('static DeleteDataService Function()? override'));
    });
  });
}
