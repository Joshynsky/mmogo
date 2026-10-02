// B21: the Auto-backup card on the Backup page in every state, with the fake
// storage bridge and in-memory prefs (no platform channels, no real database).
// States: off, on without a folder, working, last failed, paused. Flows: the
// setup sheet (W1) BEFORE the picker, the cloud notice (W2) right after a pick
// and only then, choose another folder, cancel, picker error, steppers and
// their bounds, turning off, the last-backup line, live pause.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/backup/backup_counts.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/backup/backup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_storage_bridge.dart';

const _counts = BackupCounts(transactions: 12, userClassifications: 1, receivers: 2, deletedLeftOut: 0);
const _uri = 'content://tree/mmogo-backups';
const _folder = PickedFolder(uri: _uri, name: 'Documents / mmogo-backups');
const _other = PickedFolder(uri: 'content://tree/other', name: 'Other folder');

late FakeStorageBridge _bridge;
late StorageBridge _oldBridge;
late AutoBackupService _oldService;
final _notices = <String>[];

Future<void> _pump(WidgetTester t, {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  BackupPrefs.pausedNotifier.value = false;
  t.view.physicalSize = const Size(420, 3600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: BackupScreen(key: UniqueKey(), loadCounts: () async => _counts)));
  await t.pumpAndSettle();
}

Map<String, Object> _working({int n = 10, int k = 5, int since = 0, int? lastMs}) => {
  'auto_backup_enabled': true,
  'auto_backup_folder_uri': _uri,
  'auto_backup_folder_name': 'Documents / mmogo-backups',
  'auto_backup_every_n': n,
  'auto_backup_keep_k': k,
  'auto_backup_since_count': since,
  if (lastMs != null) 'auto_backup_last_at': DateTime.fromMillisecondsSinceEpoch(lastMs).toIso8601String(),
};

Future<void> _tapSwitch(WidgetTester t) async {
  await t.tap(find.byKey(const Key('autoBackupSwitch')));
  await t.pumpAndSettle();
}

