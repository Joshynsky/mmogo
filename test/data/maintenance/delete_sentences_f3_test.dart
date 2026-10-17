// F3 (0.1.2 corrections): the Delete data option sentences are PINNED to what
// the service really clears. The real DeleteDataServiceImpl runs against a
// REAL SQLite file in a TEMP directory with mock prefs, a temp safety folder
// and fakes (test/support/data_op_env.dart; nothing real is touched). The test
// OBSERVES what each level cleared and kept, compares that with a plain-language
// list written here, and then checks that the on-screen sentences say exactly
// those things. If the service starts (or stops) clearing something, the first
// expect fails and the sentence has to be re-written. Plain test(): a real
// Database hangs in testWidgets.
//
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/maintenance/delete_data_service.dart';
import 'package:mmogo/ui/copy/delete_data_copy.dart';
import 'package:path/path.dart' as p;

import '../../support/data_op_env.dart';

/// Keys the service clears for internal reasons (a queue that the standard build
/// never fills, a merge report, a counter): not something a sentence claims.
const _internalKeys = {'pending_entries_v1', 'phone_merge_report_v1', 'auto_backup_since_count', 'recipient_types_v1'};

Future<Set<String>> _observe(DataOpEnv env, Map<String, Object?> prefsBefore) async {
  final cleared = <String>{};
  final db = await env.open();
  final live = await env.count('SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL');
  final soft = await env.count('SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL');
  if (live == 0) cleared.add('your transactions');
  if (soft == 0) cleared.add('Recently deleted');
  if (await env.count('SELECT COUNT(*) FROM counterparty_classification_map') == 0) cleared.add('learned receivers');
  final after = await env.prefsMap();
  if (!after.containsKey('recipient_types_v1')) cleared.add('remembered names');
  final safety = Directory(p.join(env.safetyBase.path, 'safety'));
  if (!await safety.exists() || (await safety.list().toList()).isEmpty) cleared.add('safety copy of the last Replace');
  if (await env.count('SELECT COUNT(*) FROM classifications WHERE seed_key IS NULL') == 0) cleared.add('own categories');
  final renamed = await db.rawQuery("SELECT name FROM classifications WHERE seed_key = 'SEND_MONEY:rent'");
  if (renamed.first['name'] != 'Landlord') cleared.add('renamed built-in categories');
  if (await env.count("SELECT COUNT(*) FROM classifications WHERE seed_key IS NOT NULL AND active = 0") == 0) {
    cleared.add('hidden built-in categories');
  }
  for (final e in prefsBefore.entries) {
    if (_internalKeys.contains(e.key)) continue;
    if (after[e.key] != e.value) cleared.add('preferences');
  }
  if (!after.containsKey('auto_backup_folder_uri')) cleared.add('auto-backup folder');
  if (!after.containsKey('user_display_name')) cleared.add('display name');
  return cleared;
}

