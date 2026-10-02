// B27 / B28 (as redefined) / B49: the Updates page. Every state: empty, welcome,
// unread, read, long notes, plain text only, See what's new, Check for updates
// now (new version, up to date, off, failed), the switch, Last checked, and
// marking read on leaving. Fake client and fake storage bridge: nothing opens
// a socket or a browser.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_constants.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_client.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/updates/fake_update_check_client.dart';
import '../../../support/fake_storage_bridge.dart';

final _received = DateTime(2026, 10, 2, 9, 0);

Map<String, Object?> _notice(String tag, String notes, {bool read = false, bool welcome = false}) => {
  'tag': tag,
  'notes': notes,
  'receivedAt': _received.millisecondsSinceEpoch,
  'read': read,
  if (welcome) 'welcome': true,
};

class _Rig {
  _Rig({this.result, this.error});
  final ReleaseInfo? result;
  final Object? error;
  late final UpdatesInbox inbox = UpdatesInbox(installedVersion: () => '0.1.1');
  late final FakeUpdateCheckClient client = FakeUpdateCheckClient(result: result, error: error);
  late final UpdateCheckService service = UpdateCheckService(
    clientFactory: () => client,
    inbox: inbox,
    installedVersion: () => '0.1.1',
  );
}

Future<_Rig> _pump(
  WidgetTester tester, {
  List<Map<String, Object?>> stored = const [],
  Map<String, Object> prefs = const {},
  ReleaseInfo? result,
  Object? error,
}) async {
  SharedPreferences.setMockInitialValues({
    ...prefs,
    if (stored.isNotEmpty) 'updates_inbox_v1': jsonEncode(stored),
  });
  final rig = _Rig(result: result, error: error);
  await rig.inbox.load();
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: UpdatesScreen(inbox: rig.inbox, service: rig.service)));
  await tester.pumpAndSettle();
  return rig;
}

