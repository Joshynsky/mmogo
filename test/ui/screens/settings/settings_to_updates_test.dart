// F9 (0.1.2): the S2 / S11 Updates behaviours, reached the way a user now
// reaches them: Settings > About > Updates (not the bell). Same fakes as
// updates_screen_test.dart; no network, no browser.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/prefs/update_prefs.dart';
import 'package:mmogo/data/updates/release_info.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/platform/storage_bridge.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/screens/settings/about_section.dart';
import 'package:mmogo/ui/screens/updates/updates_screen.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/updates/fake_update_check_client.dart';
import '../../../support/fake_storage_bridge.dart';

final _at = DateTime(2026, 10, 2, 9, 0);

class _Rig {
  _Rig(this.result);
  final ReleaseInfo result;
  late final UpdatesInbox inbox = UpdatesInbox(installedVersion: () => '0.1.1');
  late final FakeUpdateCheckClient client = FakeUpdateCheckClient(result: result);
  late final UpdateCheckService service = UpdateCheckService(
    clientFactory: () => client,
    inbox: inbox,
    installedVersion: () => '0.1.1',
  );
}

Future<_Rig> _fromSettings(
  WidgetTester tester, {
  ReleaseInfo result = const ReleaseInfo(tag: 'v0.1.1', notes: ''),
  List<Map<String, Object?>> stored = const [],
}) async {
  SharedPreferences.setMockInitialValues({
    if (stored.isNotEmpty) 'updates_inbox_v1': jsonEncode(stored),
  });
  WhatsNewProcess.resetForTest();
  StorageBridge.instance = FakeStorageBridge();
  final rig = _Rig(result);
  await rig.inbox.load();
  tester.view.physicalSize = const Size(400, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      routes: {
        Routes.updates: (_) => UpdatesScreen(
          inbox: rig.inbox,
          service: rig.service,
          readSeenVersion: () async => null,
          writeSeenVersion: (_) async {},
          installedVersionName: '0.1.1',
        ),
      },
      home: Scaffold(body: AboutSection(palette: AppPalette.light, inbox: rig.inbox)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Updates'));
  await tester.pumpAndSettle();
  return rig;
}

void main() {
  testWidgets('Settings > Updates shows the check, the weekly switch and What\'s new', (tester) async {
    await _fromSettings(tester);
    expect(find.text(kUpdatesCheckNowLabel), findsOneWidget);
    expect(find.text(kUpdatesSwitchTitle), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.byKey(const Key('whatsNewEntry')), findsOneWidget);
    expect(find.text(kWhatsNewPagerTitle), findsOneWidget);
  });

  testWidgets('check now from Settings: a newer release is found and listed (history)', (tester) async {
    final rig = await _fromSettings(tester, result: const ReleaseInfo(tag: 'v0.2.0', notes: 'Shiny'));
    await tester.tap(find.byKey(const Key('checkNowButton')));
    await tester.pumpAndSettle();
    expect(rig.client.calls, 1);
    expect(find.text(kCheckNowNewVersion), findsOneWidget);
    expect(find.text('mmogo 0.2.0 is out'), findsOneWidget);
    expect(await UpdatePrefs.readLastCheckAt(), isNotNull);
  });

  testWidgets('check now from Settings: nothing newer says you have the latest', (tester) async {
    final rig = await _fromSettings(tester);
    await tester.tap(find.byKey(const Key('checkNowButton')));
    await tester.pumpAndSettle();
    expect(rig.client.calls, 1);
    expect(find.text(kCheckNowUpToDate), findsOneWidget);
  });

  testWidgets('weekly switch from Settings persists and shows on the Settings row after Back', (tester) async {
    await _fromSettings(tester);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(await UpdatePrefs.readEnabled(), isFalse);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Checking is off'), findsOneWidget);
  });

  testWidgets('history from Settings: earlier notices are listed and marked read on leaving', (tester) async {
    final rig = await _fromSettings(
      tester,
      stored: [
        {'tag': 'v0.1.3', 'notes': 'Notes.', 'receivedAt': _at.millisecondsSinceEpoch, 'read': false},
        {'tag': 'v0.1.2', 'notes': 'Old.', 'receivedAt': _at.millisecondsSinceEpoch - 1000, 'read': true},
      ],
    );
    expect(find.byKey(const Key('notice-v0.1.3')), findsOneWidget);
    expect(find.byKey(const Key('notice-v0.1.2')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(rig.inbox.unreadCount.value, 0);
  });

  testWidgets('What\'s new from Settings > Updates opens the pager', (tester) async {
    await _fromSettings(tester);
    await tester.tap(find.byKey(const Key('whatsNewEntryButton')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('whatsNewPager')), findsOneWidget);
  });
}
