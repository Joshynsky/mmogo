// B14: the Backup and restore page in every state, with fakes (no real
// database, no real file IO, no platform channels): empty, loading, counts
// failed, normal, warning dialog (cancel / acknowledge), progress, success,
// repaired/skipped, failure, share dismissed. Also the Settings > Your data
// row. The temp-file lifecycle and the prefs write are covered by the plain
// tests in backup_export_flow_test.dart.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/screens/settings/data_section.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_storage_bridge.dart';

const _counts = BackupCounts(transactions: 120, userClassifications: 3, receivers: 8, deletedLeftOut: 5);
const _emptyCounts = BackupCounts(transactions: 0, userClassifications: 0, receivers: 0, deletedLeftOut: 2);

BackupExport _export({int repaired = 0, List<BackupSkippedRow> skipped = const []}) => BackupExport(
  bytes: Uint8List.fromList([123, 125]),
  classifications: 3,
  transactions: 120,
  counterpartyMap: 8,
  excludedSoftDeleted: 5,
  repairedCount: repaired,
  skipped: skipped,
);

class _Files implements BackupTempFiles {
  final List<String> written = [];
  final List<String> deleted = [];

  @override
  Future<String> write(String name, Uint8List bytes) async {
    written.add(name);
    return '/tmp/$name';
  }

  @override
  Future<void> delete(String path) async => deleted.add(path);
}

class _Run {
  final files = _Files();
  int exports = 0;
  int shares = 0;
  int recorded = 0;
  Completer<BackupExport>? gate;
  Object? exportError;
  bool shareResult = true;
}

BackupExportFlow _flow(_Run r, {BackupExport Function()? build}) => BackupExportFlow(
  export: () async {
    r.exports++;
    if (r.gate != null) return r.gate!.future;
    if (r.exportError != null) throw r.exportError!;
    return (build ?? _export)();
  },
  files: r.files,
  share: (_, _) async {
    r.shares++;
    return r.shareResult;
  },
  recordLastBackup: (_) async {
    r.recorded++;
    return true;
  },
  now: () => DateTime(2026, 9, 25, 9, 14),
);

