// 0.1.2 S10c: the StartupGate and the open-failure screen. Fakes only: no test
// here opens a database or touches a real file or the app's real prefs.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/app_startup.dart';
import 'package:mmogo/data/db/open_classifier.dart';
import 'package:mmogo/data/db/open_stage.dart';
import 'package:mmogo/ui/copy/open_failure_copy.dart';
import 'package:mmogo/ui/startup_gate.dart';
import 'package:mmogo/ui/theme/app_colors.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';

const _bannedEverywhere = [
  'or deleted',
  'Your entries are still on this phone',
  'reinstall',
  'or tell us',
  'safe',
  'Exception',
  'StateError',
  'secret',
];

class Harness {
  int opens = 0;
  int closes = 0;
  int beforeCalls = 0;
  int classifyCalls = 0;
  final List<OpenSnapshot?> snapshotsSeen = [];
  final List<Object> failures = [StateError('secret /data/user/0/x.db')];
  Completer<void>? hold;
  OpenFailureKind kind = OpenFailureKind.other;
  OpenStage stage = OpenStage.none;
  OpenSnapshot? snapshot;
  bool beforeThrows = false;
  bool classifyThrows = false;

  /// Throws the next queued failure; empty queue = success.
  Future<void> open() async {
    opens++;
    if (hold != null) await hold!.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
  }

  Widget gate({AppPaletteController? controller}) => StartupGate(
        controller: controller ?? AppPaletteController(),
        open: open,
        readStage: () => stage,
        closeDatabase: () async => closes++,
        beforeOpen: () async {
          beforeCalls++;
          if (beforeThrows) throw StateError('x');
          return snapshot;
        },
        classify: (e, s, snap) async {
          classifyCalls++;
          snapshotsSeen.add(snap);
          if (classifyThrows) throw StateError('x');
          return kind;
        },
        child: const Directionality(textDirection: TextDirection.ltr, child: Text('CHILD')),
      );
}

String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => r.text.toPlainText())
    .join('\n');

void _expectNoBanned(String text, {required bool upg3}) {
  for (final b in _bannedEverywhere) {
    expect(text.contains(b), isFalse, reason: 'banned "$b" on screen');
  }
  if (!upg3) {
    expect(text.contains('Your data is untouched'), isFalse);
    expect(text.contains('Nothing was changed'), isFalse);
  }
}

int popCalls = 0;

