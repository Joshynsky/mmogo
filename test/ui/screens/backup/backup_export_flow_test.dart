// B14: the Back up now flow (warning, export, temp file, share, cleanup, last
// backup write) with injected fakes. Plain test(): real file IO, no widgets.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/backup_format.dart';

BackupExport _export({int repaired = 0, List<BackupSkippedRow> skipped = const [], int deleted = 0}) => BackupExport(
  bytes: Uint8List.fromList([123, 125]),
  classifications: 4,
  transactions: 10,
  counterpartyMap: 2,
  excludedSoftDeleted: deleted,
  repairedCount: repaired,
  skipped: skipped,
);

class _DirFiles implements BackupTempFiles {
  _DirFiles(this.dir);
  final Directory dir;

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('mmogo_b14_'));
  tearDown(() => dir.deleteSync(recursive: true));

  final when = DateTime(2026, 9, 25, 9, 14, 5);

  test('export_deletes_temp_file (also when sharing throws)', () async {
    String? seenPath;
    var existedWhileSharing = false;
    var flow = BackupExportFlow(
      export: () async => _export(),
      files: _DirFiles(dir),
      now: () => when,
      share: (path, name) async {
        seenPath = path;
        existedWhileSharing = File(path).existsSync();
        return true;
      },
      recordLastBackup: (_) async => true,
    );
    final out = await flow.execute();
    expect(out, isA<BackupShared>());
    expect(existedWhileSharing, isTrue);
    expect(File(seenPath!).existsSync(), isFalse);
    expect(dir.listSync(), isEmpty);

    flow = BackupExportFlow(
      export: () async => _export(),
      files: _DirFiles(dir),
      now: () => when,
      share: (path, name) async => throw StateError('boom'),
      recordLastBackup: (_) async => true,
    );
    expect(await flow.execute(), isA<BackupFailed>());
    expect(dir.listSync(), isEmpty);
  });

  test('shared file name matches mmogo-backup-YYYYMMDD-HHMMSS.json and holds the export bytes', () async {
    String? name;
    List<int>? bytes;
    final flow = BackupExportFlow(
      export: () async => _export(),
      files: _DirFiles(dir),
      now: () => when,
      share: (path, n) async {
        name = n;
        bytes = File(path).readAsBytesSync();
        return true;
      },
      recordLastBackup: (_) async => true,
    );
    await flow.execute();
    expect(name, matches(RegExp(r'^mmogo-backup-\d{8}-\d{6}\.json$')));
    expect(name, 'mmogo-backup-20260925-091405.json');
    expect(BackupExportFlow.fileNameFor(when), name);
    expect(bytes, [123, 125]);
  });

  test('last backup is recorded only after a real share, never on failure or dismiss', () async {
    final recorded = <DateTime>[];
    BackupExportFlow make({required Future<bool> Function(String, String) share, BackupExporter? export}) =>
        BackupExportFlow(
          export: export ?? () async => _export(),
          files: _DirFiles(dir),
          now: () => when,
          share: share,
          recordLastBackup: (t) async {
            recorded.add(t);
            return true;
          },
        );

    expect(await make(share: (_, _) async => false).execute(), isA<BackupNotShared>());
    expect(recorded, isEmpty);

    expect(
      await make(
        share: (_, _) async => true,
        export: () async => throw const BackupTooLarge(what: 'bytes'),
      ).execute(),
      isA<BackupFailed>(),
    );
    expect(recorded, isEmpty);

    final ok = await make(share: (_, _) async => true).execute();
    expect(ok, isA<BackupShared>());
    expect(recorded, [when]);
  });

  test('last_backup_line_updates: the default recorder writes backup_last_manual_at to prefs', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await BackupPrefs.readLastManualAt(), isNull);
    final flow = BackupExportFlow(
      export: () async => _export(),
      files: _DirFiles(dir),
      now: () => when,
      share: (_, _) async => true,
    );
    expect(await flow.execute(), isA<BackupShared>());
    expect(await BackupPrefs.readLastManualAt(), when);
  });

  test('a failed last-backup write does not turn a shared backup into a failure', () async {
    final flow = BackupExportFlow(
      export: () async => _export(),
      files: _DirFiles(dir),
      now: () => when,
      share: (_, _) async => true,
      recordLastBackup: (_) async => false,
    );
    expect(await flow.execute(), isA<BackupShared>());
  });

  group('messages', () {
    test('no repaired or skipped wording when both are zero', () {
      final m = backupResultMessage(_export());
      expect(m, contains('10 transactions'));
      expect(m, isNot(contains('tidied')));
      expect(m, isNot(contains('left out')));
    });

    test('repaired and skipped counts are reported in plain words, with no row values', () {
      final m = backupResultMessage(
        _export(
          repaired: 3,
          skipped: [
            const BackupSkippedRow(table: 'transactions', rowId: 7, field: 'counterparty_label', rule: 'tooLong'),
            const BackupSkippedRow(table: 'transactions', rowId: 9, field: 'amount_cents', rule: 'range'),
          ],
        ),
      );
      expect(m, contains('3 entries were tidied'));
      expect(m, contains('2 entries could not be made valid and were left out'));
      expect(m, isNot(contains('counterparty_label')));
      expect(m, isNot(contains('amount_cents')));
    });

    test('not-included line, singular and plural', () {
      expect(
        notIncludedLine(3),
        '3 recently deleted transactions are not included. Restore them first if you want them in the backup.',
      );
      expect(notIncludedLine(1), startsWith('1 recently deleted transaction is not included.'));
    });

    test('last backup texts', () {
      expect(lastBackupLine(null), 'Never backed up');
      expect(lastBackupLine(when), 'Last backup (manual): 25 Sep 2026, 09:14');
      expect(backupRowSubtitle(null), 'Never backed up');
      expect(backupRowSubtitle(when), 'Last backup 25 Sep 2026');
    });
  });
}
