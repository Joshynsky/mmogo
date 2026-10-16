// Shared harness for the S10b Backup page tests. Everything is a fake: the
// restore service, the export / share / temp files, the storage bridge and the
// auto-backup service (useFakeBackupUi). Invented data only; no name, amount,
// phone number or code anywhere.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/backup/backup_repair.dart';
import 'package:mmogo/data/backup/backup_service.dart';
import 'package:mmogo/data/backup/skipped_row_describer.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/screens/backup/backup_export_flow.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:mmogo/ui/screens/backup/restore_flow.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

import 'fake_backup_ui.dart';
import 'fake_restore_service.dart';

const kPageCounts = BackupCounts(transactions: 120, userClassifications: 3, receivers: 8, deletedLeftOut: 0);

double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// A [BackupExport] built by hand: [rows] are the left-out rows (described), and
/// the raw `skipped` list matches them by table.
BackupExport fakeExport({
  int tx = 120,
  int cats = 3,
  int receivers = 8,
  int repaired = 0,
  List<SkippedRowInfo> rows = const [],
}) {
  String table(SkipKind k) => switch (k) {
    SkipKind.entry => 'transactions',
    SkipKind.category => 'classifications',
    SkipKind.savedReceiver => 'counterparty_map',
  };
  return BackupExport(
    bytes: Uint8List.fromList([123, 125]),
    classifications: cats,
    transactions: tx,
    counterpartyMap: receivers,
    excludedSoftDeleted: 0,
    repairedCount: repaired,
    skipped: [
      for (var i = 0; i < rows.length; i++)
        BackupSkippedRow(table: table(rows[i].kind), rowId: i, field: 'x', rule: 'range'),
    ],
    skippedRows: rows,
  );
}

class FakeTempFiles implements BackupTempFiles {
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

/// The "Back up now" flow with every step faked. [export] is what the next
/// run returns; [shared] false means the share sheet was closed.
class FakeExportRig {
  FakeExportRig({BackupExport? export}) : export = export ?? fakeExport();

  BackupExport export;
  bool shared = true;
  Object? exportError;
  Completer<BackupExport>? gate;
  int exports = 0;
  int shares = 0;
  final files = FakeTempFiles();

  BackupExportFlow flow() => BackupExportFlow(
    export: () async {
      exports++;
      if (gate != null) return gate!.future;
      if (exportError != null) throw exportError!;
      return export;
    },
    files: files,
    share: (_, _) async {
      shares++;
      return shared;
    },
    recordLastBackup: (_) async => true,
    now: () => DateTime(2026, 9, 25, 9, 14),
  );
}

/// The Restore flow with a fake service and the fake bridge.
class FakeRestoreRig {
  FakeRestoreRig(this.ui);

  final FakeBackupUi ui;
  final service = FakeRestoreService();
  int refreshes = 0;

  void file() => ui.bridge.filePicks.add(PickedFile(name: 'b.json', bytes: Uint8List.fromList([1, 2, 3])));

  RestoreFlow flow() => RestoreFlow(
    service: () => service,
    bridge: ui.bridge,
    onDataChanged: () async {
      refreshes++;
    },
  );
}

/// Pumps the Backup page with fakes. [scale] is the text scale, [dark] picks
/// the dark palette. The window is tall so the whole page is built.
Future<void> pumpBackupPage(
  WidgetTester t, {
  BackupExportFlow? flow,
  RestoreFlow? restoreFlow,
  BackupCounts counts = kPageCounts,
  double scale = 1.0,
  bool dark = false,
  Size size = const Size(420, 3200),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    AppPaletteScope(
      controller: AppPaletteController('ocean', dark ? 'dark' : 'light'),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: BackupScreen(loadCounts: () async => counts, flow: flow, restoreFlow: restoreFlow),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

/// The height and width of the widget with [key] as it is laid out.
Size sizeOfKey(WidgetTester t, String key) => t.getSize(find.byKey(Key(key)));

/// True when the primary focus is the widget with [key] or inside it.
bool hasFocusKey(WidgetTester t, String key) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  final target = t.element(find.byKey(Key(key)));
  if (identical(focused, target)) return true;
  var found = false;
  focused.visitAncestorElements((e) {
    if (identical(e, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}