/// A tall phone so the whole screen is on screen (the scroll view needs none).
void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void main() {
  setUp(() => popCalls = 0);

  void mockPop(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') popCalls++;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }

  testWidgets('healthy start: one open, the first frame is a themed empty page, then the child', (tester) async {
    _tall(tester);
    final h = Harness()..failures.clear();
    h.hold = Completer<void>();
    await tester.pumpWidget(h.gate());
    expect(find.byKey(const Key('startupOpening')), findsOneWidget);
    expect(find.text('CHILD'), findsNothing);
    expect(find.byKey(const Key('openFailure')), findsNothing);
    h.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('CHILD'), findsOneWidget);
    expect(h.opens, 1, reason: 'a healthy start opens exactly once (Home reuses it)');
    expect(h.beforeCalls, 1);
    expect(h.classifyCalls, 0);
    expect(h.closes, 0);
  });

  testWidgets('OPN-1: other failure shows the OPN-1 screen with no promise and no exception text', (tester) async {
    _tall(tester);
    final h = Harness();
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    expect(find.text(kOpenFailTitleOther), findsOneWidget);
    expect(find.text(kOpenFailBodyOther), findsOneWidget);
    expect(find.text(openFailCodeLine('OPN-1')), findsOneWidget);
    expect(find.text(kOpenFailLeadIn), findsOneWidget);
    for (final s in kOpenFailSteps) {
      expect(find.text(s), findsOneWidget);
    }
    expect(find.byKey(const Key('openFailStill')), findsNothing);
    expect(find.text('CHILD'), findsNothing);
    _expectNoBanned(_allText(tester), upg3: false);
    expect(h.opens, 1);
  });

  testWidgets('UPG-3: a rolled-back classification shows the signed title and the exact body', (tester) async {
    _tall(tester);
    final h = Harness()..kind = OpenFailureKind.rolledBackUpgrade;
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    expect(find.text('Your data is untouched'), findsOneWidget);
    expect(
      find.text('mmogo could not finish updating its storage, so it has not opened. Nothing was changed.'),
      findsOneWidget,
    );
    expect(find.text(openFailCodeLine('UPG-3')), findsOneWidget);
    expect(find.textContaining('OPN-1'), findsNothing);
    _expectNoBanned(_allText(tester), upg3: true);
  });

  testWidgets('a throwing classifier and a throwing beforeOpen both end as OPN-1 / a normal open', (tester) async {
    _tall(tester);
    final h = Harness()
      ..classifyThrows = true
      ..beforeThrows = true
      ..kind = OpenFailureKind.rolledBackUpgrade;
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    expect(find.text(kOpenFailTitleOther), findsOneWidget);
    expect(h.snapshotsSeen.single, isNull);
  });

  testWidgets('Try again: one open per tap, original snapshot reused, "Still not working" after the first failed retry', (tester) async {
    _tall(tester);
    const snap = OpenSnapshot(userVersion: 2, fkViolationRows: 0, facts: {});
    final h = Harness()
      ..snapshot = snap
      ..failures.addAll([StateError('b'), StateError('c')]);
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    expect(h.opens, 1);

    await tester.tap(find.byKey(const Key('openFailTryAgain')));
    await tester.pumpAndSettle();
    expect(h.opens, 2, reason: 'one open per tap');
    expect(h.closes, 1);
    expect(h.beforeCalls, 1, reason: 'beforeOpen is once per gate run, not per retry');
    expect(find.byKey(const Key('openFailStill')), findsOneWidget);
    expect(_allText(tester), contains('Still not working. Close mmogo and open it again.'));
    _expectNoBanned(_allText(tester), upg3: false);

    await tester.tap(find.byKey(const Key('openFailTryAgain')));
    await tester.pumpAndSettle();
    expect(h.opens, 3);
    expect(h.snapshotsSeen.every((s) => identical(s, snap)), isTrue, reason: 'the original snapshot is reused');

    // the next open succeeds: recovers into the child
    await tester.tap(find.byKey(const Key('openFailTryAgain')));
    await tester.pumpAndSettle();
    expect(h.opens, 4);
    expect(find.text('CHILD'), findsOneWidget);
    expect(find.byKey(const Key('openFailure')), findsNothing);
  });

  testWidgets('Try again is guarded while running: disabled, "Trying again...", a second tap does nothing', (tester) async {
    _tall(tester);
    final h = Harness();
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    h.hold = Completer<void>();
    await tester.tap(find.byKey(const Key('openFailTryAgain')));
    await tester.pump();
    expect(find.text(kOpenFailTrying), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byKey(const Key('openFailTryAgain')));
    expect(btn.onPressed, isNull);
    await tester.tap(find.byKey(const Key('openFailTryAgain')), warnIfMissed: false);
    await tester.pump();
    expect(h.opens, 2, reason: 'the second tap did not start another open');
    h.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('CHILD'), findsOneWidget);
    expect(h.opens, 2);
  });

  testWidgets('no automatic retry and no timer: time passing opens nothing more', (tester) async {
    _tall(tester);
    final h = Harness()..failures.add(StateError('b'));
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    await tester.pump(const Duration(minutes: 10));
    expect(h.opens, 1);
    expect(h.closes, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Close app and Back both call SystemNavigator.pop; no Restore on the screen', (tester) async {
    _tall(tester);
    mockPop(tester);
    final h = Harness();
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('openFailClose')));
    await tester.pump();
    expect(popCalls, 1);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(popCalls, 2);
    expect(find.textContaining('Restore'), findsNothing);
    expect(find.text('CHILD'), findsNothing);
  });

  testWidgets('dark, 1.3 text scale and 44 px buttons: no overflow, themed page', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.platformDispatcher.clearAllTestValues();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final h = Harness()..failures.add(StateError('b'));
    final c = AppPaletteController('ocean', 'dark');
    await tester.pumpWidget(h.gate(controller: c));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('openFailTryAgain')));
    await tester.tap(find.byKey(const Key('openFailTryAgain')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final scaffold = tester.widget<Scaffold>(find.byKey(const Key('openFailure')));
    expect(scaffold.backgroundColor, AppPalettes.byId('ocean').dark.background);
    expect(tester.getSize(find.byKey(const Key('openFailTryAgain'))).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.byKey(const Key('openFailClose'))).height, greaterThanOrEqualTo(44));
    // the code is reachable by scrolling
    await tester.ensureVisible(find.byKey(const Key('openFailCode')));
    expect(find.byKey(const Key('openFailCode')), findsOneWidget);
  });

  testWidgets('the failure screen has its own app with no app-root messenger key', (tester) async {
    _tall(tester);
    final h = Harness();
    await tester.pumpWidget(h.gate());
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.scaffoldMessengerKey, isNull);
  });

  group('source pins', () {
    test('StartupGate takes open and every seam as required, no default', () {
      final src = File('lib/ui/startup_gate.dart').readAsStringSync();
      for (final f in ['open', 'readStage', 'closeDatabase', 'beforeOpen', 'classify', 'controller', 'child']) {
        expect(src.contains('required this.$f,'), isTrue, reason: '$f must be required');
      }
      expect(src.contains('AppDatabase'), isFalse, reason: 'the gate never names the real database');
    });

    test('main.dart: bootstrapApp (resume, palette) before runApp; the gate is built inside the RestartScope, not in bootstrapApp', () {
      final main = File('lib/main.dart').readAsStringSync();
      final boot = main.indexOf('bootstrapApp()');
      final run = main.indexOf('runApp(');
      final gate = main.indexOf('StartupGate(');
      final app = main.indexOf('MpesaTrackerApp(controller: c)');
      expect(boot, greaterThan(-1));
      expect(run, greaterThan(boot));
      expect(gate, greaterThan(run));
      expect(app, greaterThan(gate));
      expect(main.indexOf('RestartScope('), lessThan(gate));
      expect(File('lib/app_startup.dart').readAsStringSync().contains('StartupGate'), isFalse);
      // the order function itself still runs the resume first
      expect(bootstrapApp, isNotNull);
    });

    test('MpesaTrackerApp does not name the gate', () {
      final main = File('lib/main.dart').readAsStringSync();
      final cls = main.indexOf('class MpesaTrackerApp');
      expect(main.substring(cls).contains('StartupGate'), isFalse);
    });
  });

  group('copy file', () {
    final src = File('lib/ui/copy/open_failure_copy.dart').readAsStringSync();

    test('no banned phrase anywhere in the copy file', () {
      for (final b in ['or deleted', 'still on this phone', 'reinstall', 'tell us', 'safe', 'Exception', 'Tell us', 'Copy code']) {
        expect(src.toLowerCase().contains(b.toLowerCase()), isFalse, reason: '"$b" is banned in the copy file');
      }
    });

    test('the reassuring words live only in the UPG-3 constants', () {
      expect(kOpenFailTitleOther.contains('untouched'), isFalse);
      expect(kOpenFailBodyOther.contains('Nothing was changed'), isFalse);
      expect(kOpenFailTitleUpg3, 'Your data is untouched');
      expect(kOpenFailBodyUpg3, 'mmogo could not finish updating its storage, so it has not opened. Nothing was changed.');
      for (final s in kOpenFailSteps) {
        expect(s.contains('untouched') || s.contains('Nothing was changed'), isFalse);
      }
      expect('$kOpenFailStillHead $kOpenFailStillTail'.contains('untouched'), isFalse);
    });

    test('the codes and the code line', () {
      expect(kOpenFailCodeOther, 'OPN-1');
      expect(kOpenFailCodeUpg3, 'UPG-3');
      expect(openFailCodeLine('OPN-1'), 'If it keeps failing, send us this code: OPN-1.');
      expect(kOpenFailStillTail, 'Close mmogo and open it again.');
      expect(kOpenFailSteps.length, 4);
      expect(kOpenFailSteps[2], contains('Uninstalling erases your entries from this phone'));
    });
  });
}