void main() {
  late FakeStorageBridge bridge;
  setUp(() {
    bridge = FakeStorageBridge();
    StorageBridge.instance = bridge;
  });

  group('empty state', () {
    testWidgets('switch on: "No updates yet." and the cadence', (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('updatesEmpty')), findsOneWidget);
      expect(find.text(kUpdatesEmptyTitle), findsOneWidget);
      expect(find.text(kUpdateCheckCadence), findsOneWidget);
      expect(find.byKey(const Key('noticeNewPill')), findsNothing);
    });

    testWidgets('switch off: says checks are off and how to turn them on', (tester) async {
      await _pump(tester, prefs: {'update_check_enabled': false});
      expect(find.text(kUpdatesEmptyOff), findsOneWidget);
    });
  });

  group('the controls sit at the top of the page', () {
    testWidgets('switch, Check for updates now and Last checked are all there', (tester) async {
      await _pump(tester, prefs: {'update_last_check_at': _received.millisecondsSinceEpoch});
      expect(find.text(kUpdatesSwitchTitle), findsOneWidget);
      expect(find.text(kUpdatesCheckNowLabel), findsOneWidget);
      expect(find.textContaining('Last checked 2 Oct 2026.'), findsOneWidget);
      expect(find.textContaining('GitHub sees your IP address'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('never checked: "Not checked yet."', (tester) async {
      await _pump(tester);
      expect(find.textContaining('Not checked yet.'), findsOneWidget);
    });

    testWidgets('switch toggling persists, shows "Off: mmogo makes no request." and back on', (tester) async {
      await _pump(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await UpdatePrefs.readEnabled(), isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.textContaining('Off: mmogo makes no request.'), findsOneWidget);
      expect(find.text(kUpdatesEmptyOff), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(await UpdatePrefs.readEnabled(), isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('a saved "off" is shown as off when the page opens', (tester) async {
      await _pump(tester, prefs: {'update_check_enabled': false});
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });

  group('notices', () {
    testWidgets('welcome: its title and wording, New pill, no "See what\'s new"', (tester) async {
      await _pump(tester, stored: [_notice('Welcome', '', welcome: true)]);
      expect(find.text(kWelcomeNoticeTitle), findsOneWidget);
      expect(find.text('Hello, and welcome to mmogo 0.1.1'), findsOneWidget);
      expect(find.byKey(const Key('noticeNewPill')), findsOneWidget);
      expect(find.byKey(const Key('noticeSeeWhatsNew')), findsNothing);
      expect(find.text('Welcome'), findsOneWidget, reason: 'the tag chip');
      // The notes are the shared constant, in full (it is short enough to read at a glance).
      final notes = tester.widget<Text>(find.byKey(const Key('noticeNotes')));
      expect(notes.data, kWelcomeNoticeNotes);
      expect(kWelcomeNoticeNotes, contains('update checks are switched on'));
      expect(kWelcomeNoticeNotes, contains(kNetworkSentence));
      expect(kWelcomeNoticeNotes, contains('at most once a week'));
      expect(kWelcomeNoticeNotes, contains('switch update checks off at the top of this page'));
    });

    testWidgets('backup paused: title, notes, Backup pill, Open button that goes to Backup and restore',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'updates_inbox_v1': jsonEncode([
          {
            'tag': 'BackupPaused',
            'notes': '',
            'receivedAt': _received.millisecondsSinceEpoch,
            'read': false,
            'backup_paused': true,
          },
        ]),
      });
      final rig = _Rig();
      await rig.inbox.load();
      tester.view.physicalSize = const Size(400, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: UpdatesScreen(inbox: rig.inbox, service: rig.service),
        routes: {Routes.backup: (_) => const Scaffold(body: Text('backup page'))},
      ));
      await tester.pumpAndSettle();

      expect(find.text(kBackupPausedNoticeTitle), findsOneWidget);
      expect(find.text('Auto-backup is paused'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('noticeNotes'))).data, kBackupPausedNoticeNotes);
      expect(find.text('Backup'), findsOneWidget, reason: 'the tag pill');
      expect(find.text('BackupPaused'), findsNothing);
      expect(find.byKey(const Key('noticeNewPill')), findsOneWidget);
      expect(find.byKey(const Key('noticeSeeWhatsNew')), findsNothing);
      expect(find.text('Open Backup and restore'), findsOneWidget);

      await tester.tap(find.byKey(const Key('noticeOpenBackup')));
      await tester.pumpAndSettle();
      expect(find.text('backup page'), findsOneWidget);
    });

    testWidgets('unread release: tag, date, New pill, title, notes, See what\'s new', (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'Faster Analytics')]);
      expect(find.text('v0.2.0'), findsOneWidget);
      expect(find.text('Received 2 Oct 2026'), findsOneWidget);
      expect(find.byKey(const Key('noticeNewPill')), findsOneWidget);
      expect(find.text('mmogo 0.2.0 is out'), findsOneWidget);
      expect(find.text('Faster Analytics'), findsOneWidget);
      expect(find.byKey(const Key('noticeSeeWhatsNew')), findsOneWidget);
      expect(find.textContaining('shortened to 30 lines'), findsOneWidget, reason: 'the footnote');
    });

    testWidgets('read release: no New pill', (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'Faster Analytics', read: true)]);
      expect(find.byKey(const Key('noticeNewPill')), findsNothing);
      expect(find.text('mmogo 0.2.0 is out'), findsOneWidget);
    });

    testWidgets('newest first: two notices in order', (tester) async {
      await _pump(tester, stored: [
        {..._notice('v0.2.0', 'a'), 'receivedAt': 1000},
        {..._notice('v0.3.0', 'b'), 'receivedAt': 2000},
      ]);
      final first = tester.getTopLeft(find.text('mmogo 0.3.0 is out')).dy;
      final second = tester.getTopLeft(find.text('mmogo 0.2.0 is out')).dy;
      expect(first, lessThan(second));
    });

    testWidgets("See what's new opens the mmogo page constant through the storage bridge", (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'x https://evil.example/apk.apk')]);
      await tester.tap(find.byKey(const Key('noticeSeeWhatsNew')));
      await tester.pumpAndSettle();
      expect(bridge.openedUrls, [AppConstants.siteUrl]);
      expect(bridge.calls.where((c) => c.startsWith('openUrl')), ['openUrl:https://joshynsky.github.io/mmogo/']);
    });

    testWidgets("a failed open says so in plain words", (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'x')]);
      StorageBridge.instance = _RefusingBridge();
      await tester.tap(find.byKey(const Key('noticeSeeWhatsNew')));
      await tester.pump();
      await tester.pump();
      expect(find.text(kUpdatesCouldNotOpen), findsOneWidget);
    });

    testWidgets('notes are plain Text only: no SelectableText, no tappable span; a URL stays characters',
        (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'More: https://joshynsky.github.io/mmogo/ now')]);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('https://joshynsky.github.io/mmogo/ now'), findsOneWidget);
      var recognizers = 0;
      for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
        rt.text.visitChildren((span) {
          if (span is TextSpan && span.recognizer is TapGestureRecognizer) recognizers++;
          return true;
        });
      }
      expect(recognizers, 0);
    });

    testWidgets('the light Markdown strip: leading #, ** and backticks are not shown', (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', '## What is new\n**Faster** `sync`\n#123 stays')]);
      final text = tester.widget<Text>(find.byKey(const Key('noticeNotes'))).data!;
      expect(text, 'What is new\nFaster sync\n#123 stays');
    });

    testWidgets('short notes: no "Show all notes"', (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'One line')]);
      expect(find.byKey(const Key('noticeShowAll')), findsNothing);
    });

    testWidgets('long notes (44 lines): capped at 30, collapsed to 6, "Show all notes" opens and closes',
        (tester) async {
      final notes = List.generate(44, (i) => 'Small fix number ${i + 1}').join('\n');
      await _pump(tester, stored: [_notice('v0.2.0', notes)]);
      final shown = tester.widget<Text>(find.byKey(const Key('noticeNotes')));
      expect(shown.data!.split('\n'), hasLength(30), reason: 'capped at 30 lines');
      expect(shown.data!.endsWith('…'), isTrue);
      expect(shown.maxLines, 6);
      expect(find.text(kUpdatesShowAllNotes), findsOneWidget);

      await tester.tap(find.byKey(const Key('noticeShowAll')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('noticeNotes'))).maxLines, 30);
      expect(find.text(kUpdatesShowFewerNotes), findsOneWidget);

      await tester.tap(find.byKey(const Key('noticeShowAll')));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('noticeNotes'))).maxLines, 6);
    });

    testWidgets('notes over 1,500 characters are cut with an ellipsis (re-sanitised at render)', (tester) async {
      await _pump(tester, stored: [_notice('v0.2.0', 'x' * 5000)]);
      final text = tester.widget<Text>(find.byKey(const Key('noticeNotes'))).data!;
      expect(text.runes.length, lessThanOrEqualTo(1500));
      expect(text.endsWith('…'), isTrue);
    });
  });

  group('Check for updates now', () {
    testWidgets('a newer release: says so and shows the notice, and Last checked updates', (tester) async {
      final rig = await _pump(tester, result: const ReleaseInfo(tag: 'v0.2.0', notes: 'Shiny'));
      expect(find.byKey(const Key('noticeSeeWhatsNew')), findsNothing);
      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pumpAndSettle();
      expect(rig.client.calls, 1);
      expect(find.text(kCheckNowNewVersion), findsOneWidget);
      expect(find.text('mmogo 0.2.0 is out'), findsOneWidget);
      expect(find.textContaining('Last checked '), findsOneWidget);
      expect(await UpdatePrefs.readLastCheckAt(), isNotNull);
    });

    testWidgets('nothing newer: "You have the latest version."', (tester) async {
      final rig = await _pump(tester, result: const ReleaseInfo(tag: 'v0.1.1', notes: ''));
      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pumpAndSettle();
      expect(rig.client.calls, 1);
      expect(find.text(kCheckNowUpToDate), findsOneWidget);
      expect(find.byKey(const Key('updatesEmpty')), findsOneWidget);
    });

    testWidgets('switch off: says it is off and makes no request', (tester) async {
      final rig = await _pump(tester, prefs: {'update_check_enabled': false}, result: const ReleaseInfo(tag: 'v0.2.0', notes: ''));
      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pumpAndSettle();
      expect(find.text(kCheckNowOff), findsOneWidget);
      expect(rig.client.calls, 0);
    });

    testWidgets('turning the switch off, then Check now: off, no request', (tester) async {
      final rig = await _pump(tester, result: const ReleaseInfo(tag: 'v0.2.0', notes: ''));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pumpAndSettle();
      expect(find.text(kCheckNowOff), findsOneWidget);
      expect(rig.client.calls, 0);
    });

    testWidgets('failed (offline): plain words, no timestamp, no error dialog', (tester) async {
      final rig = await _pump(tester, error: StateError('offline'));
      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pumpAndSettle();
      expect(rig.client.calls, 1);
      expect(find.text(kCheckNowFailed), findsOneWidget);
      expect(await UpdatePrefs.readLastCheckAt(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Not checked yet.'), findsOneWidget);
    });

    testWidgets('while a check runs the button reads "Checking..." and is disabled', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final inbox = UpdatesInbox(installedVersion: () => '0.1.1');
      await inbox.load();
      final gate = Completer<ReleaseInfo>();
      final client = _GatedClient(gate.future);
      final service = UpdateCheckService(
        clientFactory: () => client,
        inbox: inbox,
        installedVersion: () => '0.1.1',
      );
      await tester.pumpWidget(MaterialApp(home: UpdatesScreen(inbox: inbox, service: service)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('checkNowButton')));
      await tester.pump();
      await tester.pump();
      expect(find.text(kUpdatesCheckingLabel), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('checkNowButton'))).onPressed, isNull);

      gate.complete(const ReleaseInfo(tag: 'v0.1.1', notes: ''));
      await tester.pumpAndSettle();
      expect(find.text(kUpdatesCheckNowLabel), findsOneWidget);
      expect(client.calls, 1);
    });
  });

  group('marking read', () {
    testWidgets('opening the page marks nothing; leaving it marks every notice read', (tester) async {
      SharedPreferences.setMockInitialValues({
        'updates_inbox_v1': jsonEncode([_notice('v0.2.0', 'x'), _notice('Welcome', '', welcome: true)]),
      });
      final rig = _Rig();
      await rig.inbox.load();
      expect(rig.inbox.unreadCount.value, 2);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => UpdatesScreen(inbox: rig.inbox, service: rig.service)),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(rig.inbox.unreadCount.value, 2, reason: 'still unread while the page is open');
      expect(find.byKey(const Key('noticeNewPill')), findsNWidgets(2));

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(rig.inbox.unreadCount.value, 0);
      expect(rig.inbox.notices.every((n) => n.read), isTrue);

      // And it is stored: a fresh inbox reads them as read.
      final again = UpdatesInbox(installedVersion: () => '0.1.1');
      await again.load();
      expect(again.unreadCount.value, 0);
    });
  });
}

class _GatedClient implements UpdateCheckSource {
  _GatedClient(this._answer);
  final Future<ReleaseInfo> _answer;
  int calls = 0;

  @override
  Future<ReleaseInfo> fetchLatest() {
    calls++;
    return _answer;
  }
}

class _RefusingBridge extends FakeStorageBridge {
  @override
  Future<bool> openUrl(String url) async => false;
}