void main() {
  late DataOpEnv env;

  setUp(() async {
    env = await DataOpEnv.create();
    await env.populateAll();
  });
  tearDown(() => env.dispose());

  // What the service really clears, in the words a person would use.
  const level1Clears = {
    'your transactions',
    'Recently deleted',
    'learned receivers',
    'remembered names',
    'safety copy of the last Replace',
  };
  const level2Clears = {
    ...level1Clears,
    'own categories',
    'renamed built-in categories',
    'hidden built-in categories',
    'preferences',
    'auto-backup folder',
    'display name',
  };

  test('Delete my transactions clears exactly: transactions, Recently deleted, learned receivers, remembered names, the safety copy', () async {
    final before = await env.prefsMap();
    // The test data has something of every kind (so "cleared" cannot be a false alarm).
    expect(await env.count('SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL'), greaterThan(0));
    expect(await env.count('SELECT COUNT(*) FROM counterparty_classification_map'), greaterThan(0));
    expect(await env.count('SELECT COUNT(*) FROM classifications WHERE seed_key IS NULL'), greaterThan(0));
    final r = await env.service().deleteMyTransactions();
    expect(r.outcome, DeleteDataOutcome.done);
    expect(await _observe(env, before), level1Clears, reason: 'the service clears something the sentences do not say (or stopped clearing something they do)');
    // Nothing outside the app's own database / prefs / safety copy was deleted: no backup file.
    expect(env.fs.deleted, isEmpty, reason: 'Level 1 deletes no file at all');
    expect(env.bridge.calls.where((c) => c.startsWith('releaseGrant')), isEmpty, reason: 'the backup folder is kept');
  });

  test('Reset app clears everything the app keeps, and still leaves saved backup files alone', () async {
    final before = await env.prefsMap();
    final r = await env.service().resetApp();
    expect(r.outcome, DeleteDataOutcome.done);
    // The database file is new: fresh built-ins only.
    expect(await _observe(env, before), level2Clears);
    expect(await env.prefsMap(), isEmpty, reason: 'every preference');
    // Only the database file and its journal files were deleted: never a backup file.
    for (final path in env.fs.deleted) {
      expect(p.basename(path), startsWith('mmogo.db'), reason: path);
    }
    // The only thing done to the backup folder is giving the permission back.
    expect(env.bridge.calls.where((c) => !c.startsWith('releaseGrant')), isEmpty);
    expect(env.bridge.calls.where((c) => c.startsWith('releaseGrant')), isNotEmpty);
  });

  group('the sentences say exactly that', () {
    final level1 = '$kDeleteLevel1Short $kDeleteExtraLevel1 $kDeleteExtraBackups';
    final level2 = '$kDeleteLevel2Short $kDeleteExtraLevel2 $kDeleteExtraBackups';

    // observed fact -> the words the text for that level must contain
    const words = {
      'your transactions': 'your transactions',
      'Recently deleted': 'Recently deleted',
      'learned receivers': 'receivers mmogo has learned',
      'remembered names': 'names it remembers',
      'safety copy of the last Replace': 'safety copy of your last Replace',
    };

    test('Delete my transactions says every fact it really clears', () {
      for (final f in level1Clears) {
        expect(level1, contains(words[f]!), reason: f);
      }
    });

    test('Delete my transactions says it KEEPS settings and categories, and does not claim to clear them', () {
      expect(kDeleteLevel1Short, contains('Keeps your settings and categories.'));
      expect(level1.toLowerCase(), isNot(contains('preferences')));
      expect(level1.toLowerCase(), isNot(contains('your own categories')));
      expect(level1.toLowerCase(), isNot(contains('everything')));
    });

    test('Reset app says every fact it really clears', () {
      const level2Words = {
        'own categories': 'your own categories',
        'renamed built-in categories': 'changes you made to built-in categories',
        'hidden built-in categories': 'changes you made to built-in categories',
        'preferences': 'your preferences',
        'auto-backup folder': 'forgets the auto-backup folder',
        'display name': 'your display name',
      };
      expect(level2, contains('Deletes everything mmogo keeps on this phone'));
      expect(level2, contains('returns it to first launch'));
      // The facts it shares with Level 1 are covered by "everything mmogo keeps".
      for (final f in level2Clears) {
        if (level1Clears.contains(f)) continue;
        expect(level2, contains(level2Words[f]!), reason: f);
      }
    });

    test('both options say saved backup files are NOT deleted (the mock said "everything" and did not)', () {
      expect(level1, contains('Backup files you saved earlier are not touched.'));
      expect(kDeleteLevel2Short, contains('Backup files you saved earlier stay where they are.'));
      expect(kDeleteLevel2Short.toLowerCase(), isNot(contains('erases everything')));
    });

    test('no sentence uses a word the wording rules ban', () {
      for (final s in [level1, level2, kDeleteIntro]) {
        for (final w in ['erase', 'wipe', 'secure', 'authenticat']) {
          expect(s.toLowerCase(), isNot(contains(w)), reason: '"$s" has "$w"');
        }
      }
    });
  });
}
