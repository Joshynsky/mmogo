// 0.1.2 S10b: pattern searches over the Backup and restore words (A7, A8, CB6)
// and over the code that builds them. Only the NEW or CHANGED backup strings
// are scanned; untouched older strings that still say "classification" are
// listed in s10b-deviations.md for MS2.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/skipped_row_describer.dart';
import 'package:mmogo/ui/copy/backup_copy.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/restore_result_sheet.dart';
import 'package:mmogo/ui/screens/backup/skipped_rows_list.dart';

String _read(String path) => File(path).readAsStringSync();

/// Source without full-line comments, import/export lines and widget keys
/// (none of those is phone-side text).
String _code(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//') && !l.startsWith('import ') && !l.startsWith('export '))
    .join('\n')
    .replaceAll(RegExp(r"Key\('[^']*'\)"), '');

/// Every quoted string literal in [src] (single or double quotes, no
/// interpolation handling: good enough to find words).
List<String> _literals(String src) => [
  for (final m in RegExp(r"'((?:[^'\\\n]|\\.)*)'|" r'"((?:[^"\\\n]|\\.)*)"').allMatches(_code(src)))
    (m.group(1) ?? m.group(2))!,
];

/// The words of a literal: interpolated expressions (`${rp.count}`, `$n`) removed.
String _words(String lit) => lit.replaceAll(RegExp(r'\$\{[^}]*\}?|\$[A-Za-z_][\w.]*'), '');

List<File> _dartFiles(String dir) => [
  for (final f in Directory(dir).listSync(recursive: true))
    if (f is File && f.path.endsWith('.dart')) f,
];

String _p(File f) => f.path.replaceAll('\\', '/');

/// Every S10b phone-side string, with sample arguments, in one list.
List<String> _s10bStrings() {
  final rows = [
    SkippedRowInfo(kind: SkipKind.entry, reason: SkipReason.missingDetail, date: DateTime(2026, 9, 3), type: 'SEND_MONEY'),
    const SkippedRowInfo(kind: SkipKind.entry, reason: SkipReason.couldNotRead),
    const SkippedRowInfo(kind: SkipKind.category, reason: SkipReason.cascaded),
    const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.notAllowed),
    const SkippedRowInfo(kind: SkipKind.savedReceiver, reason: SkipReason.couldNotRead),
  ];
  return [
    kBackupSharedTitle, kBackupFilesApp, kBackupNotSharedLine, kShowWhich, kHideList, kShowAll, kDone,
    kStillInApp, kOnlyDateAndType, kShowingFirst20, kRowUnreadableEntry, kRowCategory, kRowSavedReceiver,
    kReasonMissingDetail, kReasonNotAllowed, kReasonCouldNotRead, kReasonCascaded,
    kLostWarningTitle, kLostTickLabel, kContinue, kCancel, kChangedWhileChecking, kReplaceChecking,
    kReplaceSafetyCopyFailed, kUndoRestoresRest, kReplaceProgressTitle, kStepValidating, kStepSafetyCopy,
    kStepWriting, kRestoreSlow, kLeftoverTitle, kLeftoverCountedNote, kLeftoverWhatToDo, kOldFolderTitle,
    kOldFolderBody, kStopUsingIt, kKeepAccess, kKeepAccessHint, kOldFolderGroup, kFolderWorking,
    ...kRestoredSettingLabels.values,
    backupSharedCountsLine(1284, 17, 42), backupSharedCountsLine(1, 1, 1),
    backupLeftOutLine(3, allEntries: true), backupLeftOutLine(1, allEntries: false),
    backupTidiedLine(1), backupTidiedLine(4),
    for (final n in [0, 1, 3, 200]) ...[notIncludedTitle(n), lostWarningListTitle(n), lostResultListTitle(n)],
    moreNotShown(180),
    for (final n in [1, 3]) ...[
      lostWarningBody(n, allEntries: true), lostWarningBody(n, allEntries: false),
      replaceUndoLostNote(n), resultUndoneLostNote(n), lostForGoodLine(n, 'categories'),
      leftoverKeepLabel(n), leftoverDeleteLabel(n), leftoverContinueKeep(n), keptToast(n), deletedToast(n),
    ],
    keptAndLostSentence(live: 60, included: 57, lost: 3),
    replaceCountsLine(60, 3, 7), replaceRestoredLine(187, 0), replaceRestoredLine(187, 3),
    settingsRestoredLine(const ['Colour palette']), deletedPartlyToast(4, 2),
    leftoverBody(1, DateTime(2026, 9, 1), DateTime(2026, 9, 1)),
    leftoverBody(3, DateTime(2026, 9, 1), DateTime(2026, 9, 3)), leftoverBody(3, null, null),
    for (final r in rows) ...[skippedRowText(r, showReason: true), skippedRowText(r, showReason: false)],
    // data_copy.dart: new or changed in S10b
    kBackupNotRestorableByOlder, kWhyRestoreAsks, kReplaceOptionHelp, kReplaceOptionTitle, kReplaceConfirmTitle,
    kRememberedRecipientsNotInBackup, replaceRemovesLine(64, 3, 7), resultUndoneLostNote(5), kResultUndoneNote,
    kResultSafetyCopyStillThere, kAutoBackupStuckLine,
  ];
}

