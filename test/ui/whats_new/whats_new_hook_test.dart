// 0.1.2 S11a (A1, A3, A7): Home's What's-new hook after the pager replaced the
// 0.1.1 modal. Seen / onboarding reads, the writer and the start-up notice
// flag are all injected; the Settings and Backup routes are stubs. No real
// prefs, database or network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/whats_new_copy.dart';
import 'package:mmogo/ui/copy/whats_new_pager_copy.dart';
import 'package:mmogo/ui/whats_new/whats_new_hook.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _pager = Key('whatsNewPager');

class _Rig {
  _Rig({this.seen, this.onboarded = true, this.noticeShown = false, this.installed = '0.1.2', this.write});
  final String? seen;
  final bool onboarded;
  final bool noticeShown;
  final String installed;
  Future<void> Function(String)? write;
  final written = <String>[];
  final opened = <String>[];
  int hookRuns = 0;
}

Future<_Rig> _pump(
  WidgetTester tester, {
  String? seen,
  bool onboarded = true,
  bool noticeShown = false,
  String installed = '0.1.2',
  Future<void> Function(String)? write,
  bool reset = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  if (reset) WhatsNewProcess.resetForTest();
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final rig = _Rig(seen: seen, onboarded: onboarded, noticeShown: noticeShown, installed: installed, write: write);
  await tester.pumpWidget(_app(rig));
  await tester.pumpAndSettle();
  return rig;
}

Widget _app(_Rig rig, {String home = 'HOME'}) => MaterialApp(
  routes: {
    '/settings': (_) => Scaffold(appBar: AppBar(title: const Text('SETTINGS STUB'))),
    '/backup': (_) => Scaffold(appBar: AppBar(title: const Text('BACKUP STUB'))),
  },
  home: Builder(
    builder: (context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        rig.hookRuns++;
        maybeShowWhatsNew(
          context,
          installedVersionName: rig.installed,
          readSeenVersion: () async => rig.seen,
          readOnboardingComplete: () async => rig.onboarded,
          writeSeenVersion: rig.write ?? (v) async => rig.written.add(v),
          startupNoticeShown: () => rig.noticeShown,
          openSettings: () {
            rig.opened.add('settings');
            Navigator.of(context).pushNamed('/settings');
          },
          openBackup: () {
            rig.opened.add('backup');
            Navigator.of(context).pushNamed('/backup');
          },
        );
      });
      return Scaffold(body: Text(home));
    },
  ),
);

Future<void> _toLastCard(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.tap(find.byKey(const Key('whatsNewNext')));
    await tester.pumpAndSettle();
  }
}

void main() {
  group('who sees the pop-up', () {
    testWidgets('an upgrade (older version stored, onboarding done) sees the pager on card 1', (tester) async {
      await _pump(tester, seen: '0.1.1');
      expect(find.byKey(_pager), findsOneWidget);
      expect(find.text(kWhatsNewPagerTitle), findsOneWidget);
      expect(find.text(kWhatsNewCard1Title), findsOneWidget);
    });

    testWidgets('an upgrade from 0.1.0 (nothing stored, onboarding done) sees it', (tester) async {
      await _pump(tester, seen: null);
      expect(find.byKey(_pager), findsOneWidget);
    });

    testWidgets('a fresh install (nothing stored, onboarding not done) gets no pop-up', (tester) async {
      await _pump(tester, seen: null, onboarded: false);
      expect(find.byKey(_pager), findsNothing);
    });

    testWidgets('a version already seen is not shown again', (tester) async {
      await _pump(tester, seen: '0.1.2');
      expect(find.byKey(_pager), findsNothing);
    });

    testWidgets('the installed 0.1.1 has no content any more: the old modal text is retired', (tester) async {
      await _pump(tester, seen: '0.1.0', installed: '0.1.1');
      expect(find.byKey(_pager), findsNothing);
      expect(find.byKey(const Key('whatsNewDialog')), findsNothing);
    });

    testWidgets('no pager on top of the start-up notice; it is not marked seen', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1', noticeShown: true);
      expect(find.byKey(_pager), findsNothing);
      expect(rig.written, isEmpty);
      expect(WhatsNewProcess.autoShown, isFalse);
    });

    testWidgets('Home starting twice in one process shows no second pager', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await tester.binding.handlePopRoute(); // first card Back: closes, unseen
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      // A restart scope rebuilds Home: the hook runs again.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_app(rig, home: 'HOME AGAIN'));
      await tester.pumpAndSettle();
      expect(rig.hookRuns, 2);
      expect(find.byKey(_pager), findsNothing);
      expect(rig.written, isEmpty);
    });
  });

  group('closing', () {
    testWidgets('Got it writes the installed version once and returns to Home', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await _toLastCard(tester);
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
      expect(rig.written, ['0.1.2']);
      expect(WhatsNewProcess.pillCleared, isTrue);
    });

    testWidgets('Got it does not wait for the write: a write that never finishes still closes', (tester) async {
      final never = Completer<void>();
      await _pump(tester, seen: '0.1.1', write: (_) => never.future);
      await _toLastCard(tester);
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      // The 2 s timeout then drops it silently.
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a write that throws is silent and leaves it unseen', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1', write: (_) async => throw StateError('disk full'));
      await _toLastCard(tester);
      await tester.tap(find.byKey(const Key('whatsNewGotIt')));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(tester.takeException(), isNull);
      expect(rig.written, isEmpty);
    });

    testWidgets('the first-card Back closes WITHOUT marking it seen', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsNothing);
      expect(rig.written, isEmpty);
      expect(WhatsNewProcess.pillCleared, isFalse);
    });

    testWidgets('an outside tap does nothing', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(rig.written, isEmpty);
    });

    testWidgets('the two route buttons open their routes and mark nothing seen', (tester) async {
      final rig = await _pump(tester, seen: '0.1.1');
      await tester.tap(find.byKey(const Key('whatsNewNext')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
      await tester.pumpAndSettle();
      expect(rig.opened, ['settings']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(rig.written, isEmpty);
      await tester.tap(find.byKey(const Key('whatsNewNext')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewNext')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('whatsNewOpenBackup')));
      await tester.pumpAndSettle();
      expect(rig.opened, ['settings', 'backup']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(_pager), findsOneWidget);
      expect(rig.written, isEmpty);
    });
  });

  test('the retired 0.1.1 texts are gone from the shared copy', () {
    expect(kWhatsNewGotIt, 'Got it');
    expect(kWhatsNewOpenBackup, 'Open Backup and restore');
    expect(kWhatsNewSignOff, '— Josh');
    expect(kWhatsNewPagerTitle, isNot(contains('0.1.1')));
  });
}