Future<void> _pump(
  WidgetTester t, {
  BackupCounts? counts = _counts,
  Object? countsError,
  BackupExportFlow? flow,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: BackupScreen(
        loadCounts: () async {
          if (countsError != null) throw countsError;
          return counts!;
        },
        flow: flow,
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _backUpAndAcknowledge(WidgetTester t) async {
  await t.tap(find.byKey(const Key('backUpNowButton')));
  await t.pumpAndSettle();
  await t.tap(find.text('Share backup'));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('normal: header card, counts line, not-included line, warning, enabled button', (t) async {
    await _pump(t);
    expect(find.text('Your data lives only on this phone'), findsOneWidget);
    expect(find.text(kUninstallErasesNotice), findsOneWidget);
    expect(find.text(kPhoneTransferNotice), findsOneWidget);
    expect(find.text('Never backed up'), findsOneWidget);
    expect(
      find.text(
        'A backup holds your 120 transactions, 3 classifications you made, 8 saved receivers and your settings, in one file.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('5 recently deleted transactions are not included. Restore them first if you want them in the backup.'),
      findsOneWidget,
    );
    expect(find.text(kBackupFileWarning), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('backUpNowButton'))).onPressed, isNotNull);
    // B17, B21 and B32 add these later: not on the page yet.
    expect(find.text('Restore from a file'), findsNothing);
    expect(find.text('Auto-backup'), findsNothing);
    expect(find.text('Privacy and your data'), findsNothing);
  });

  testWidgets('last backup line reads the saved manual time', (t) async {
    SharedPreferences.setMockInitialValues({
      BackupPrefs.keyBackupLastManualAt: DateTime(2026, 9, 20, 18, 5).millisecondsSinceEpoch,
    });
    await _pump(t);
    expect(find.text('Last backup (manual): 20 Sep 2026, 18:05'), findsOneWidget);
  });

  testWidgets('no recently deleted line when none are deleted', (t) async {
    await _pump(
      t,
      counts: const BackupCounts(transactions: 1, userClassifications: 0, receivers: 0, deletedLeftOut: 0),
    );
    expect(find.byKey(const Key('backupNotIncluded')), findsNothing);
    expect(find.textContaining('1 transaction, 0 classifications you made'), findsOneWidget);
  });

  testWidgets('empty: clear message, button disabled, no counts line', (t) async {
    await _pump(t, counts: _emptyCounts);
    expect(find.textContaining('Nothing to back up yet.'), findsOneWidget);
    expect(find.byKey(const Key('backupCountsLine')), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('backUpNowButton'))).onPressed, isNull);
    expect(find.text(kBackupFileWarning), findsOneWidget);
  });

  testWidgets('loading: counts placeholder while the numbers load, button enabled', (t) async {
    final gate = Completer<BackupCounts>();
    await t.pumpWidget(MaterialApp(home: BackupScreen(loadCounts: () => gate.future)));
    await t.pump();
    await t.pump();
    expect(find.text('Reading your data...'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('backUpNowButton'))).onPressed, isNotNull);
    gate.complete(_counts);
    await t.pumpAndSettle();
    expect(find.text('Reading your data...'), findsNothing);
  });

  testWidgets('counts failed: message with Retry that reloads', (t) async {
    var fail = true;
    await t.pumpWidget(
      MaterialApp(
        home: BackupScreen(
          loadCounts: () async {
            if (fail) throw StateError('db');
            return _counts;
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Could not read your data.'), findsOneWidget);
    fail = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Could not read your data.'), findsNothing);
    expect(find.byKey(const Key('backupCountsLine')), findsOneWidget);
  });

  testWidgets('export_shows_warning_before_share', (t) async {
    final run = _Run();
    await _pump(t, flow: _flow(run));
    await t.tap(find.byKey(const Key('backUpNowButton')));
    await t.pumpAndSettle();
    expect(find.text('Before you back up'), findsOneWidget);
    // W1 now appears twice: the page panel and the dialog.
    expect(find.text(kBackupFileWarning), findsNWidgets(2));
    expect(find.text('Share backup'), findsOneWidget);
    expect(run.exports, 0);
    expect(run.shares, 0);
  });

  testWidgets('export_cancel_does_not_share', (t) async {
    final run = _Run();
    await _pump(t, flow: _flow(run));
    await t.tap(find.byKey(const Key('backUpNowButton')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(run.exports, 0);
    expect(run.shares, 0);
    expect(run.recorded, 0);
    expect(run.files.written, isEmpty);
    expect(find.text('Before you back up'), findsNothing);
    expect(find.text('Never backed up'), findsOneWidget);
  });

  testWidgets('progress: shows Preparing your backup while the export runs, then the result', (t) async {
    final run = _Run()..gate = Completer<BackupExport>();
    await _pump(t, flow: _flow(run));
    await t.tap(find.byKey(const Key('backUpNowButton')));
    await t.pumpAndSettle();
    await t.tap(find.text('Share backup'));
    await t.pump();
    await t.pump();
    expect(find.text('Preparing your backup...'), findsOneWidget);
    expect(find.byKey(const Key('backupProgress')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('backUpNowButton'))).onPressed, isNull);
    run.gate!.complete(_export());
    await t.pumpAndSettle();
    expect(find.text('Preparing your backup...'), findsNothing);
    expect(find.byKey(const Key('backupResult')), findsOneWidget);
  });

  testWidgets('success: shared once, temp file cleaned, last backup line updates, no repaired or skipped wording', (
    t,
  ) async {
    final bridge = FakeStorageBridge();
    StorageBridge.instance = bridge;
    final run = _Run();
    await _pump(t, flow: _flow(run));
    await _backUpAndAcknowledge(t);
    expect(run.exports, 1);
    expect(run.shares, 1);
    expect(run.recorded, 1);
    expect(run.files.written, ['mmogo-backup-20260925-091400.json']);
    expect(run.files.deleted, ['/tmp/mmogo-backup-20260925-091400.json']);
    expect(find.text('Last backup (manual): 25 Sep 2026, 09:14'), findsOneWidget);
    final msg = t.widget<Text>(find.byKey(const Key('backupResult'))).data!;
    expect(msg, contains('120 transactions'));
    expect(msg, isNot(contains('tidied')));
    expect(msg, isNot(contains('left out')));
    // Manual backups go through the share sheet, not the folder bridge.
    expect(bridge.calls, isEmpty);
  });

  testWidgets('repaired and skipped counts are reported when non-zero', (t) async {
    final run = _Run();
    await _pump(
      t,
      flow: _flow(
        run,
        build: () => _export(
          repaired: 2,
          skipped: const [BackupSkippedRow(table: 'transactions', rowId: 4, field: 'amount_cents', rule: 'range')],
        ),
      ),
    );
    await _backUpAndAcknowledge(t);
    final msg = t.widget<Text>(find.byKey(const Key('backupResult'))).data!;
    expect(msg, contains('2 entries were tidied'));
    expect(msg, contains('1 entry could not be made valid and was left out'));
    expect(msg, isNot(contains('amount_cents')));
  });

  testWidgets('failure: the plain message, nothing shared, last backup not written', (t) async {
    final run = _Run()..exportError = const BackupTooLarge(what: 'bytes');
    await _pump(t, flow: _flow(run));
    await _backUpAndAcknowledge(t);
    expect(find.text('Could not create the backup'), findsOneWidget);
    expect(find.text('Could not create the backup. Nothing was shared.'), findsOneWidget);
    expect(run.shares, 0);
    expect(run.recorded, 0);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(find.text('Never backed up'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('backUpNowButton'))).onPressed, isNotNull);
  });

  testWidgets('share sheet dismissed: told so, last backup not written, temp file cleaned', (t) async {
    final run = _Run()..shareResult = false;
    await _pump(t, flow: _flow(run));
    await _backUpAndAcknowledge(t);
    expect(find.text('The share sheet was closed. No backup was saved.'), findsOneWidget);
    expect(run.recorded, 0);
    expect(run.files.deleted, hasLength(1));
    expect(find.text('Never backed up'), findsOneWidget);
  });

  group('Settings > Your data row', () {
    Widget host({String subtitle = 'Never backed up'}) => MaterialApp(
      onGenerateRoute: (s) => MaterialPageRoute<void>(
        settings: s,
        builder: (ctx) => s.name == Routes.backup
            ? const Scaffold(body: Text('BACKUP PAGE'))
            : Scaffold(
                body: DataSection(
                  palette: AppPalette.of(ctx),
                  tourKey: GlobalKey(),
                  exportSubtitle: 'x',
                  exportEnabled: false,
                  onExport: () {},
                  backupSubtitle: subtitle,
                ),
              ),
      ),
    );

    testWidgets('shows "Backup and restore" with the subtitle and opens the page', (t) async {
      await t.pumpWidget(host(subtitle: 'Last backup 25 Sep 2026'));
      expect(find.text('Backup and restore'), findsOneWidget);
      expect(find.text('Last backup 25 Sep 2026'), findsOneWidget);
      await t.tap(find.text('Backup and restore'));
      await t.pumpAndSettle();
      expect(find.text('BACKUP PAGE'), findsOneWidget);
    });

    testWidgets('never backed up subtitle', (t) async {
      await t.pumpWidget(host());
      expect(find.text('Never backed up'), findsOneWidget);
    });
  });
}