void main() {
  group('words (A8, CB6)', () {
    test('no S10b phone-side string says skipped, erase, wipe or classification', () {
      for (final s in _s10bStrings()) {
        final l = s.toLowerCase();
        for (final banned in ['skipped', 'wipe', 'classification']) {
          expect(l.contains(banned), isFalse, reason: '"$banned" in "$s"');
        }
        // "erase" is legitimate in exactly one string, and it is not an S10b one.
        expect(l.contains('erase'), isFalse, reason: 'erase in "$s"');
      }
    });

    test('every S10b string is non-empty, single-spaced and has no stray whitespace', () {
      for (final s in _s10bStrings()) {
        expect(s, isNotEmpty);
        expect(s, equals(s.trim()), reason: '"$s"');
        expect(s.contains('  '), isFalse, reason: '"$s"');
        expect(s.contains('\n'), isFalse, reason: '"$s"');
      }
    });

    test('"erase": the only string literal in the backup copy and screens is kUninstallErasesNotice', () {
      final hits = <String>[];
      for (final f in [..._dartFiles('lib/ui/screens/backup'), File('lib/ui/copy/data_copy.dart'), File('lib/ui/copy/backup_copy.dart')]) {
        for (final lit in _literals(f.readAsStringSync())) {
          if (lit.toLowerCase().contains('erase')) hits.add('${_p(f)}: $lit');
        }
      }
      expect(hits, hasLength(1), reason: '$hits');
      expect(hits.single, contains('Uninstalling mmogo erases your data from this phone.'));
    });

    test('"skipped": only the Merge result file-side column and kResultMergeNote say it', () {
      final hits = <String>[];
      for (final f in [..._dartFiles('lib/ui/screens/backup'), File('lib/ui/copy/data_copy.dart'), File('lib/ui/copy/backup_copy.dart')]) {
        for (final lit in _literals(f.readAsStringSync())) {
          if (_words(lit).toLowerCase().contains('skipped')) hits.add('${_p(f)}: $lit');
        }
      }
      expect(hits..sort(), [
        'lib/ui/copy/data_copy.dart: Skipped entries were already on this phone (matched by M-Pesa code). Nothing here was changed or deleted.',
        'lib/ui/screens/backup/restore_result_sheet.dart: Skipped',
      ]);
    });

    test('"classification" is gone from every file S10b created or rewrote (the settings key is not a word the user sees)', () {
      const files = [
        'lib/ui/copy/backup_copy.dart',
        'lib/ui/screens/backup/skipped_rows_list.dart',
        'lib/ui/screens/backup/backup_shared_sheet.dart',
        'lib/ui/screens/backup/backup_sheet_shell.dart',
        'lib/ui/screens/backup/replace_sheets.dart',
        'lib/ui/screens/backup/restore_progress_sheet.dart',
        'lib/ui/screens/backup/leftover_dialog.dart',
        'lib/ui/screens/backup/backup_section.dart',
        'lib/ui/screens/backup/restore_result_sheet.dart',
        'lib/ui/screens/backup/restore_flow.dart',
      ];
      final hits = <String>[];
      for (final path in files) {
        for (final lit in _literals(_read(path))) {
          if (_words(lit).toLowerCase().contains('classification')) hits.add('$path: $lit');
        }
      }
      expect(hits, ['lib/ui/copy/backup_copy.dart: auto_recognize_classifications'], reason: 'a stored settings key, never shown');
    });

    test('the Merge result table says Categories, not Classifications (the file-side table)', () {
      final lits = _literals(_read('lib/ui/screens/backup/restore_result_sheet.dart'));
      expect(lits, contains('Categories'));
      expect(lits, isNot(contains('Classifications')));
    });
  });

  group('D7 (A7)', () {
    test('the sentence is written once in lib/ and is exactly the PM wording', () {
      const d7 = 'A backup made with 0.1.2 cannot be restored by 0.1.1 or older.';
      expect(kBackupNotRestorableByOlder, d7);
      var n = 0;
      for (final f in _dartFiles('lib')) {
        n += d7.allMatches(f.readAsStringSync()).length;
      }
      expect(n, 1);
    });

    test('only the Backup page and the pager Backups card copy use it (S11a reuses the constant; Privacy does not)', () {
      final users = [
        for (final f in _dartFiles('lib'))
          if (f.readAsStringSync().contains('kBackupNotRestorableByOlder')) _p(f),
      ]..sort();
      // S11a: pager card 4 reuses the constant (one source); still no Privacy page.
      expect(users, [
        'lib/ui/copy/data_copy.dart',
        'lib/ui/copy/whats_new_pager_copy.dart',
        'lib/ui/screens/backup/backup_section.dart',
      ]);
    });
  });

  group('no value reaches a phone-side string (code scan)', () {
    test('the new sheets never interpolate a name, uri, amount, phone, code or folder', () {
      const files = [
        'lib/ui/copy/backup_copy.dart',
        'lib/ui/screens/backup/skipped_rows_list.dart',
        'lib/ui/screens/backup/backup_shared_sheet.dart',
        'lib/ui/screens/backup/replace_sheets.dart',
        'lib/ui/screens/backup/restore_progress_sheet.dart',
        'lib/ui/screens/backup/leftover_dialog.dart',
        'lib/ui/screens/backup/restore_result_sheet.dart',
      ];
      // The last part of the interpolated name must not be a value-carrying field.
      const bad = {'name', 'uri', 'url', 'amount', 'phone', 'code', 'label', 'counterparty', 'recipient', 'displayname', 'foldername', 'filename', 'path', 'bytes'};
      final seen = <String>{};
      for (final path in files) {
        for (final lit in _literals(_read(path))) {
          for (final m in RegExp(r'\$\{?([A-Za-z_][\w.]*)').allMatches(lit)) {
            final id = m.group(1)!;
            seen.add(id);
            // typeName is the display name of a transaction type (Send Money), not a value.
            expect(bad.contains(id.split('.').last.toLowerCase()), isFalse, reason: '$path interpolates "$id" in "$lit"');
          }
        }
      }
      expect(seen, isNotEmpty, reason: 'the scan saw interpolations');
    });

    test('a row text carries only a date, a type name and a fixed phrase', () {
      final r = SkippedRowInfo(
        kind: SkipKind.entry,
        reason: SkipReason.notAllowed,
        date: DateTime(2026, 9, 3),
        type: 'PAYBILL',
      );
      expect(skippedRowText(r, showReason: true), '03-09-2026, Paybill: a value is not allowed');
    });

    test('a date reads dd-mm-yyyy with leading zeros', () {
      expect(backupDmy(DateTime(2026, 1, 5)), '05-01-2026');
      expect(backupDmy(DateTime(2026, 12, 31)), '31-12-2026');
    });

    test('settings labels list only fixed labels, in a fixed order', () {
      expect(restoredSettingLabels(const ['where_it_went_style', 'palette_id', 'bogus']), ['Colour palette', 'Where it went style']);
    });
  });

  group('the old wording is gone', () {
    test('kReplaceNeedsCompleteCopy, the old failed banner and the one-line Replace progress no longer exist', () {
      final all = _dartFiles('lib').map((f) => f.readAsStringSync()).join('\n');
      expect(all.contains('kReplaceNeedsCompleteCopy'), isFalse);
      expect(all.contains('kAutoBackupFailedBanner'), isFalse);
      expect(all.contains('kRestoreReplacing'), isFalse);
      expect(all.contains('backupResultMessage'), isFalse);
      expect(all.contains('Backup ready'), isFalse);
      expect(all.contains('Check that you saved it'), isFalse);
    });
  });
}
