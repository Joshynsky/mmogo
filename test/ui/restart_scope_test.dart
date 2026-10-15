// 0.1.2 S9b-1: the soft restart after "Reset app" (RestartScope +
// resetInMemoryState). Widget tests use FAKES only: mock prefs, no database,
// no real files (Welcome and Onboarding touch prefs only). Nothing here calls
// ResetResume, resetApp or AppDatabase.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/data/backup/auto_backup_service.dart';
import 'package:mmogo/data/prefs/app_prefs.dart';
import 'package:mmogo/data/prefs/backup_prefs.dart';
import 'package:mmogo/data/updates/update_check_service.dart';
import 'package:mmogo/data/updates/updates_inbox.dart';
import 'package:mmogo/main.dart';
import 'package:mmogo/ui/restart_scope.dart';
import 'package:mmogo/ui/screens/onboarding_screen.dart';
import 'package:mmogo/ui/screens/privacy/privacy_screen.dart';
import 'package:mmogo/ui/screens/welcome_screen.dart';
import 'package:mmogo/ui/shell/primary_scaffold.dart';
import 'package:mmogo/ui/shell/primary_shell.dart';
import 'package:mmogo/ui/shell/routes.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/updates/fake_update_check_client.dart';

void _useBuiltFrameAsPresented() {
  welcomeFirstFramePresented = waitForFrameBuilt;
  addTearDown(() => welcomeFirstFramePresented = waitForFirstFramePresented);
}

Notice _notice() => Notice(tag: 'v9.9.9', notes: 'Invented', receivedAt: DateTime(2026, 10, 1));

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    BackupPrefs.pausedNotifier.value = false;
  });

  testWidgets('resetInMemoryState returns every listed singleton to its fresh state', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final originalAuto = AutoBackupService.instance;
    final originalUpdates = UpdateCheckService.instance;
    addTearDown(() {
      AutoBackupService.instance = originalAuto;
      UpdateCheckService.instance = originalUpdates;
    });

    // A live shell.
    await tester.pumpWidget(MaterialApp(
      home: PrimaryShell(pages: {
        0: const PrimaryScaffold(title: 'Home', activeIndex: 0, body: Text('H')),
        1: const PrimaryScaffold(title: 'Analytics', activeIndex: 1, body: Text('A')),
        3: const PrimaryScaffold(title: 'Paid to', activeIndex: 3, body: Text('P')),
        4: const PrimaryScaffold(title: 'Profile', activeIndex: 4, body: Text('Q')),
      }),
    ));
    await tester.pump();
    expect(PrimaryShell.active, isNotNull);

    // Dirty everything.
    final controller = AppPaletteController('indigo', 'dark');
    BackupPrefs.pausedNotifier.value = true;
    final rev = AppPrefs.userDisplayNameRevision.value;
    final auto = AutoBackupService.instance = AutoBackupService(notify: (_) {});
    await auto.quiesce();
    expect(auto.isBlocked, isTrue);
    final fake = FakeUpdateCheckClient(error: StateError('offline'));
    final service = UpdateCheckService.instance = UpdateCheckService(clientFactory: () => fake);
    await tester.runAsync(() async {
      await UpdatesInbox.instance.add(_notice());
      expect(UpdatesInbox.instance.notices, hasLength(1));
      expect(UpdatesInbox.instance.unreadCount.value, 1);
      await service.maybeCheck(now: DateTime(2026, 10, 2));
      await service.maybeCheck(now: DateTime(2026, 10, 2));
      expect(fake.calls, 1, reason: 'once per launch');

      SharedPreferences.setMockInitialValues({}); // the reset wiped the prefs
      await resetInMemoryState(palette: controller);

      expect(controller.value, 'ocean');
      expect(controller.appearance, 'system');
      expect(UpdatesInbox.instance.notices, isEmpty);
      expect(UpdatesInbox.instance.unreadCount.value, 0);
      expect(UpdatesInbox.instance.hadStoredValue, isFalse);
      expect(BackupPrefs.pausedNotifier.value, isFalse);
      expect(AppPrefs.userDisplayNameRevision.value, rev + 1);
      expect(auto.isBlocked, isFalse);
      expect(PrimaryShell.active, isNull);
      // A12: the update check can run again after the restart.
      await service.maybeCheck(now: DateTime(2026, 10, 2));
      expect(fake.calls, 2);
      // The inbox loads again from the (wiped) storage, not from the cache.
      await UpdatesInbox.instance.ensureLoaded();
      expect(UpdatesInbox.instance.notices, isEmpty);
    });
  });

  testWidgets('the soft restart rebuilds the app on Welcome with no stale route, no duplicate GlobalKey, fresh look', (tester) async {
    _useBuiltFrameAsPresented();
    SharedPreferences.setMockInitialValues({
      'palette_id': 'leaf',
      'appearance_mode': 'dark',
      'user_display_name': 'Invented User',
    });
    final controller = AppPaletteController('leaf', 'dark');
    await tester.pumpWidget(RestartScope(
      controller: controller,
      builder: (c) => MpesaTrackerApp(controller: c),
    ));
    await tester.pump();
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await tester.pump(welcomeDuration);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OnboardingScreen), findsOneWidget);
    final navigator = Navigator.of(tester.element(find.byType(OnboardingScreen)));
    navigator.pushNamed(Routes.privacy);
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyScreen), findsOneWidget);
    final first = tester.state<NavigatorState>(find.byType(Navigator).first);

    // The reset wiped the prefs; now the soft restart.
    SharedPreferences.setMockInitialValues({});
    BackupPrefs.pausedNotifier.value = true;
    await tester.runAsync(() async {
      expect(await RestartScope.restart(tester.element(find.byType(PrivacyScreen))), isTrue);
    });
    await tester.pump();
    expect(tester.takeException(), isNull, reason: 'no Duplicate GlobalKey (appMessengerKey) on the swap');

    // Back to Welcome, a NEW navigator, and the look is a fresh install's.
    expect(find.byType(PrivacyScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(tester.state<NavigatorState>(find.byType(Navigator).first), isNot(same(first)));
    expect(controller.value, 'ocean');
    expect(controller.appearance, 'system');
    expect(BackupPrefs.pausedNotifier.value, isFalse);

    await tester.pump(welcomeDuration);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(OnboardingScreen), findsOneWidget, reason: 'Welcome -> Onboarding, as on a first launch');
    expect(tester.takeException(), isNull);
    expect(await AppPrefs.readUserDisplayName(), isNull);
  });

  testWidgets('RestartScope.restart returns false when there is no scope', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(await RestartScope.restart(ctx), isFalse);
  });
}
