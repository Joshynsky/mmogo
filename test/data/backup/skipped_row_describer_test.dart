// S10a (A2b, A3, CB8, addendum D): the describer gives kind, date and type
// for an entry and a reason CODE, never a value. Pure tests plus a 200-row
// case through a real export of a temp (in-memory) database.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_validator.dart';
import 'package:mmogo/data/backup/skipped_row_describer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/restore_test_db.dart';

BackupSkippedRow _row(String table, int? id, String rule, [String field = 'amount_cents']) =>
    BackupSkippedRow(table: table, rowId: id, field: field, rule: rule);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('reason codes', () {
    test('every rule name in the repair source, and every validator reason, maps explicitly', () {
      final src = File('lib/data/backup/backup_repair.dart').readAsStringSync();
      final rules = <String>{
        for (final m in RegExp(r"_Problem\(\s*(?:'[^']*'|field)\s*,\s*'([^']+)'\s*\)").allMatches(src))
          m.group(1)!,
        // the cascade and dangling rules are plain string literals
        'its classification was skipped',
        'dangling reference',
        for (final r in RestoreRejectReason.values) r.name,
      };
      expect(rules.length, greaterThan(15));
      for (final r in rules) {
        expect(kSkipRuleReasons.containsKey(r), isTrue, reason: 'rule "$r" has no explicit reason');
      }
    });

    test('the function is total: an unknown or empty rule maps to the default', () {
      expect(skipReasonFor('a rule added later'), SkipReason.couldNotRead);
      expect(skipReasonFor(''), SkipReason.couldNotRead);
      expect(skipReasonFor('empty'), SkipReason.missingDetail);
      expect(skipReasonFor('range'), SkipReason.notAllowed);
      expect(skipReasonFor('its classification was skipped'), SkipReason.cascaded);
    });
  });

  group('describeSkipped', () {
    final at = DateTime(2026, 9, 21, 10, 30).millisecondsSinceEpoch;

    test('an entry gets date and type; the other kinds get neither', () {
      final out = describeSkipped(
        [_row('transactions', 1, 'range'), _row('classifications', 2, 'empty'), _row('counterparty_map', 3, 'format')],
        entryFacts: {1: EntryFacts(occurredAtMs: at, sourceType: 'PAYBILL')},
      );
      expect(out[0].kind, SkipKind.entry);
      expect(out[0].date, DateTime.fromMillisecondsSinceEpoch(at));
      expect(out[0].type, 'PAYBILL');
      expect(out[0].typeName, 'Paybill');
      expect(out[0].unreadable, isFalse);
      expect(out[1].kind, SkipKind.category);
      expect(out[1].date, isNull);
      expect(out[1].type, isNull);
      expect(out[2].kind, SkipKind.savedReceiver);
      expect(out[2].reason, SkipReason.notAllowed);
    });

    test('unjoinable (no id, no facts, bad type, date out of range) = an entry that could not be read', () {
      final out = describeSkipped(
        [
          _row('transactions', null, 'range'),
          _row('transactions', 9, 'range'),
          _row('transactions', 1, 'range'),
          _row('transactions', 2, 'range'),
          _row('transactions', 3, 'range'),
        ],
        entryFacts: {
          1: EntryFacts(occurredAtMs: at, sourceType: 'NOT_A_TYPE'),
          2: const EntryFacts(occurredAtMs: -5, sourceType: 'CASH'),
          3: const EntryFacts(occurredAtMs: 'text', sourceType: 'CASH'),
        },
      );
      for (final i in out) {
        expect(i.kind, SkipKind.entry);
        expect(i.unreadable, isTrue);
        expect(i.date, isNull);
        expect(i.type, isNull);
      }
    });

    test('a row cascaded from its category carries the cascade code', () {
      final out = describeSkipped(
        [_row('transactions', 1, 'its classification was skipped', 'classification')],
        entryFacts: {1: EntryFacts(occurredAtMs: at, sourceType: 'CASH')},
      );
      expect(out.single.reason, SkipReason.cascaded);
    });

    test('200 rows: N exactly, first 20 shown, "and M more not shown" = 180', () {
      final rows = [for (var i = 1; i <= 200; i++) _row('transactions', i, 'range')];
      final out = describeSkipped(rows, entryFacts: {
        for (var i = 1; i <= 200; i++) i: EntryFacts(occurredAtMs: at + i * 60000, sourceType: 'SEND_MONEY'),
      });
      final s = SkippedSummary.of(out);
      expect(s.count, 200);
      expect(s.shown, hasLength(20));
      expect(s.moreNotShown, 180);
      expect(s.shown.first.date, DateTime.fromMillisecondsSinceEpoch(at + 60000), reason: 'order kept');
      expect(SkippedSummary.of(out.sublist(0, 20)).moreNotShown, 0);
      expect(SkippedSummary.of(const []).count, 0);
    });
  });

  group('through a real export: no value ever leaks (200-row pattern search)', () {
    test('200 unreadable entries with planted names, numbers and codes', () async {
      final db = await openTestDb();
      await populate(db);
      final shopping = await seedId(db, 'BUY_GOODS:groceries');
      await db.transaction((txn) async {
        for (var i = 0; i < 200; i++) {
          await addTx(txn,
              code: 'LEAK${i.toString().padLeft(6, '0')}',
              source: 'BUY_GOODS',
              classId: shopping,
              amount: 99999999999 + i,
              label: 'SECRETSHOP$i',
              createdAt: t0 + 1000 + i);
        }
      });
      final export = await backupOf(db).export();
      expect(export.skippedCount, 200);
      final summary = export.notIncluded;
      expect(summary.count, 200);
      expect(summary.shown, hasLength(20));
      expect(summary.moreNotShown, 180);

      // Everything a UI could print from the described rows, all 200 of them.
      final text = [
        for (final i in export.skippedRows)
          '${i.toString()} ${i.kind} ${i.reason} ${i.date} ${i.type} ${i.typeName}',
        summary.toString(),
      ].join('\n');
      for (final planted in [
        'SECRET', 'LEAK', '99999999', '0712345678', 'JANE', 'DOE', 'DUKA', 'SCHOOL', 'ADM 42', 'Church',
      ]) {
        expect(text.contains(planted), isFalse, reason: 'leaked "$planted"');
      }
      // Date and type are the only content.
      for (final i in export.skippedRows) {
        expect(i.kind, SkipKind.entry);
        expect(i.type, 'BUY_GOODS');
        expect(i.date, isNotNull);
        expect(i.reason, SkipReason.notAllowed);
      }
      await db.close();
    });
  });
}
