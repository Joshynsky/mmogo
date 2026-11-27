// 0.2.1 #10: a What's new link opens Settings at an area and outlines it; the button passes its id.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mmogo/autoread/autoread_feature.dart';
import 'package:mmogo/ui/screens/settings/settings_targets.dart';
import 'package:mmogo/ui/screens/settings_screen.dart';
import 'package:mmogo/ui/theme/app_palette_scope.dart';
import 'package:mmogo/ui/whats_new/whats_new_pager.dart';
import 'package:mmogo/ui/widgets/highlight_pulse.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../support/fake_delete_data.dart';

class _CountDb implements Database {
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async => [
    {'cnt': 0},
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, {String? request, double height = 800}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  HighlightRequest.set(request);
  await tester.pumpWidget(
    MaterialApp(
      home: AppPaletteScope(controller: AppPaletteController(), child: SettingsScreen(db: _CountDb(), exportCsv: (_, _) async {})),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder _outlineIn(String key) =>
    find.descendant(of: find.ancestor(of: find.byKey(Key(key)), matching: find.byType(HighlightPulse)), matching: find.byKey(const Key('highlightOutline')));

void main() {
  setUp(() {
    useFakeDeleteData();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('receiver link: the receiver row is outlined and nothing else', (tester) async {
    await _pump(tester, request: kSettingsTargetCaptureReceiver);
    expect(find.byKey(const Key('highlightOutline')), findsOneWidget);
    expect(_outlineIn('settingsCaptureReceiver'), findsOneWidget);
    await tester.pump(kHighlightDuration + const Duration(seconds: 1));
  });

  testWidgets('remembered link on a short phone: the row is outlined and on screen', (tester) async {
    await _pump(tester, request: kSettingsTargetRemembered, height: 500);
    expect(_outlineIn('settingsRemembered'), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('settingsRemembered'))).dy, inInclusiveRange(0, 500));
    await tester.pump(kHighlightDuration + const Duration(seconds: 1));
  });

  testWidgets('reading link (auto-read build): the Reading section is outlined', (tester) async {
    await _pump(tester, request: kSettingsTargetReading);
    expect(find.byKey(const Key('highlightOutline')), findsOneWidget);
    await tester.pump(kHighlightDuration + const Duration(seconds: 1));
  }, skip: !kAutoReadCompiled);

  testWidgets('no request: nothing is outlined', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('highlightOutline')), findsNothing);
  });

  testWidgets('Settings takes the request: it does not leak into the next visit', (tester) async {
    await _pump(tester, request: kSettingsTargetCaptureReceiver);
    expect(HighlightRequest.take(), isNull);
    await tester.pump(kHighlightDuration + const Duration(seconds: 1));
  });

  testWidgets('the Open in Settings button hands its id to the opener', (tester) async {
    final got = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            key: const Key('go'),
            onPressed: () => showWhatsNewPager(context, onOpenSettings: got.add, onOpenBackup: () {}),
            child: const Text('x'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('go')));
    await tester.pumpAndSettle();
    const head = Key('whatsNewItemHead-autorecord');
    await tester.ensureVisible(find.byKey(head));
    await tester.pumpAndSettle();
    // Auto-record is the first row and starts open.
    await tester.ensureVisible(find.byKey(const Key('whatsNewCalSettings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('whatsNewCalSettings')));
    await tester.pumpAndSettle();
    expect(got, [kSettingsTargetRemembered]);
  }, skip: !kAutoReadCompiled);
}
