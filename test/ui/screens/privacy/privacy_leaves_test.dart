// 0.1.2 S11a (A6): the Privacy page's "What exactly leaves the phone" detail is
// collapsed; the first line and the "goes online once" line stay visible
// outside it. 44 px, expanded / collapsed semantics, dark and text scale 1.3.
// Static page: no prefs read, no network, no real Backup page.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/ui/copy/data_copy.dart';
import 'package:mmogo/ui/copy/privacy_copy.dart';
import 'package:mmogo/ui/screens/privacy/privacy_screen.dart';
import 'package:mmogo/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _toggle = Key('privacyLeavesToggle');

Future<void> _pump(WidgetTester tester, {bool dark = false, double scale = 1.0, Size size = const Size(400, 3200)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          platformBrightness: dark ? Brightness.dark : Brightness.light,
          textScaler: TextScaler.linear(scale),
        ),
        child: child!,
      ),
      home: const PrivacyScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('collapsed at first: the detail is hidden, the first line and the once-online line are visible', (tester) async {
    await _pump(tester);
    expect(find.text(kPrivacySentenceStandard), findsOneWidget);
    expect(find.text(kPrivacyCheckNowOnce), findsOneWidget);
    expect(find.text(kPrivacyLeavesToggle), findsOneWidget);
    expect(find.text(kNetworkDisclosure), findsNothing);
    expect(find.text(kPrivacyLeavesBody), findsNothing);
    expect(find.byKey(const Key('privacyLeavesDetail')), findsNothing);
  });

  testWidgets('tapping the toggle opens the detail (both sentences); tapping again closes it; the once line stays', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.text(kNetworkDisclosure), findsOneWidget);
    expect(find.text(kPrivacyLeavesBody), findsOneWidget);
    expect(find.text(kPrivacyCheckNowOnce), findsOneWidget);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.text(kNetworkDisclosure), findsNothing);
    expect(find.text(kPrivacyLeavesBody), findsNothing);
    expect(find.text(kPrivacyCheckNowOnce), findsOneWidget);
  });

  testWidgets('the once-online line is outside the expander: below the toggle in both states, never inside the detail', (tester) async {
    await _pump(tester);
    final onceY = tester.getTopLeft(find.byKey(const Key('privacyCheckNowOnce'))).dy;
    expect(onceY, greaterThan(tester.getTopLeft(find.byKey(_toggle)).dy));
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    final detailY = tester.getTopLeft(find.byKey(const Key('privacyLeavesDetail'))).dy;
    expect(tester.getTopLeft(find.byKey(const Key('privacyCheckNowOnce'))).dy, greaterThan(detailY));
    expect(kNetworkDisclosure, isNot(contains('goes online once')));
    expect(kPrivacyLeavesBody, isNot(contains('goes online once')));
  });

  testWidgets('semantics: a button that says expanded or collapsed', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    var node = tester.getSemantics(find.byKey(_toggle));
    expect(node.label, kPrivacyLeavesToggle);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.flagsCollection.isExpanded, Tristate.isFalse);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    node = tester.getSemantics(find.byKey(_toggle));
    expect(node.flagsCollection.isExpanded, Tristate.isTrue);
    handle.dispose();
  });

  testWidgets('the toggle is at least 44 px high, also at text scale 1.3', (tester) async {
    await _pump(tester);
    expect(tester.getSize(find.byKey(_toggle)).height, greaterThanOrEqualTo(44));
    await _pump(tester, scale: 1.3);
    expect(tester.getSize(find.byKey(_toggle)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('dark and 1.3 on a small screen: opens without overflow and the detail reads', (tester) async {
    await _pump(tester, dark: true, scale: 1.3, size: const Size(360, 700));
    await tester.scrollUntilVisible(find.byKey(_toggle), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('privacyLeavesDetail')));
    expect(find.text(kPrivacyLeavesBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no D7 line on the Privacy page', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(_toggle));
    await tester.pumpAndSettle();
    expect(find.textContaining(kBackupNotRestorableByOlder), findsNothing);
  });
}