/// Switch on, setup sheet, Choose folder, then the cloud dialog is up.
Future<void> _toCloudDialog(WidgetTester t, PickedFolder pick) async {
  _bridge.folderPicks.add(pick);
  await t.tap(find.byKey(const Key('setupChooseFolder')));
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    _bridge = FakeStorageBridge();
    _oldBridge = StorageBridge.instance;
    _oldService = AutoBackupService.instance;
    StorageBridge.instance = _bridge;
    _notices.clear();
    AutoBackupService.instance = AutoBackupService(
      bridge: () => _bridge,
      export: () async => Uint8List.fromList([123, 125]),
      notify: _notices.add,
    );
  });
  tearDown(() {
    StorageBridge.instance = _oldBridge;
    AutoBackupService.instance = _oldService;
    BackupPrefs.pausedNotifier.value = false;
  });

  testWidgets('off: only the switch, explanation, no folder row, no steppers', (t) async {
    await _pump(t);
    expect(find.text('Auto-backup'), findsOneWidget);
    expect(find.text(kAutoBackupOffSubtitle), findsOneWidget);
    expect(find.byKey(const Key('autoBackupFolderRow')), findsNothing);
    expect(find.byKey(const Key('autoEveryNValue')), findsNothing);
    expect(t.widget<Switch>(find.byType(Switch).first).value, isFalse);
  });

  group('setup flow and warnings order', () {
    testWidgets('the unencrypted warning W1 is shown BEFORE the folder picker opens', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      // Sheet is up, W1 is on screen, the picker has not been called.
      expect(find.byKey(const Key('setupWarning')), findsOneWidget);
      expect(find.text(kBackupFileWarning), findsWidgets);
      expect(find.text(kAutoBackupSetupTitle), findsOneWidget);
      expect(find.text(autoBackupSetupIntro(10, 5)), findsOneWidget);
      expect(find.text(kAutoBackupFolderHint), findsWidgets);
      expect(_bridge.calls, isNot(contains('pickFolder')));
      expect(find.text(kCloudSyncNotice), findsNothing);
    });

    testWidgets('the cloud notice W2 comes only AFTER a folder is picked, naming the folder', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      expect(find.text(kCloudSyncNotice), findsNothing);
      await _toCloudDialog(t, _folder);
      expect(_bridge.calls, contains('pickFolder'));
      expect(find.text(kCloudSyncTitle), findsOneWidget);
      expect(find.text(kCloudSyncNotice), findsOneWidget);
      expect(find.text(_folder.name), findsOneWidget);
      // Nothing is stored until the user accepts.
      expect(await BackupPrefs.readFolderUri(), isNull);
    });

    testWidgets('Use this folder: stored, switched on, card shows folder, status and the toast', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      await _toCloudDialog(t, _folder);
      await t.tap(find.byKey(const Key('cloudUseFolder')));
      await t.pumpAndSettle();
      expect(await BackupPrefs.readFolderUri(), _uri);
      expect(await BackupPrefs.readFolderName(), _folder.name);
      expect(await BackupPrefs.readEnabled(), isTrue);
      expect(find.text(autoBackupOnSubtitle(10)), findsOneWidget);
      expect(find.text(_folder.name), findsOneWidget);
      expect(find.text('No auto-backup yet. The first one is made after 10 saved entries.'), findsOneWidget);
      expect(find.text(autoBackupIsOnToast(10)), findsOneWidget);
      expect(find.byKey(const Key('autoBackupNoFolderBanner')), findsNothing);
    });

    testWidgets('the cloud notice is not shown again when the page is reopened with a stored folder', (t) async {
      await _pump(t, prefs: _working());
      expect(find.text(kCloudSyncNotice), findsNothing);
      expect(find.text(kCloudSyncTitle), findsNothing);
      expect(_bridge.calls, isNot(contains('pickFolder')));
      expect(find.text(_folder.name), findsOneWidget);
    });

    testWidgets('Choose another folder at the notice: the declined grant is released, the picker opens again',
        (t) async {
      await _pump(t);
      await _tapSwitch(t);
      await _toCloudDialog(t, _folder);
      _bridge.folderPicks.add(_other);
      await t.tap(find.byKey(const Key('cloudChooseAnother')));
      await t.pumpAndSettle();
      expect(_bridge.calls, contains('releaseGrant:$_uri'));
      expect(_bridge.calls.where((c) => c == 'pickFolder').length, 2);
      expect(find.text(kCloudSyncTitle), findsOneWidget);
      expect(find.text(_other.name), findsOneWidget);
      await t.tap(find.byKey(const Key('cloudUseFolder')));
      await t.pumpAndSettle();
      expect(await BackupPrefs.readFolderUri(), _other.uri);
    });

    testWidgets('Not now: switched on but no folder; no picker, banner with Choose folder', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      await t.tap(find.byKey(const Key('setupNotNow')));
      await t.pumpAndSettle();
      expect(_bridge.calls, isEmpty);
      expect(find.text(kAutoBackupOnNoFolderSubtitle), findsOneWidget);
      expect(find.byKey(const Key('autoBackupNoFolderBanner')), findsOneWidget);
      expect(find.text('Not chosen yet'), findsOneWidget);
      expect(await BackupPrefs.readFolderUri(), isNull);
    });

    testWidgets('picker cancelled: nothing stored, no cloud notice', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      await t.tap(find.byKey(const Key('setupChooseFolder'))); // the fake answers "cancelled" with an empty queue
      await t.pumpAndSettle();
      expect(find.text(kCloudSyncNotice), findsNothing);
      expect(await BackupPrefs.readFolderUri(), isNull);
      expect(find.byKey(const Key('autoBackupNoFolderBanner')), findsOneWidget);
    });

    testWidgets('picker error: a plain message, nothing stored', (t) async {
      await _pump(t);
      await _tapSwitch(t);
      _bridge.nextPickError = const StorageException(StorageErrorCode.io, 'raw detail');
      await t.tap(find.byKey(const Key('setupChooseFolder')));
      await t.pumpAndSettle();
      expect(find.text('Could not open the folder picker. Try again.'), findsOneWidget);
      expect(find.textContaining('raw detail'), findsNothing);
      expect(await BackupPrefs.readFolderUri(), isNull);
    });

    testWidgets('changing the folder from a working card also goes W1, picker, W2, and releases the old grant',
        (t) async {
      await _pump(t, prefs: _working());
      _bridge.folders[_uri] = {};
      await t.tap(find.byKey(const Key('autoBackupFolderRow')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('setupWarning')), findsOneWidget);
      expect(_bridge.calls, isNot(contains('pickFolder')));
      await _toCloudDialog(t, _other);
      await t.tap(find.byKey(const Key('cloudUseFolder')));
      await t.pumpAndSettle();
      expect(await BackupPrefs.readFolderUri(), _other.uri);
      expect(_bridge.calls, contains('releaseGrant:$_uri'));
      expect(await BackupPrefs.readSinceCount(), 0);
    });
  });

  group('working card', () {
    testWidgets('folder, defaults 10 and 5, status with entries left, W1 on the card', (t) async {
      final last = DateTime(2026, 9, 25, 8, 2);
      await _pump(t, prefs: _working(since: 4, lastMs: last.millisecondsSinceEpoch));
      expect(find.text(autoBackupOnSubtitle(10)), findsOneWidget);
      expect(find.text(_folder.name), findsOneWidget);
      expect(find.byKey(const Key('autoEveryNValue')), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Older auto-backup files beyond 5 are deleted'), findsOneWidget);
      expect(
        find.text('Last auto-backup: 25 Sep 2026, 08:02. 6 more saved entries until the next one.'),
        findsOneWidget,
      );
      expect(find.text(kBackupFileWarning), findsNWidgets(2)); // Back up now card and this card
      expect(find.byKey(const Key('autoBackupPausedBanner')), findsNothing);
      expect(find.byKey(const Key('autoBackupFailedBanner')), findsNothing);
    });

    testWidgets('the last-backup line appends "Last auto-backup" after the manual time', (t) async {
      final manual = DateTime(2026, 9, 20, 18, 5);
      final auto = DateTime(2026, 9, 25, 8, 2);
      await _pump(
        t,
        prefs: {
          ..._working(lastMs: auto.millisecondsSinceEpoch),
          'backup_last_manual_at': manual.millisecondsSinceEpoch,
        },
      );
      expect(
        t.widget<Text>(find.byKey(const Key('backupLastLine'))).data,
        'Last backup (manual): 20 Sep 2026, 18:05 · Last auto-backup: 25 Sep 2026, 08:02',
      );
    });

    testWidgets('auto only: the line shows just the auto time; none yet: Never backed up', (t) async {
      await _pump(t, prefs: _working(lastMs: DateTime(2026, 9, 25, 8, 2).millisecondsSinceEpoch));
      expect(t.widget<Text>(find.byKey(const Key('backupLastLine'))).data, 'Last auto-backup: 25 Sep 2026, 08:02');
      await _pump(t, prefs: _working());
      expect(t.widget<Text>(find.byKey(const Key('backupLastLine'))).data, 'Never backed up');
    });

    testWidgets('last attempt failed (not paused): banner, steppers still on', (t) async {
      await _pump(t, prefs: {..._working(), 'auto_backup_fail_count': 1});
      expect(find.byKey(const Key('autoBackupFailedBanner')), findsOneWidget);
      expect(find.text(kAutoBackupFailedBanner), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed, isNotNull);
    });

    testWidgets('turning it off releases the grant, clears the folder keys and collapses the card', (t) async {
      await _pump(t, prefs: _working());
      _bridge.folders[_uri] = {};
      await _tapSwitch(t);
      expect(_bridge.calls, contains('releaseGrant:$_uri'));
      expect(await BackupPrefs.readEnabled(), isFalse);
      expect(await BackupPrefs.readFolderUri(), isNull);
      expect(find.byKey(const Key('autoBackupFolderRow')), findsNothing);
      expect(find.text(kAutoBackupOffSubtitle), findsOneWidget);
    });
  });

  group('N and K steppers', () {
    testWidgets('N_and_K_choices_persist', (t) async {
      await _pump(t, prefs: _working());
      await t.tap(find.byKey(const Key('autoEveryNMore')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('autoEveryNMore')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('autoKeepKLess')));
      await t.pumpAndSettle();
      expect(await BackupPrefs.readEveryN(), 12);
      expect(await BackupPrefs.readKeepK(), 4);
      expect(t.widget<Text>(find.byKey(const Key('autoEveryNValue'))).data, '12');
      expect(t.widget<Text>(find.byKey(const Key('autoKeepKValue'))).data, '4');
      expect(find.text('After every 12 saved entries'), findsOneWidget);
      expect(find.text('Older auto-backup files beyond 4 are deleted'), findsOneWidget);
    });

    testWidgets('N is 1 to 100: minus is off at 1, plus is off at 100; one entry is worded in the singular', (t) async {
      await _pump(t, prefs: _working(n: 1));
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNLess'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed, isNotNull);
      expect(find.text('After every 1 saved entry'), findsOneWidget);
      await _pump(t, prefs: _working(n: 100));
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNLess'))).onPressed, isNotNull);
    });

    testWidgets('K is 2 to 20: minus is off at 2, plus is off at 20', (t) async {
      await _pump(t, prefs: _working(k: 2));
      expect(t.widget<IconButton>(find.byKey(const Key('autoKeepKLess'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const Key('autoKeepKMore'))).onPressed, isNotNull);
      await _pump(t, prefs: _working(k: 20));
      expect(t.widget<IconButton>(find.byKey(const Key('autoKeepKMore'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const Key('autoKeepKLess'))).onPressed, isNotNull);
    });

    testWidgets('a stored value outside the range is clamped on read (N 500 shows 100, K 1 shows 2)', (t) async {
      await _pump(t, prefs: _working(n: 500, k: 1));
      expect(t.widget<Text>(find.byKey(const Key('autoEveryNValue'))).data, '100');
      expect(t.widget<Text>(find.byKey(const Key('autoKeepKValue'))).data, '2');
    });

    testWidgets('walking N from 10 up to the cap and K down to the floor stops at the bounds', (t) async {
      await _pump(t, prefs: _working(n: 98, k: 3));
      for (var i = 0; i < 4; i++) {
        final more = t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed;
        if (more != null) {
          await t.tap(find.byKey(const Key('autoEveryNMore')));
          await t.pumpAndSettle();
        }
      }
      for (var i = 0; i < 3; i++) {
        final less = t.widget<IconButton>(find.byKey(const Key('autoKeepKLess'))).onPressed;
        if (less != null) {
          await t.tap(find.byKey(const Key('autoKeepKLess')));
          await t.pumpAndSettle();
        }
      }
      expect(await BackupPrefs.readEveryN(), 100);
      expect(await BackupPrefs.readKeepK(), 2);
    });
  });

  group('B21b: hold to repeat on the real card', () {
    testWidgets('holding N plus keeps adding, stops at 100 and saves it; a plain tap is still +1', (t) async {
      await _pump(t, prefs: _working(n: 90));
      await t.tap(find.byKey(const Key('autoEveryNMore')));
      await t.pumpAndSettle();
      expect(await BackupPrefs.readEveryN(), 91);
      final g = await t.startGesture(t.getCenter(find.byKey(const Key('autoEveryNMore'))));
      for (var i = 0; i < 400; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      await g.up();
      await t.pumpAndSettle();
      expect(await BackupPrefs.readEveryN(), 100);
      expect(t.widget<Text>(find.byKey(const Key('autoEveryNValue'))).data, '100');
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed, isNull);
    });

    testWidgets('holding K minus stops at 2', (t) async {
      await _pump(t, prefs: _working(k: 6));
      final g = await t.startGesture(t.getCenter(find.byKey(const Key('autoKeepKLess'))));
      for (var i = 0; i < 150; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      await g.up();
      await t.pumpAndSettle();
      expect(await BackupPrefs.readKeepK(), 2);
      expect(t.widget<Text>(find.byKey(const Key('autoKeepKValue'))).data, '2');
    });
  });

  group('paused', () {
    Map<String, Object> paused() => {..._working(since: 3), 'auto_backup_paused': true};

    testWidgets('paused_row_shows_choose_folder_again: banner, button, "(not available)", steppers off', (t) async {
      await _pump(t, prefs: paused());
      expect(find.byKey(const Key('autoBackupPausedBanner')), findsOneWidget);
      expect(find.textContaining(kAutoBackupPausedBannerTitle), findsOneWidget);
      expect(find.byKey(const Key('autoBackupChooseFolder')), findsOneWidget);
      expect(find.text('On, but paused'), findsOneWidget);
      expect(find.text('${_folder.name} (not available)'), findsOneWidget);
      expect(find.text(kAutoBackupPausedStatus), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('autoEveryNMore'))).onPressed, isNull);
      expect(t.widget<IconButton>(find.byKey(const Key('autoKeepKLess'))).onPressed, isNull);
      expect(find.byKey(const Key('autoBackupFailedBanner')), findsNothing);
    });

    testWidgets('paused hides the last auto-backup from the last-backup line', (t) async {
      await _pump(t, prefs: {...paused(), 'auto_backup_last_at': DateTime(2026, 9, 25, 8, 2).toIso8601String()});
      expect(t.widget<Text>(find.byKey(const Key('backupLastLine'))).data, 'Never backed up');
    });

    testWidgets('Choose folder again: W1 sheet, picker, W2, then resumed (banner gone, counter reset)', (t) async {
      await _pump(t, prefs: paused());
      await t.tap(find.byKey(const Key('autoBackupChooseFolder')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('setupWarning')), findsOneWidget);
      expect(_bridge.calls, isNot(contains('pickFolder')));
      await _toCloudDialog(t, _folder);
      await t.tap(find.byKey(const Key('cloudUseFolder')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('autoBackupPausedBanner')), findsNothing);
      expect(await BackupPrefs.readPaused(), isFalse);
      expect(await BackupPrefs.readSinceCount(), 0);
      expect(find.text(autoBackupOnSubtitle(10)), findsOneWidget);
    });

    testWidgets('live: the service pauses itself while the page is open and the banner appears', (t) async {
      await _pump(t, prefs: _working());
      _bridge.folders[_uri] = {};
      await BackupPrefs.writeEveryN(1);
      _bridge.revokeGrant(_uri);
      expect(find.byKey(const Key('autoBackupPausedBanner')), findsNothing);
      await t.runAsync(() async {
        await AutoBackupService.instance.onEntrySaved();
        await Future<void>.delayed(const Duration(milliseconds: 100)); // let the page re-read its prefs
      });
      await t.pumpAndSettle();
      expect(find.byKey(const Key('autoBackupPausedBanner')), findsOneWidget);
      expect(_notices, [AutoBackupService.pausedMessage]);
    });
  });
}
